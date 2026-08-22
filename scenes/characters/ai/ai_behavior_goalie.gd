class_name AIBehaviorGoalie
extends AIBehavior

## 门将 AI 行为
## 包含：站位、出击、扑救、抱球、发球

const PROXIMITY_CONCERN := 10.0
const CATCH_RADIUS := 18.0           ## 抱球范围（像素）
const RUSH_OUT_DISTANCE := 100.0    ## 最大出击距离（离球门线）
const RUSH_OUT_TRIGGER_DIST := 120.0  ## 触发出击的球距球门距离
const HOLD_DURATION_MIN_MS := 1500  ## 最少抱球时间
const HOLD_DURATION_MAX_MS := 3000  ## 最多抱球时间
const DISTRIBUTION_KICK_DIST := 150.0 ## 大脚开球的最小目标距离
const DIVING_SAVE_DISTANCE := 80.0  ## 飞身扑救的触发距离

var time_ball_held_ms := 0

func perform_ai_movement() -> void:
	if ball.carrier == player:
		# 抱球时不移动，等待发球决策
		player.velocity = Vector2.ZERO
		return

	var total_steering_force := Vector2.ZERO

	if _should_rush_out():
		total_steering_force += _get_rush_out_steering_force()
	else:
		total_steering_force += get_goalie_steering_force()

	total_steering_force = total_steering_force.limit_length(1.0)
	player.velocity = total_steering_force * player.speed

func perform_ai_decisions() -> void:
	if ball.carrier == player:
		_decide_distribution()
		return

	# 检查是否能抱球
	if _can_catch_ball():
		_catch_ball()
		return

	# 检查是否需要飞身扑救
	if ball.is_headed_for_scoring_area(player.own_goal.get_scoring_area()):
		var ball_dist := player.position.distance_to(ball.position)
		if ball_dist < DIVING_SAVE_DISTANCE:
			# 只有在移动状态下才能扑救（不在扑救/恢复动作中）
			if player.can_carry_ball():
				player.switch_state(Player.State.DIVING)

func _can_catch_ball() -> bool:
	## 判断是否能抱住球
	if ball.carrier != null and ball.carrier.country == player.country and ball.carrier != player:
		return false  # 队友带的球不能抢
	# 球太高抱不到
	if ball.height > PitchConstants.HEIGHT_GOALIE_CATCH_MAX:
		return false
	var dist := player.position.distance_to(ball.position)
	return dist < CATCH_RADIUS

func _catch_ball() -> void:
	## 抱住球
	time_ball_held_ms = Time.get_ticks_msec()
	ball.hold_by_goalkeeper(player)

func _decide_distribution() -> void:
	## 决定如何发球：手抛球 或 大脚开球
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
	if randf() < urgency * 0.05:
		_distribute_ball()

func _distribute_ball() -> void:
	## 发球：根据场上情况选手抛球或大脚
	var target := _find_distribution_target()
	var target_pos := Vector2.ZERO

	if target != null:
		var dist_to_target := player.position.distance_to(target.position)
		if dist_to_target > DISTRIBUTION_KICK_DIST:
			# 距离远 → 大脚开球
			target_pos = target.position
			ball.release_with_kick(target_pos)
		else:
			# 距离近 → 手抛球
			target_pos = target.position
			ball.release_with_throw(target_pos)
	else:
		# 没有目标 → 朝前方踢
		var direction := player.heading
		target_pos = player.position + direction * 200.0
		ball.release_with_kick(target_pos)

	# 球发出后回到移动状态（通过 state 切换会自动处理）
	player.switch_state(Player.State.MOVING)

func _find_distribution_target() -> Player:
	## 找发球目标（前场队友优先）
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

		# 越靠前的队友越优先（更靠近对方球门）
		var goal_pos := player.target_goal.get_center_target_position()
		var dist_to_opponent_goal := teammate.position.distance_to(goal_pos)
		var score: float = 1.0 - clamp(dist_to_opponent_goal / 300.0, 0.0, 1.0)

		if score > best_score:
			best_score = score
			best_target = teammate

	return best_target

func _should_rush_out() -> bool:
	## 判断是否应该出击
	# 球不在危险区域就不出击
	if not _is_ball_approaching_goal():
		return false

	# 球被对方带着 → 可以考虑出击
	if ball.carrier != null and ball.carrier.country != player.country:
		var dist_to_goal := ball.position.distance_to(player.own_goal.get_center_target_position())
		return dist_to_goal < RUSH_OUT_TRIGGER_DIST

	# 球飞向球门 → 不出击，站位扑救
	return false

func _is_ball_approaching_goal() -> bool:
	## 判断球是否在接近球门
	var goal_center := player.own_goal.get_center_target_position()
	var to_goal := goal_center - ball.position
	return ball.velocity.dot(to_goal) > 0  # 速度朝向球门方向

func _get_rush_out_steering_force() -> Vector2:
	## 出击：向前缩小角度，同时保持在球和球门之间
	var goal_center := player.own_goal.get_center_target_position()
	var ball_pos := ball.position

	# 出击的目标位置：在球和球门之间，靠近球但不超过最大出击距离
	var goal_to_ball := ball_pos - goal_center
	var dist_ball_to_goal := goal_to_ball.length()

	if dist_ball_to_goal < 1.0:
		return Vector2.ZERO

	var rush_distance: float = min(dist_ball_to_goal * 0.4, RUSH_OUT_DISTANCE)
	var target_pos: Vector2 = goal_center + goal_to_ball.normalized() * rush_distance

	# 同时调整 Y 轴对齐球
	target_pos.y = clamp(ball_pos.y,
		player.own_goal.get_top_target_position().y,
		player.own_goal.get_bottom_target_position().y)

	var direction := player.position.direction_to(target_pos)
	var dist_to_target := player.position.distance_to(target_pos)
	var weight: float = clamp(dist_to_target / 20.0, 0.0, 1.0)

	return weight * direction

func get_goalie_steering_force() -> Vector2:
	var top := player.own_goal.get_top_target_position()
	var bottom := player.own_goal.get_bottom_target_position()
	var center := player.spawn_position
	var target_y: float = clampf(ball.position.y, top.y, bottom.y)
	var destination := Vector2(center.x, target_y)
	var direction := player.position.direction_to(destination)
	var distance_to_destination := player.position.distance_to(destination)
	var weight: float = clampf(distance_to_destination / PROXIMITY_CONCERN, 0, 1)
	return weight * direction
