class_name AIBehaviorField
extends AIBehavior

const PASS_PROBABILITY := 0.05
const SHOT_PROBABILITY := 0.3
const SPREAD_ASSIST_FACTOR := 0.8
const TACKLE_PROBABILITY := 0.3

## 距离判断（使用 PitchConstants 集中管理）
const SHOT_DISTANCE := PitchConstants.AI.SHOT_DISTANCE
const TACKLE_DISTANCE := PitchConstants.AI.TACKLE_DISTANCE
const CpuActionSelectorScript := preload("res://utils/cpu_action_selector.gd")
const TeamTacticsScript := preload("res://utils/team_tactics.gd")

## Tactical target arrival radii. Players settle into shape inside the stop
## radius and progressively slow down inside the larger radius.
const TACTICAL_STOP_RADIUS := 8.0
const TACTICAL_SLOW_RADIUS := 55.0
const PRESS_STOP_RADIUS := 3.0
const PRESS_SLOW_RADIUS := 18.0

## 带球模式 AI 参数
const SPRINT_TECH_THRESHOLD := PitchConstants.AI.SPRINT_TECH_THRESHOLD
const SPRINT_OPPONENT_MAX := 0         ## 附近对手不超过此数才冲刺
const SPRINT_DIST_TO_GOAL_MAX := PitchConstants.AI.SPRINT_DIST_TO_GOAL_MAX

## AI 转向参数（与人类玩家 TurnController 一致）
const AI_TURN_RATE_LOW := 10.0         # rad/s, 低速
const AI_TURN_RATE_HIGH := 3.5        # rad/s, 高速
const AI_SPRINT_TURN_PENALTY := 0.6

var _ai_move_direction := Vector2.RIGHT  ## AI 平滑移动方向

func perform_ai_movement() -> void:
	var total_steering_force := Vector2.ZERO
	if player.has_ball():
		total_steering_force += get_carrier_steering_force()
	elif is_ball_carried_by_teammate():
		total_steering_force += get_assist_formation_steering_force()
	else:
		total_steering_force += get_onduty_steering_force()
		if player.tactical_role.is_empty() and total_steering_force.length_squared() < 1:
			if is_ball_possessed_by_opponent():
				total_steering_force += get_spawn_steering_force()
			elif ball.carrier == null:
				total_steering_force += get_ball_proximity_steering_force()
				total_steering_force += get_density_around_ball_steering_force()

	total_steering_force = total_steering_force.limit_length(1.0)
	var intent_strength := total_steering_force.length()

	# 带球模式决策（只有持球时才需要）
	if player.has_ball():
		_decide_dribble_mode()
	else:
		player.dribble_mode = DribblePhysics.Mode.JOG

	# 速度倍率（冲刺时）
	var speed_mult := 1.0
	if player.dribble_mode == DribblePhysics.Mode.SPRINT:
		speed_mult = 1.6

	# AI 转向平滑（与人类玩家 TurnController 一致的手感）
	var target_dir := total_steering_force
	if intent_strength > 0.05:
		var ai_tick_delta := float(_get_tick_interval_ms()) / 1000.0
		_ai_apply_turning(target_dir.normalized(), ai_tick_delta)
		player.velocity = _ai_move_direction * player.speed * speed_mult * intent_strength
	else:
		player.velocity = Vector2.ZERO

	# 同步 heading
	if player.velocity.x > 0:
		player.heading = Vector2.RIGHT
	elif player.velocity.x < 0:
		player.heading = Vector2.LEFT

func _decide_dribble_mode() -> void:
	var opponent_count := _count_nearby_opponents()
	var dist_to_goal := player.position.distance_to(player.target_goal.get_center_target_position())

	# 条件：技术足够 + 附近没人 + 在进攻半场
	if player.technique >= SPRINT_TECH_THRESHOLD \
			and opponent_count <= SPRINT_OPPONENT_MAX \
			and dist_to_goal < SPRINT_DIST_TO_GOAL_MAX:
		player.dribble_mode = DribblePhysics.Mode.SPRINT
	else:
		player.dribble_mode = DribblePhysics.Mode.JOG

