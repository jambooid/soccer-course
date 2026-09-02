class_name AIBehaviorField
extends AIBehavior

const PASS_PROBABILITY := 0.05
const SHOT_PROBABILITY := 0.3
const SPREAD_ASSIST_FACTOR := 0.8
const TACKLE_PROBABILITY := 0.3

## 距离判断（使用 PitchConstants 集中管理）
const SHOT_DISTANCE := PitchConstants.AI.SHOT_DISTANCE
const TACKLE_DISTANCE := PitchConstants.AI.TACKLE_DISTANCE

## 无球跑位（进攻支援）参数
const SUPPORT_RUN_WING_WIDTH := 70.0       ## 边路球员拉开宽度
const SUPPORT_RUN_FORWARD_PUSH := 90.0     ## 前锋向前插的距离
const SUPPORT_MID_PUSH := 50.0            ## 中场向前支援的距离
const SUPPORT_FULLBACK_PUSH := 60.0       ## 边后卫插上距离
const SUPPORT_CENTRAL_HOLD_DIST := PitchConstants.AI.SUPPORT_CENTRAL_HOLD_DIST
const SUPPORT_RUN_ACTIVATION_DIST := PitchConstants.AI.SUPPORT_RUN_ACTIVATION_DIST

## 带球模式 AI 参数
const SPRINT_TECH_THRESHOLD := PitchConstants.AI.SPRINT_TECH_THRESHOLD
const SPRINT_OPPONENT_MAX := 0         ## 附近对手不超过此数才冲刺
const SPRINT_DIST_TO_GOAL_MAX := PitchConstants.AI.SPRINT_DIST_TO_GOAL_MAX

## AI 转向参数（与人类玩家 TurnController 一致）
const AI_TURN_RATE_LOW := 10.0         # rad/s, 低速
const AI_TURN_RATE_HIGH := 3.5        # rad/s, 高速
const AI_SPRINT_TURN_PENALTY := 0.6

## 无球跑位状态机
enum OffBallRunState {
	HOLD_POSITION,   ## 保持位置
	BREAK_OFFSIDE,   ## 反越位前插
	PULL_WIDE,       ## 拉边
	DROP_DEEP,       ## 回撤接应
	OVERLAP_RUN      ## 套边助攻
}
const RUN_STATE_COOLDOWN_MS := 800    ## 跑位状态切换冷却（毫秒），防止抖动
var current_run_state : int = OffBallRunState.HOLD_POSITION
var run_state_cooldown_ms := 0.0       ## 剩余冷却时间
var cached_run_target := Vector2.ZERO ## 缓存的跑位目标位置（冷却期内使用）
var _ai_move_direction := Vector2.RIGHT  ## AI 平滑移动方向

