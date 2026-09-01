class_name AIBehaviorGoalie
extends AIBehavior

## 门将 AI 行为（反应式决策树，非分层式）
##
## 设计原则：
## - 扁平决策树：所有决策在 perform_ai_decisions() 中按优先级判断
## - 事件驱动：球侧检测（body_entered）负责帧级的抱球/扑救触发
## - AI tick 只负责：位置决策、时机判断、发球选择
##
## 决策优先级（从高到低）：
##   1. 持有球 → 决定发球
##   2. 近距离可抱球 → 抱球兜底
##   3. 球飞向球门且赶不上 → 飞身扑救
##   4. 应该出击 → 出击拦截
##   5. 默认 → 门线站位

const AI_TICK_MS := 80              ## 门将 AI tick 频率（比普通球员快）
const PROXIMITY_CONCERN := 10.0
const CATCH_PREDICT_MS := 120        ## 抱球预判时间（ms），看未来这个时间内球是否会进入范围
const HOLD_DURATION_MIN_MS := 1500   ## 最少抱球时间
const HOLD_DURATION_MAX_MS := 3000   ## 最多抱球时间
const DIVING_REACTION_TIME := 0.15   ## 门将反应时间（秒），低于这个时间赶不上就扑救
const GROUND_BALL_HEIGHT := 5.0      ## 视为地滚球的高度阈值

## 距离判断（使用 PitchConstants 集中管理）
const CATCH_RADIUS := PitchConstants.AI.GOALIE_CATCH_RADIUS
const RUSH_OUT_DISTANCE := PitchConstants.AI.GOALIE_RUSH_OUT_DISTANCE
const RUSH_OUT_TRIGGER_DIST := PitchConstants.AI.GOALIE_RUSH_OUT_TRIGGER_DIST
const DISTRIBUTION_KICK_DIST := PitchConstants.AI.GOALIE_DISTRIBUTION_KICK_DIST
const DIVING_SAVE_DISTANCE := PitchConstants.AI.GOALIE_DIVING_SAVE_DISTANCE

var time_ball_held_ms := 0
var time_since_last_ai_tick_goalie := 0
var was_holding_ball := false

func _ready() -> void:
	time_since_last_ai_tick_goalie = Time.get_ticks_msec() + randi_range(0, AI_TICK_MS)

func _process(_delta: float) -> void:
	var is_holding_ball := ball != null and ball.carrier == player
	if is_holding_ball and not was_holding_ball:
		time_ball_held_ms = Time.get_ticks_msec()
	elif not is_holding_ball:
		time_ball_held_ms = 0
	was_holding_ball = is_holding_ball

	# 发球决策不能依赖门将当前是否处于 MOVING；扑救抱球后也必须继续运行。
	# 无球时仍由球员状态机调度，避免干扰 RESETING 等动作状态。
	if is_holding_ball and player.control_scheme == Player.ControlScheme.CPU:
		process_ai()

func process_ai() -> void:
	# 门将使用自己的 tick 频率（更快）
	if Time.get_ticks_msec() - time_since_last_ai_tick_goalie > AI_TICK_MS:
		time_since_last_ai_tick_goalie = Time.get_ticks_msec()
		perform_ai_movement()
		perform_ai_decisions()

# ============================================================
# 移动决策
# ============================================================

func perform_ai_movement() -> void:
	if ball.carrier == player:
		# 抱球时不移动
		player.velocity = Vector2.ZERO
		return

	var total_force := Vector2.ZERO

	if _should_rush_out():
		total_force += _get_rush_out_steering_force()
	else:
		total_force += _get_positioning_steering_force()

	total_force = total_force.limit_length(1.0)
	player.velocity = total_force * player.speed

# ============================================================
# 决策树（按优先级从高到低）
# ============================================================

func perform_ai_decisions() -> void:
	# 优先级 1：持有球 → 决定发球
	if ball.carrier == player:
		_decide_distribution()
		return

	# 优先级 2：近距离能直接抱球 → 抱球（兜底防止漏球）
	if _can_catch_ball():
		_catch_ball()
		return

	# 优先级 3：球飞向球门且需要飞身扑救 → 扑救
	if _should_dive_save():
		_dive_save()
		return

	# 优先级 4 & 5：出击/站位 → 已在 perform_ai_movement 中处理

# ============================================================
# 抱球逻辑
# ============================================================

func _can_catch_ball() -> bool:
	## 判断门将是否能抱住球
	## 检查项：队友带球排除 + 高度 + 当前距离 + 预判距离
	if ball.is_recapture_locked_for(player):
		return false

	# 队友带的球不能抢
	if ball.carrier != null and ball.carrier.country == player.country and ball.carrier != player:
		return false

	# 球太高抱不到
	if ball.height > PitchConstants.HEIGHT_GOALIE_CATCH_MAX:
		return false

	# 当前距离是否在抱球范围内
	var dist := player.position.distance_to(ball.position)
	if dist < CATCH_RADIUS:
		return true

	# 预判：球在短时间内是否会进入抱球范围
	var predict_time := float(CATCH_PREDICT_MS) / 1000.0
	var future_ball_pos := ball.position + ball.velocity * predict_time
	var future_dist := player.position.distance_to(future_ball_pos)
	if future_dist < CATCH_RADIUS:
		# 同时检查预判时刻的高度
		var future_height := ball.predict_height_at_time(predict_time)
		if future_height <= PitchConstants.HEIGHT_GOALIE_CATCH_MAX:
			return true

	return false