func _ai_apply_turning(target_direction: Vector2, delta: float) -> void:
	if target_direction.length() < 0.01:
		return
	if player.velocity.length() < player.speed * 0.1:
		_ai_move_direction = target_direction.normalized()
		return

	var current_dir: Vector2 = _ai_move_direction.normalized()
	var target_dir: Vector2 = target_direction.normalized()

	# 转向速率：速度越快转越慢；冲刺时更慢
	var speed_factor: float = clamp(player.velocity.length() / player.speed, 0.0, 1.0)
	var turn_rate: float = lerp(AI_TURN_RATE_LOW, AI_TURN_RATE_HIGH, speed_factor)
	if player.dribble_mode == DribblePhysics.Mode.SPRINT:
		turn_rate *= AI_SPRINT_TURN_PENALTY

	var angle_diff: float = current_dir.angle_to(target_dir)
	var max_turn: float = turn_rate * delta

	if abs(angle_diff) <= max_turn:
		_ai_move_direction = target_dir
	else:
		_ai_move_direction = current_dir.rotated(sign(angle_diff) * max_turn)

func perform_ai_decisions() -> void:
	# 防守时的断球决策
	if is_ball_possessed_by_opponent() and player.position.distance_to(ball.position) < TACKLE_DISTANCE and randf() < TACKLE_PROBABILITY:
		player.switch_state(Player.State.TACKLING)
		return

	# 持球时的进攻决策树
	if ball.carrier == player:
		_make_carrier_decision()

func _make_carrier_decision() -> void:
	var target_goal_pos := player.target_goal.get_center_target_position()
	var dist_to_goal := player.position.distance_to(target_goal_pos)
	var opponent_count := _count_nearby_opponents()
	var pressure := clampf(float(opponent_count) / 3.0, 0.0, 1.0)
	var pass_result := _find_best_pass_option()
	var pass_distance := player.position.distance_to(pass_result.get("target_position", player.position))
	var pass_eta := sqrt(2.0 * pass_distance / PitchConstants.BALL.KICKED_GROUND_FRICTION)
	var actions: Array[Dictionary] = [
		{"kind": "SHOT", "eligible": dist_to_goal <= SHOT_DISTANCE,
			"reachable": _is_ball_ready_for_release(), "rule_legal": true,
			"eta": dist_to_goal / maxf(player.power, 1.0),
			"utility": CpuActionSelectorScript.shot_utility(dist_to_goal, SHOT_DISTANCE, player.shooting, pressure)},
		{"kind": "PASS", "eligible": pass_result.target != null,
			"reachable": pass_result.target != null and _is_ball_ready_for_release(), "rule_legal": pass_result.target != null,
			"eta": pass_eta, "utility": CpuActionSelectorScript.pass_utility(
				float(pass_result.get("quality", 0.0)), pass_eta, pressure, player.technique),
			"target": pass_result.get("target"), "pass_type": pass_result.get("pass_type")},
		{"kind": "RETAIN", "eligible": true, "reachable": true, "rule_legal": true,
			"eta": 0.0, "utility": clampf(0.35 + player.technique / 250.0 - pressure * 0.2, 0.0, 1.0)},
	]
	var selected := CpuActionSelectorScript.select(actions)
	if selected.kind == "SHOT":
		player.dribble_mode = DribblePhysics.Mode.JOG
		_execute_shot(target_goal_pos)
	elif selected.kind == "PASS":
		player.dribble_mode = DribblePhysics.Mode.JOG
		_execute_pass(selected.target, int(selected.pass_type))

func _count_nearby_opponents() -> int:
	## 统计附近的对手数量
	var count := 0
	for body in opponent_detection_area.get_overlapping_bodies():
		if body is Player and body.country != player.country:
			count += 1
	return count