func perform_ai_movement() -> void:
	var total_steering_force := Vector2.ZERO
	if player.has_ball():
		total_steering_force += get_carrier_steering_force()
	elif is_ball_carried_by_teammate():
		if _is_carrier_human_controlled():
			# 队友是人类玩家 → 智能无球跑位，创造传球选项
			total_steering_force += get_offensive_support_steering_force()
		else:
			# 队友是 AI → 保持阵型跟随
			total_steering_force += get_assist_formation_steering_force()
	else:
		total_steering_force += get_onduty_steering_force()
		if total_steering_force.length_squared() < 1:
			if is_ball_possessed_by_opponent():
				total_steering_force += get_spawn_steering_force()
			elif ball.carrier == null:
				total_steering_force += get_ball_proximity_steering_force()
				total_steering_force += get_density_around_ball_steering_force()

	total_steering_force = total_steering_force.limit_length(1.0)

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
	if target_dir.length() > 0.1:
		_ai_apply_turning(target_dir.normalized(), get_process_delta_time())
		player.velocity = _ai_move_direction * player.speed * speed_mult
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
	## CPU 持球决策树
	## 根据场上形势、属性、位置决定：射门 / 传球(短/长/直塞) / 带球
	var target_goal_pos := player.target_goal.get_center_target_position()
	var dist_to_goal := player.position.distance_to(target_goal_pos)
	var own_goal_pos := player.own_goal.get_center_target_position()
	var dist_to_own_goal := player.position.distance_to(own_goal_pos)

	# 场上区域判断
	var in_attacking_third := dist_to_goal < SHOT_DISTANCE * 1.5
	var in_midfield := dist_to_goal > SHOT_DISTANCE and dist_to_own_goal > SHOT_DISTANCE
	var in_own_half := dist_to_own_goal < dist_to_goal

	# 防守压力（附近对手数量）
	var opponent_count := _count_nearby_opponents()
	var under_pressure := opponent_count >= 2

	# 玩家队伍的 AI 减少射门/传球频率（把球权交给玩家主导）
	var is_player_team := GameManager.player_setup[0] == player.country \
		or GameManager.player_setup[1] == player.country
	var decision_multiplier := 0.1 if is_player_team else 1.0

	# === 决策优先级 ===

	# 1. 禁区内有机会 → 射门（最高优先级）
	if in_attacking_third and dist_to_goal < SHOT_DISTANCE:
		var shoot_prob := SHOT_PROBABILITY
		# 射门属性高的球员更倾向射门
		shoot_prob *= 0.5 + (player.shooting / 100.0) * 0.8
		# 防守压力大时降低射门概率（更难起脚）
		if under_pressure:
			shoot_prob *= 0.5
		if randf() < shoot_prob * decision_multiplier:
			player.dribble_mode = DribblePhysics.Mode.JOG  # 射门前切回普通模式保证精度
			_execute_shot(target_goal_pos)
			return

	# 2. 防守压力大 → 传球（出球）
	if under_pressure and randf() < 0.6 * decision_multiplier:
		var pass_result := _find_best_pass_option()
		if pass_result.target != null:
			player.dribble_mode = DribblePhysics.Mode.JOG  # 传球前切回普通模式保证精度
			_execute_pass(pass_result.target, pass_result.pass_type)
			return

	# 3. 有好的直塞/长传机会 → 传威胁球
	if not in_own_half:
		var pass_result := _find_best_pass_option()
		if pass_result.target != null and pass_result.quality > 0.7:
			var threat_pass_prob := 0.15 + (player.technique / 100.0) * 0.2
			if randf() < threat_pass_prob * decision_multiplier:
				player.dribble_mode = DribblePhysics.Mode.JOG  # 传球前切回普通模式保证精度
				_execute_pass(pass_result.target, pass_result.pass_type)
				return

	# 4. 中场区域，前面没人 → 偶尔长传找前锋
	if in_midfield and opponent_count == 0 and randf() < 0.05 * decision_multiplier:
		var forward_target := _find_most_forward_teammate()
		if forward_target != null:
			player.dribble_mode = DribblePhysics.Mode.JOG  # 传球前切回普通模式保证精度
			_execute_pass(forward_target, PlayerStateData.PassType.LONG)
			return

	# 5. 默认：继续带球（不做决策，movement 系统负责推进）
	# 技术好的球员更愿意带球推进（这里不做任何事 = 继续带球）

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

	return {"target": best_target, "quality": best_quality, "pass_type": best_pass_type}

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

func _is_carrier_human_controlled() -> bool:
	## 判断球的持有者是否是人类玩家（P1 或 P2）
	if ball.carrier == null:
		return false
	return ball.carrier.control_scheme == Player.ControlScheme.P1 \
		or ball.carrier.control_scheme == Player.ControlScheme.P2

func get_offensive_support_steering_force() -> Vector2:
	## 人类队友持球时的无球跑位（状态机驱动，带冷却防抖）
	## 跑位状态每 800ms 重新评估一次，冷却期内维持当前跑位目标
	var carrier := ball.carrier
	if carrier == null:
		return Vector2.ZERO

	# 太远了就先回到阵型位置（防止乱跑）
	var dist_to_ball := player.position.distance_to(carrier.position)
	if dist_to_ball > SUPPORT_RUN_ACTIVATION_DIST:
		current_run_state = OffBallRunState.HOLD_POSITION
		return get_assist_formation_steering_force()

	# 更新冷却 + 判断是否需要重新选择跑位状态
	if run_state_cooldown_ms <= 0:
		# 冷却结束，重新选择跑位状态
		_select_run_state(carrier)
		# 根据新状态计算目标位置
		cached_run_target = _compute_run_target_for_state(carrier, current_run_state)
		run_state_cooldown_ms = RUN_STATE_COOLDOWN_MS
	else:
		run_state_cooldown_ms -= _get_tick_interval_ms()

	var target_pos := cached_run_target
	var direction := player.position.direction_to(target_pos)
	var dist_to_target := player.position.distance_to(target_pos)

	# 靠近目标时减速，保持位置
	var weight := get_bicircular_weight(player.position, target_pos, 20, 0.1, 50, 1.0)

	# 离球越近，跑位越积极
	var proximity_factor: float = clamp(1.0 - dist_to_ball / SUPPORT_RUN_ACTIVATION_DIST, 0.3, 1.0)

	return weight * direction * proximity_factor