func _catch_ball() -> void:
	## 抱住球
	time_ball_held_ms = Time.get_ticks_msec()
	was_holding_ball = true
	ball.hold_by_goalkeeper(player)

# ============================================================
# 飞身扑救
# ============================================================

func _should_dive_save() -> bool:
	## 判断是否需要飞身扑救
	## 条件：球飞向球门 + 门将靠移动赶不上 + 球在扑救范围内

	if not player.can_carry_ball():
		return false  # 正在做其他动作（扑救中、恢复中等），不能再扑

	# 检查球是否会飞入球门
	var goal_x := player.own_goal.get_center_target_position().x
	var goal_top := player.own_goal.get_top_target_position().y
	var goal_bottom := player.own_goal.get_bottom_target_position().y

	if not ball.will_reach_goal_area(goal_x, goal_top, goal_bottom):
		# 射线作为近距离补充判断
		if not ball.is_headed_for_scoring_area(player.own_goal.get_scoring_area()):
			return false

	# 球距离门将太远 → 不扑救（用移动去拦截）
	var ball_dist := player.position.distance_to(ball.position)
	if ball_dist > DIVING_SAVE_DISTANCE:
		return false

	# 估算球到达门将位置的时间
	var time_to_goalie := _estimate_time_to_reach_goalie()
	if time_to_goalie < 0 or time_to_goalie > 1.0:
		return false  # 球不会到达，或者时间太长用移动就行

	# 如果球很快就到（赶不上移动拦截）→ 飞身扑救
	if time_to_goalie < DIVING_REACTION_TIME:
		return true

	return false

func _dive_save() -> void:
	## 触发飞身扑救
	player.switch_state(Player.State.DIVING)

func _estimate_time_to_reach_goalie() -> float:
	## 估算球到达门将所在 x 坐标的时间（秒）
	## 如果球不朝门将方向移动，返回 -1
	if abs(ball.velocity.x) < 1.0:
		return -1

	var dx := player.position.x - ball.position.x
	# 球不朝门将方向移动
	if dx * ball.velocity.x < 0:
		return -1

	var speed: float = abs(ball.velocity.x)
	# 考虑摩擦减速，用平均速度估算
	var avg_speed: float = speed * 0.75
	return abs(dx) / max(avg_speed, 1.0)

# ============================================================
# 出击判断
# ============================================================

func _should_rush_out() -> bool:
	## 判断是否应该出击拦截
	## 三种情况：
	## 1. 对方带球接近禁区
	## 2. 无主球飞向禁区（预判落点在出击范围内）
	## 3. 慢速地滚球靠近球门

	var goal_center := player.own_goal.get_center_target_position()
	var dist_ball_to_goal := ball.position.distance_to(goal_center)

	# 球离球门太远 → 不出击
	if dist_ball_to_goal > RUSH_OUT_TRIGGER_DIST:
		return false

	# 球在球门后面 → 不出击（已经进了或出界了）
	var goal_dir := player.own_goal.goal_facing_dir
	if (ball.position - goal_center).dot(-goal_dir) < 0:
		return false

	# 情况 1：对方带球 → 出击
	if ball.carrier != null and ball.carrier.country != player.country:
		return true

	# 情况 2 & 3：无主球
	if ball.carrier == null:
		# 球不朝球门移动 → 不出击
		if not _is_ball_approaching_goal():
			return false

		# 预判落点是否在出击范围内
		var landing_pos := ball.predict_landing_position()
		var dist_landing_to_goal := landing_pos.distance_to(goal_center)
		if dist_landing_to_goal < RUSH_OUT_DISTANCE:
			return true

		# 地滚球接近球门 → 出击抱球
		if ball.height < GROUND_BALL_HEIGHT and dist_ball_to_goal < RUSH_OUT_DISTANCE:
			return true

	return false

func _is_ball_approaching_goal() -> bool:
	## 判断球是否在接近球门
	var goal_center := player.own_goal.get_center_target_position()
	var to_goal := goal_center - ball.position
	return ball.velocity.dot(to_goal) > 0  # 速度朝向球门方向

# ============================================================
# 移动力计算
# ============================================================

func _get_rush_out_steering_force() -> Vector2:
	## 出击：在球和球门之间，同时保持 Y 轴对齐球
	var goal_center := player.own_goal.get_center_target_position()
	var ball_pos := ball.position

	var goal_to_ball := ball_pos - goal_center
	var dist_ball_to_goal := goal_to_ball.length()

	if dist_ball_to_goal < 1.0:
		return Vector2.ZERO

	# 出击目标：在球和球门之间，距离球门 = min(球距 * 0.5, 最大出击距离)
	var rush_distance: float = min(dist_ball_to_goal * 0.5, RUSH_OUT_DISTANCE)
	var target_pos: Vector2 = goal_center + goal_to_ball.normalized() * rush_distance

	# Y 轴对齐球的位置（约束在球门范围内）
	target_pos.y = clamp(ball_pos.y,
		player.own_goal.get_top_target_position().y,
		player.own_goal.get_bottom_target_position().y)

	var direction := player.position.direction_to(target_pos)
	var dist_to_target := player.position.distance_to(target_pos)
	var weight: float = clamp(dist_to_target / 20.0, 0.0, 1.0)

	return weight * direction