func _find_best_pass_option() -> Dictionary:
	## 寻找最佳传球选项，返回 {target, pass_type, quality}
	var best_target: Player = null
	var best_quality := -1.0
	var best_pass_type := PlayerStateData.PassType.SHORT

	var goal_pos := player.target_goal.get_center_target_position()

	for body in teammate_detection_area.get_overlapping_bodies():
		if not (body is Player):
			continue
		var teammate: Player = body
		if teammate == player or teammate.country != player.country:
			continue
		if _is_tactical_offside_target(teammate.position):
			continue

		var dist := player.position.distance_to(teammate.position)
		if dist < 10.0 or dist > 250.0:
			continue

		# 计算传球质量
		var to_teammate := teammate.position - player.position
		var to_goal := goal_pos - player.position
		var angle_to_goal: float = abs(to_teammate.angle_to(to_goal))
		var angle_score: float = 1.0 - clamp(angle_to_goal / PI, 0.0, 1.0)  # 朝向球门的传球更好

		var dist_score: float = 1.0 - clamp(dist / 250.0, 0.0, 1.0)

		# 前方队友更有威胁
		var forward_factor := 1.0 if to_teammate.dot(to_goal) > 0 else 0.5

		var quality: float = angle_score * 0.4 + dist_score * 0.3 + forward_factor * 0.3

		# 决定传球类型
		var pass_type := PlayerStateData.PassType.SHORT
		if dist > 120.0:
			pass_type = PlayerStateData.PassType.LONG
		elif dist > 60.0 and angle_to_goal < 0.5:  # 正对前方的中距离 → 直塞
			pass_type = PlayerStateData.PassType.THROUGH

		if quality > best_quality:
			best_quality = quality
			best_target = teammate
			best_pass_type = pass_type

	return {"target": best_target, "target_position": best_target.position if best_target != null else player.position,
		"quality": best_quality, "pass_type": best_pass_type}

func _is_tactical_offside_target(target: Vector2) -> bool:
	if player.tactical_attacking_dir > 0:
		return target.x > PitchConstants.CENTER_X and target.x >= player.tactical_offside_line
	return target.x < PitchConstants.CENTER_X and target.x <= player.tactical_offside_line

func _find_most_forward_teammate() -> Player:
	## 找到最靠前的队友（用于长传冲吊）
	var goal_pos := player.target_goal.get_center_target_position()
	var most_forward: Player = null
	var best_dist := 0.0

	for body in teammate_detection_area.get_overlapping_bodies():
		if not (body is Player):
			continue
		var teammate: Player = body
		if teammate == player or teammate.country != player.country:
			continue
		if teammate.role != Player.Role.OFFENSE:
			continue  # 只找前锋
		var dist := teammate.position.distance_to(goal_pos)
		if most_forward == null or dist < best_dist:
			best_dist = dist
			most_forward = teammate

	return most_forward

func _execute_shot(target_pos: Vector2) -> void:
	## 执行射门：与人类射门共用自动瞄准和距离/属性力量修正。
	player.face_towards_target_goal()
	var shot := ShootingPhysics.build_shot(
		player.position,
		player.heading,
		target_pos,
		Vector2.ZERO,
		player.power,
		player.shooting,
		1.0,
		player.technique
	)
	var data := PlayerStateData.build().set_shot_power(shot.power).set_shot_direction(shot.direction)
	player.switch_state(Player.State.SHOOTING, data)

func _execute_pass(target: Player, pass_type: int) -> void:
	## 执行传球
	var direction := player.position.direction_to(target.position)
	if sign(player.heading.x) != sign(direction.x):
		player.heading *= -1
	var data := PlayerStateData.build().set_pass_type(pass_type).set_pass_target(target)
	player.switch_state(Player.State.PASSING, data)

func get_onduty_steering_force() -> Vector2:
	if not player.tactical_role.is_empty():
		return _get_tactical_steering_force()
	return player.weight_on_duty_steering * player.position.direction_to(ball.position)

func get_carrier_steering_force() -> Vector2:
	var target := player.target_goal.get_center_target_position()
	var direction := player.position.direction_to(target)
	var weight := get_bicircular_weight(player.position, target, 100, 0, 150, 1)
	var forward_force := weight * direction

	# 带球修正力：当球处于 DRIBBLING 状态时，AI 需要调整移动方向保持球在可控范围内
	var ball_correction := _get_ball_correction_force(direction)

	return forward_force + ball_correction

func get_assist_formation_steering_force() -> Vector2:
	if not player.tactical_role.is_empty():
		return _get_tactical_steering_force()
	var spawn_difference := ball.carrier.spawn_position - player.spawn_position
	var assist_destination := ball.carrier.position - spawn_difference * SPREAD_ASSIST_FACTOR
	return TeamTacticsScript.arrival_intent(
		player.position, assist_destination, TACTICAL_STOP_RADIUS, TACTICAL_SLOW_RADIUS)

