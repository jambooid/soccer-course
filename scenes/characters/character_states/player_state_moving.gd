class_name PlayerStateMoving
extends PlayerState

## 转向参数（Turn Controller）
const TURN_RATE_LOW_SPEED := 12.0        # 静止时最大转向速率（rad/s）
const TURN_RATE_HIGH_SPEED := 4.0        # 满速时最大转向速率（rad/s）
const SPRINT_TURN_PENALTY := 0.6         # 冲刺时转向速率倍率
const CUTBACK_ANGLE_THRESHOLD := deg_to_rad(90.0)  # 急转角度阈值
const CUTBACK_HYSTERESIS := 0.8           # 急转重置滞后倍率（低于阈值×此值才重置）
const CUTBACK_SPEED_PENALTY := 0.6       # 急转速度衰减（乘以此系数）

const SPRINT_SPEED_MULTIPLIER := 1.6

## Turn Controller 状态
var current_move_direction := Vector2.RIGHT  # 当前实际移动方向（平滑插值后）
var is_moving := false
var cutback_active := false  # 急转是否处于激活状态（边沿触发用）

func _process(delta: float) -> void:
	if player.control_scheme == Player.ControlScheme.CPU:
		ai_behavior.process_ai()
	else:
		handle_human_movement(delta)
	player.set_movement_animation()
	player.set_heading()


func handle_human_movement(delta: float) -> void:
	# 方向输入
	var direction := KeyUtils.get_input_vector(player.control_scheme)
	var has_direction := direction.length() > 0.1

	# 冲刺模式切换
	if KeyUtils.is_action_pressed(player.control_scheme, KeyUtils.Action.SPRINT):
		player.dribble_mode = DribblePhysics.Mode.SPRINT
	else:
		player.dribble_mode = DribblePhysics.Mode.JOG

	# 速度倍率
	var speed_multiplier := 1.0
	if player.dribble_mode == DribblePhysics.Mode.SPRINT:
		speed_multiplier = SPRINT_SPEED_MULTIPLIER

	# 转向平滑（Turn Controller）
	var triggered_cutback := false
	if has_direction:
		var turn_result := _apply_turning(direction.normalized(), delta)
		var move_dir: Vector2 = turn_result.direction
		triggered_cutback = turn_result.cutback

		# 目标速度
		var target_velocity := move_dir * player.speed * speed_multiplier

		# 快速加速到目标速度，提升响应手感（从即时设置改为快速插值）
		var accel_factor := 10.0  # 加速系数（原本是即时设置）
		player.velocity = player.velocity.move_toward(target_velocity, player.speed * accel_factor * delta)

		# 急转：速度衰减 + 球额外前冲（在 velocity 设置后执行，避免被覆盖）
		if triggered_cutback:
			player.velocity *= CUTBACK_SPEED_PENALTY
			if player.has_ball() and ball.current_state != null:
				var dribble_state = ball.current_state
				if dribble_state.has_method("apply_cutback_kick"):
					dribble_state.apply_cutback_kick()

		is_moving = true
	else:
		# 没有方向输入 → 快速减速停下，提升手感（从 3.0 提高到 8.0）
		player.velocity = player.velocity.move_toward(Vector2.ZERO, player.speed * 8.0 * delta)
		is_moving = false

	if player.velocity != Vector2.ZERO:
		teammate_detection_area.rotation = player.velocity.angle()

	# 短传：最常用，优先级高（从输入缓冲消费，提升跟手感）
	if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.SHORT_PASS):
		if player.has_ball():
			transition_state(Player.State.PASSING, PlayerStateData.build()
				.set_pass_type(PlayerStateData.PassType.SHORT))
		elif can_teammate_pass_ball():
			ball.carrier.get_pass_request(player)
		else:
			player.swap_requested.emit(player)
		return

	# 长传：高球/传中（从输入缓冲消费）
	if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.LONG_PASS):
		if player.has_ball():
			transition_state(Player.State.PASSING, PlayerStateData.build()
				.set_pass_type(PlayerStateData.PassType.LONG))
		elif can_teammate_pass_ball():
			ball.carrier.get_pass_request(player)
		else:
			player.swap_requested.emit(player)
		return

	# 直塞：地面穿透球（从输入缓冲消费）
	if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.THROUGH_PASS):
		if player.has_ball():
			transition_state(Player.State.PASSING, PlayerStateData.build()
				.set_pass_type(PlayerStateData.PassType.THROUGH))
		elif can_teammate_pass_ball():
			ball.carrier.get_pass_request(player)
		return

	# 射门（从输入缓冲消费）
	if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.SHOOT):
		if player.has_ball():
			transition_state(Player.State.PREPPING_SHOT)
		elif ball.can_air_interact():
			if player.velocity == Vector2.ZERO:
				if player.is_facing_target_goal():
					transition_state(Player.State.VOLLEY_KICK)
				else:
					transition_state(Player.State.BICYCLE_KICK)
			else:
				transition_state(Player.State.HEADER)
		elif player.velocity != Vector2.ZERO:
			transition_state(Player.State.TACKLING)
		return

	# 特殊键：切换球员（无球时） / 假动作（持球时，M2 实现）（从输入缓冲消费）
	if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.SPECIAL):
		if not player.has_ball():
			player.swap_requested.emit(player)


## 转向平滑：将当前移动方向朝目标方向插值
## 返回 Dictionary: {"direction": Vector2, "cutback": bool}
##   direction: 插值后的移动方向
##   cutback: 本帧是否触发了急转（边沿触发，每个方向跳变只触发一次）
func _apply_turning(target_direction: Vector2, delta: float) -> Dictionary:
	var result := {"direction": current_move_direction, "cutback": false}

	if target_direction.length() < 0.01:
		return result

	var target_dir: Vector2 = target_direction.normalized()
	var current_dir: Vector2 = current_move_direction.normalized()

	# 计算转向速率：速度越快转越慢；冲刺时更慢
	var speed_factor: float = clamp(player.velocity.length() / player.speed, 0.0, 1.0)
	var turn_rate: float = lerp(TURN_RATE_LOW_SPEED, TURN_RATE_HIGH_SPEED, speed_factor)
	if player.dribble_mode == DribblePhysics.Mode.SPRINT:
		turn_rate *= SPRINT_TURN_PENALTY

	# 角度差
	var angle_diff: float = current_dir.angle_to(target_dir)
	var max_turn: float = turn_rate * delta

	if abs(angle_diff) <= max_turn:
		current_move_direction = target_dir
	else:
		current_move_direction = current_dir.rotated(sign(angle_diff) * max_turn)

	result.direction = current_move_direction

	# 急转检测（边沿触发 + 滞后）
	var abs_angle: float = abs(angle_diff)
	if not cutback_active and abs_angle > CUTBACK_ANGLE_THRESHOLD and speed_factor > 0.6:
		# 从低于阈值跳到高于阈值 → 触发一次急转
		cutback_active = true
		result.cutback = true
	elif cutback_active and abs_angle < CUTBACK_ANGLE_THRESHOLD * CUTBACK_HYSTERESIS:
		# 回落到低于阈值×滞后系数 → 重置，允许下一次触发
		cutback_active = false

	return result


func can_carry_ball() -> bool:
	# MOVING 状态下所有球员都能与球交互。
	return true


func can_teammate_pass_ball() -> bool:
	return ball.carrier != null and ball.carrier.country == player.country and ball.carrier.control_scheme == Player.ControlScheme.CPU


func can_pass() -> bool:
	return true