func _get_positioning_steering_force() -> Vector2:
	## 门线站位：对齐球的位置，球飞向球门时用预判位置
	var top := player.own_goal.get_top_target_position()
	var bottom := player.own_goal.get_bottom_target_position()
	var center := player.spawn_position

	# 默认：对齐球的 y 坐标
	var target_y: float = clampf(ball.position.y, top.y, bottom.y)

	# 如果球飞向球门，用预判的球门线 y 坐标
	var goal_x: float = player.own_goal.get_center_target_position().x
	var goal_y: float = ball.predict_goal_line_y(goal_x)
	if goal_y != INF:
		target_y = clampf(goal_y, top.y, bottom.y)

	var destination := Vector2(center.x, target_y)
	var direction := player.position.direction_to(destination)
	var distance_to_destination := player.position.distance_to(destination)
	var weight: float = clampf(distance_to_destination / PROXIMITY_CONCERN, 0, 1)
	return weight * direction

# ============================================================
# 发球决策
# ============================================================

func _decide_distribution() -> void:
	## 决定何时发球以及如何发球
	var time_held := Time.get_ticks_msec() - time_ball_held_ms

	# 最少抱球时间内不发球
	if time_held < HOLD_DURATION_MIN_MS:
		return

	# 超过最大抱球时间必须发球
	if time_held > HOLD_DURATION_MAX_MS:
		_distribute_ball()
		return

	# 概率性决定发球时机（越接近最大时间，概率越高）
	var urgency := float(time_held - HOLD_DURATION_MIN_MS) / (HOLD_DURATION_MAX_MS - HOLD_DURATION_MIN_MS)
	if randf() < urgency * 0.08:
		_distribute_ball()

func _distribute_ball() -> void:
	## 发球：根据场上情况选手抛球或大脚
	var target := _find_best_distribution_target()

	if target != null:
		var dist_to_target := player.position.distance_to(target.position)
		if dist_to_target > DISTRIBUTION_KICK_DIST:
			# 距离远 → 大脚开球
			ball.release_with_kick(target.position)
		else:
			# 距离近 → 手抛球
			ball.release_with_throw(target.position)
	else:
		# 没有目标 → 朝前方踢
		var target_pos := player.position + player.heading * 250.0
		ball.release_with_kick(target_pos)

	# 发球后回到移动状态
	player.switch_state(Player.State.MOVING)

func _find_best_distribution_target() -> Player:
	## 找最佳发球目标（前场队友优先，考虑对方封堵）
	var best_target: Player = null
	var best_score := -1.0

	for body in teammate_detection_area.get_overlapping_bodies():
		if not (body is Player):
			continue
		var teammate: Player = body
		if teammate == player or teammate.country != player.country:
			continue
		if teammate.role == Player.Role.GOALIE:
			continue

		# 越靠近对方球门的队友越优先（进攻推进）
		var goal_pos := player.target_goal.get_center_target_position()
		var dist_to_opponent_goal := teammate.position.distance_to(goal_pos)
		var pos_score: float = 1.0 - clamp(dist_to_opponent_goal / 300.0, 0.0, 1.0)

		# 对方封堵惩罚：如果有对方球员在发球路线上，降低优先级
		var safety_score := _calc_distribution_safety(teammate.position)

		var score := pos_score * 0.5 + safety_score * 0.5

		if score > best_score:
			best_score = score
			best_target = teammate

	return best_target

func _calc_distribution_safety(target_pos: Vector2) -> float:
	## 计算发球路线的安全性（对方球员在路线上的惩罚）
	## 返回 0.0-1.0，越高越安全
	var to_target := target_pos - player.position
	var dist := to_target.length()
	if dist < 1.0:
		return 1.0

	var dir := to_target / dist
	var min_dist_to_opponent := 999.0

	for body in opponent_detection_area.get_overlapping_bodies():
		if not (body is Player):
			continue
		var opponent: Player = body
		# 点到线段的距离
		var to_opp: Vector2 = opponent.position - player.position
		var proj: float = to_opp.dot(dir)
		if proj < 0 or proj > dist:
			continue  # 对方不在发球线段范围内
		var perp_dist: float = abs(to_opp.cross(dir))
		if perp_dist < min_dist_to_opponent:
			min_dist_to_opponent = perp_dist

	return clamp(min_dist_to_opponent / 30.0, 0.1, 1.0)

# ============================================================
# 兼容性：保留旧方法名（其他代码可能引用）
# ============================================================

func get_goalie_steering_force() -> Vector2:
	return _get_positioning_steering_force()
