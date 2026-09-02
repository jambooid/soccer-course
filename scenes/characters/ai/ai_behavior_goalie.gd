class_name AIBehaviorGoalie
extends AIBehavior

const GoalkeeperDecisionPolicyScript := preload("res://utils/goalkeeper_decision_policy.gd")

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
	# Stagger keeper updates without global randomness. Jersey numbers are stable
	# across squad construction and therefore produce replayable phase offsets.
	var phase_offset := posmod(player.jersey_number, maxi(AI_TICK_MS, 1))
	time_since_last_ai_tick_goalie = Time.get_ticks_msec() + phase_offset

func _physics_process(_delta: float) -> void:
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

	var decision := _goalkeeper_decision()
	var target: Vector2 = decision.get("target", player.spawn_position)
	if int(decision.kind) == GoalkeeperDecisionPolicyScript.Kind.LINE \
			or int(decision.kind) == GoalkeeperDecisionPolicyScript.Kind.SET:
		target.x = player.spawn_position.x
	var distance := player.position.distance_to(target)
	player.velocity = player.position.direction_to(target) * player.speed * clampf(distance / PROXIMITY_CONCERN, 0.0, 1.0)

# ============================================================
# 决策树（按优先级从高到低）
# ============================================================

func perform_ai_decisions() -> void:
	var decision := _goalkeeper_decision()
	# 优先级 1：持有球 → 决定发球
	if ball.carrier == player:
		if int(decision.kind) == GoalkeeperDecisionPolicyScript.Kind.DISTRIBUTE_THROW \
				or int(decision.kind) == GoalkeeperDecisionPolicyScript.Kind.DISTRIBUTE_KICK:
			_distribute_ball()
		return

	# 优先级 2：近距离能直接抱球 → 抱球（兜底防止漏球）
	if int(decision.kind) == GoalkeeperDecisionPolicyScript.Kind.CLAIM:
		_catch_ball()
		return

	# 优先级 3：球飞向球门且需要飞身扑救 → 扑救
	if int(decision.kind) == GoalkeeperDecisionPolicyScript.Kind.DIVE:
		_dive_save(decision.get("target", ball.position))
		return

	# 优先级 4 & 5：出击/站位 → 已在 perform_ai_movement 中处理

# ============================================================
# 抱球逻辑
# ============================================================

func _goalkeeper_decision() -> Dictionary:
	var goal_center := player.own_goal.get_center_target_position()
	var goal_top := player.own_goal.get_top_target_position().y
	var goal_bottom := player.own_goal.get_bottom_target_position().y
	var goal_dir := player.own_goal.goal_facing_dir
	var in_front_of_goal := (ball.position - goal_center).dot(-goal_dir) >= 0.0
	var distribution := _find_best_distribution_target() if ball.carrier == player else {}
	return GoalkeeperDecisionPolicyScript.decide({
		"holding_ball": ball.carrier == player,
		"held_seconds": float(Time.get_ticks_msec() - time_ball_held_ms) / 1000.0,
		"distribution_delay": float(HOLD_DURATION_MIN_MS) / 1000.0,
		"distribution_long": not distribution.is_empty() and bool(distribution.get("long", false)),
		"can_collect_now": ball.can_goalkeeper_collect(player),
		"opponent_carrier": ball.carrier != null and ball.carrier.country != player.country,
		"inside_rush_zone": in_front_of_goal and ball.position.distance_to(goal_center) <= RUSH_OUT_TRIGGER_DIST,
		"keeper_position": player.position,
		"keeper_speed": player.speed,
		"goal_position": goal_center,
		"goal_top": goal_top,
		"goal_bottom": goal_bottom,
		"ball_position": ball.position,
		"ball_velocity": ball.velocity,
		"ball_height": ball.height,
		"height_velocity": ball.height_velocity,
		"friction": ball.friction_ground,
		"gravity": PitchConstants.GRAVITY,
		"dive_range": DIVING_SAVE_DISTANCE,
		"save_height_max": 58.0,
	})

func _can_catch_ball() -> bool:
	return int(_goalkeeper_decision().kind) == GoalkeeperDecisionPolicyScript.Kind.CLAIM

func _catch_ball() -> void:
	## 抱住球
	time_ball_held_ms = Time.get_ticks_msec()
	was_holding_ball = true
	ball.hold_by_goalkeeper(player)

# ============================================================
# 飞身扑救
# ============================================================

func _should_dive_save() -> bool:
	return player.can_carry_ball() and int(_goalkeeper_decision().kind) == GoalkeeperDecisionPolicyScript.Kind.DIVE

func _dive_save(target: Vector2 = Vector2.ZERO) -> void:
	## 触发飞身扑救
	player.goalkeeper_dive_target = target
	player.switch_state(Player.State.DIVING)

func _estimate_time_to_reach_goalie() -> float:
	return float(_goalkeeper_decision().prediction.get("goal_eta", -1.0))

# ============================================================
# 出击判断
# ============================================================

func _should_rush_out() -> bool:
	return int(_goalkeeper_decision().kind) == GoalkeeperDecisionPolicyScript.Kind.RUSH

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
	var decision := _goalkeeper_decision()
	if int(decision.kind) == GoalkeeperDecisionPolicyScript.Kind.DISTRIBUTE_THROW \
			or int(decision.kind) == GoalkeeperDecisionPolicyScript.Kind.DISTRIBUTE_KICK:
		_distribute_ball()

func _distribute_ball() -> void:
	## 发球目标由同一地面轨迹 ETA 和对手到达时间筛选。
	var option := _find_best_distribution_target()
	var target: Player = option.get("target")

	if target != null:
		if bool(option.get("long", false)):
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

func _find_best_distribution_target() -> Dictionary:
	## 只选择接球队员先于对手到达的、可由真实地面轨迹送达的目标。
	var options: Array[Dictionary] = []

	for body in teammate_detection_area.get_overlapping_bodies():
		if not (body is Player):
			continue
		var teammate: Player = body
		if teammate == player or teammate.country != player.country:
			continue
		if teammate.role == Player.Role.GOALIE:
			continue

		var distance := player.position.distance_to(teammate.position)
		if distance <= 1.0:
			continue
		var ball_eta := sqrt(2.0 * distance / maxf(ball.friction_ground, 1.0))
		var opponent_eta := INF
		for opponent_body in opponent_detection_area.get_overlapping_bodies():
			if opponent_body is Player and opponent_body.country != player.country:
				var opponent: Player = opponent_body
				opponent_eta = minf(opponent_eta, opponent.position.distance_to(teammate.position) / maxf(opponent.speed, 1.0))

		# 越靠近对方球门的队友越优先，同时惩罚慢到达的传球。
		var goal_pos := player.target_goal.get_center_target_position()
		var dist_to_opponent_goal := teammate.position.distance_to(goal_pos)
		var pos_score: float = 1.0 - clamp(dist_to_opponent_goal / 300.0, 0.0, 1.0)
		var safety_score := clampf((opponent_eta - ball_eta) / 1.0, 0.0, 1.0)
		options.append({
			"target": teammate,
			"player_id": teammate.jersey_number,
			"rule_legal": true,
			"receiver_eta": 0.0,
			"ball_eta": ball_eta,
			"opponent_eta": opponent_eta,
			"utility": pos_score * 0.55 + safety_score * 0.45,
			"long": distance > DISTRIBUTION_KICK_DIST,
		})
	return GoalkeeperDecisionPolicyScript.select_distribution(options)

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