func _select_run_state(carrier: Player) -> void:
	## 根据场上形势选择跑位状态
	var goal_pos := player.target_goal.get_center_target_position()
	var dist_to_goal := player.position.distance_to(goal_pos)
	var dist_to_ball := player.position.distance_to(carrier.position)
	var attack_dir := carrier.position.direction_to(goal_pos)

	# 计算球员在阵型中的横向位置
	var spawn_y_offset := player.spawn_position.y - carrier.spawn_position.y
	var is_wide_player: bool = abs(spawn_y_offset) > 40

	match player.role:
		Player.Role.OFFENSE:
			# 前锋：大部分时间尝试反越位前插，偶尔拉边
			if is_wide_player and randf() < 0.4:
				current_run_state = OffBallRunState.PULL_WIDE
			else:
				current_run_state = OffBallRunState.BREAK_OFFSIDE

		Player.Role.MIDFIELD:
			# 中场：根据距离选择回撤或前插
			if dist_to_ball > 120.0:
				current_run_state = OffBallRunState.DROP_DEEP
			elif is_wide_player and randf() < 0.3:
				current_run_state = OffBallRunState.PULL_WIDE
			else:
				current_run_state = OffBallRunState.BREAK_OFFSIDE

		Player.Role.DEFENSE:
			# 后卫：边后卫套边，中后卫留守
			if is_wide_player and dist_to_goal > 150.0:
				current_run_state = OffBallRunState.OVERLAP_RUN
			else:
				current_run_state = OffBallRunState.HOLD_POSITION

		_:
			current_run_state = OffBallRunState.HOLD_POSITION

func _compute_run_target_for_state(carrier: Player, state: int) -> Vector2:
	## 根据跑位状态计算目标位置
	var goal_pos := player.target_goal.get_center_target_position()
	var carrier_pos := carrier.position
	var attack_dir := carrier_pos.direction_to(goal_pos)
	var lateral_dir := Vector2(-attack_dir.y, attack_dir.x)
	var spawn_y_offset := player.spawn_position.y - carrier.spawn_position.y

	match state:
		OffBallRunState.BREAK_OFFSIDE:
			# 反越位：向球门方向前插
			var forward_push := SUPPORT_RUN_FORWARD_PUSH
			return carrier_pos + attack_dir * forward_push

		OffBallRunState.PULL_WIDE:
			# 拉边：向边路拉开宽度
			var wide_amount: float = sign(spawn_y_offset) * SUPPORT_RUN_WING_WIDTH
			var mid_push := SUPPORT_MID_PUSH * 0.5
			return carrier_pos + attack_dir * mid_push + lateral_dir * wide_amount

		OffBallRunState.DROP_DEEP:
			# 回撤：回到球后方接应
			var drop_back := SUPPORT_CENTRAL_HOLD_DIST * 0.8
			return carrier_pos - attack_dir * drop_back

		OffBallRunState.OVERLAP_RUN:
			# 套边：沿边路插上
			var fb_push := SUPPORT_FULLBACK_PUSH
			var wide_amount: float = sign(spawn_y_offset) * SUPPORT_RUN_WING_WIDTH
			return carrier_pos + attack_dir * fb_push + lateral_dir * wide_amount

		_:  # HOLD_POSITION
			# 保持位置：停在当前位置附近
			return player.position + attack_dir * 20.0



func get_onduty_steering_force() -> Vector2:
	if not player.tactical_role.is_empty():
		var tactical_weight := 1.0 if player.tactical_role == "PRESS" else 0.7
		return tactical_weight * player.position.direction_to(player.tactical_target)
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
	var spawn_difference := ball.carrier.spawn_position - player.spawn_position
	var assist_destination := ball.carrier.position - spawn_difference * SPREAD_ASSIST_FACTOR
	var direction := player.position.direction_to(assist_destination)
	var weight := get_bicircular_weight(player.position, assist_destination, 30, 0.2, 60, 1)
	return weight * direction

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