func _get_tactical_steering_force() -> Vector2:
	var is_pressing := player.tactical_role == "PRESS"
	var stop_radius := PRESS_STOP_RADIUS if is_pressing else TACTICAL_STOP_RADIUS
	var slow_radius := PRESS_SLOW_RADIUS if is_pressing else TACTICAL_SLOW_RADIUS
	var role_speed := 1.0 if is_pressing else 0.85
	return TeamTacticsScript.arrival_intent(
		player.position, player.tactical_target, stop_radius, slow_radius) * role_speed

func get_ball_proximity_steering_force() -> Vector2:
	var weight := get_bicircular_weight(player.position, ball.position, 50, 1, 120, 0)
	var direction := player.position.direction_to(ball.position)
	return weight * direction

func get_spawn_steering_force() -> Vector2:
	var weight := get_bicircular_weight(player.position, player.spawn_position, 30, 0, 100, 1)
	var direction := player.position.direction_to(player.spawn_position)
	return weight * direction

func get_density_around_ball_steering_force() -> Vector2:
	var nb_teammates_near_ball := ball.get_proximity_teammates_count(player.country)
	if nb_teammates_near_ball == 0:
		return Vector2.ZERO
	var weight := 1 - 1.0 / nb_teammates_near_ball
	var direction := ball.position.direction_to(player.position)
	return weight * direction

func has_teammate_in_view() -> bool:
	var players_in_view := teammate_detection_area.get_overlapping_bodies()
	return players_in_view.find_custom(func(p: Player): return p != player and p.country == player.country) > -1

# ========== 带球物理适配（DRIBBLING 状态） ==========

const BALL_READY_DISTANCE_RATIO := 0.7  ## 出球判定：球在可控距离的 70% 以内认为可控

func _get_ball_correction_force(forward_dir: Vector2) -> Vector2:
	## 计算带球修正力：让 AI 调整移动方向保持球在理想触球区内
	## 仅在 DRIBBLING 状态下生效（物理推球模式）
	if ball == null or forward_dir.length() < 0.001:
		return Vector2.ZERO

	# 只在 DRIBBLING 状态下修正（CARRIED 状态球会自动跟随，不需要修正）
	if not (ball.current_state is BallStateDribbling):
		return Vector2.ZERO

	var to_ball := ball.position - player.position

	# 理想触球点：球员前方触球区中段（50% 处）
	var zone_length := DribblePhysics.get_touch_zone_length(player.technique)
	var ideal_distance := DribblePhysics.TOUCH_ZONE_FRONT_OFFSET + zone_length * 0.5

	# 球在前进方向上的偏移（正 = 球在理想点前方，负 = 在理想点后方）
	var forward_offset := to_ball.dot(forward_dir) - ideal_distance
	# 球在侧向的偏移（正 = 右侧，负 = 左侧）
	var side_dir := forward_dir.rotated(PI / 2.0)
	var side_offset := to_ball.dot(side_dir)

	# 修正力：把球员拉向能让球回到理想位置的方向
	# forward_offset > 0（球太靠前）→ 球员需要加速追上 → 正的 forward_dir 分量
	# side_offset > 0（球在右侧）→ 球员需要向右靠 → 正的 side_dir 分量
	var correction := forward_dir * forward_offset * 0.02 + side_dir * side_offset * 0.04
	return correction.limit_length(0.3)  # 修正力不超过 0.3（相对于总转向力 1.0）

func _is_ball_ready_for_release() -> bool:
	## 判断球是否在可控范围内，可以安全传球/射门
	## 用于 AI 决策：球失控时不应该传球/射门
	if ball == null or ball.carrier != player:
		return false

	var to_ball := ball.position - player.position
	var max_control := DribblePhysics.get_max_control_distance(player.technique)

	# 球在最大可控距离的 70% 以内认为是可控的
	if to_ball.length() > max_control * BALL_READY_DISTANCE_RATIO:
		return false

	# 球需要在球员前方（前进方向半球内）
	var player_dir := player.velocity.normalized() if player.velocity.length() > 5.0 else player.heading
	return to_ball.dot(player_dir) > 0.0
