class_name PlayerStateMoving
extends PlayerState

## 转向参数（Turn Controller）— 使用 PitchConstants 集中管理
const TURN_RATE_LOW_SPEED := PitchConstants.PLAYER.MOVING_TURN_RATE_LOW_SPEED
const TURN_RATE_HIGH_SPEED := PitchConstants.PLAYER.MOVING_TURN_RATE_HIGH_SPEED
const SPRINT_TURN_PENALTY := 0.6         # 冲刺时转向速率倍率
const CUTBACK_ANGLE_THRESHOLD := PitchConstants.PLAYER.MOVING_CUTBACK_ANGLE_THRESHOLD
const CUTBACK_HYSTERESIS := 0.8           # 急转重置滞后倍率（低于阈值×此值才重置）
const CUTBACK_SPEED_PENALTY := PitchConstants.PLAYER.MOVING_CUTBACK_SPEED_PENALTY

const TURN_DURATION_SHORT := 0.24
const TURN_DURATION_LONG := 0.78
const TURN_TRIGGER_ANGLE := deg_to_rad(30.0)
const TURN_ANGLE_SHORT := deg_to_rad(60.0)
const TURN_ANGLE_LONG := deg_to_rad(135.0)
const TURN_DIRECTION_MEMORY_DURATION := 0.35
const TURN_MIN_SPEED_MULTIPLIER := 0.12
const TURN_MAX_SPEED_MULTIPLIER := 0.5

const SPRINT_SPEED_MULTIPLIER := PitchConstants.PLAYER.MOVING_SPRINT_SPEED_MULTIPLIER

## Turn Controller 状态
var current_move_direction := Vector2.RIGHT  # 当前实际移动方向（平滑插值后）
var is_moving := false
var cutback_active := false  # 急转是否处于激活状态（边沿触发用）
var turn_active := false
var turn_elapsed := 0.0
var turn_start_direction := Vector2.RIGHT
var turn_target_direction := Vector2.RIGHT
var turn_duration := TURN_DURATION_LONG
var turn_angle := 0.0
var last_input_direction := Vector2.ZERO
var time_since_last_direction_input := INF

func _physics_process(delta: float) -> void:
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

	if turn_active:
		_process_turn(delta, direction if has_direction else turn_target_direction)
	else:
		# 持球时的反向输入进入短暂转身阶段，给收球和拨球留下前摇/后摇。
		if has_direction and _should_start_turn(direction.normalized()):
			_begin_turn(direction.normalized())
			_process_turn(delta, direction.normalized())
		else:
			_process_movement(delta, direction, has_direction)

	# 记录最后一次有效方向。相反方向按键交接时 Input 会短暂报告零向量，
	# 因此转身判定不能只依赖当前帧的 is_moving 或残余速度。
	if has_direction:
		last_input_direction = direction.normalized()
		time_since_last_direction_input = 0.0
	else:
		time_since_last_direction_input += delta

	_process_actions()

func _process_movement(delta: float, direction: Vector2, has_direction: bool) -> void:

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
		# 从静止启动时，直接使用新方向，避免从旧方向插值造成半圆轨迹
		if not is_moving:
			current_move_direction = direction.normalized()

		var turn_result := _apply_turning(direction.normalized(), delta)
		var move_dir: Vector2 = turn_result.direction
		triggered_cutback = turn_result.cutback

		# 直接设置目标速度（Turn Controller 已经处理了方向平滑）
		player.velocity = move_dir * player.speed * speed_multiplier

		# 急转只影响球员意图和速度；下一次合法触球决定足球方向。
		if triggered_cutback:
			player.velocity *= CUTBACK_SPEED_PENALTY

		is_moving = true
	else:
		# 没有方向输入 → 只对球员做减速。
		# 不能让球员追随球速，否则球和球员会互相回写速度，产生永不归零的反馈回路。
		player.velocity = player.velocity.move_toward(Vector2.ZERO, player.speed * 8.0 * delta)
		is_moving = false

	if player.velocity != Vector2.ZERO:
		teammate_detection_area.rotation = player.velocity.angle()

	# 短传：最常用，优先级高（从输入缓冲消费，提升跟手感）

func _process_actions() -> void:
	# Shooting starts a charge while running as well. It must be checked before
	# the turn animation lock, otherwise the short input-buffer window can
	# expire during a long turn and make the shot appear unresponsive.
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

	# 转身前摇/后摇期间锁定动作，输入留在缓冲区，转身结束后再消费。
	if turn_active:
		return
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

	# 特殊键：切换球员（无球时） / 假动作（持球时，M2 实现）（从输入缓冲消费）
	if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.SPECIAL):
		if not player.has_ball():
			player.swap_requested.emit(player)

func _should_start_turn(target_direction: Vector2) -> bool:
	if not player.has_ball() or time_since_last_direction_input > TURN_DIRECTION_MEMORY_DURATION:
		return false
	if last_input_direction.length_squared() < 0.01:
		return false
	var previous_direction: Vector2 = last_input_direction.normalized()
	var direction_dot: float = previous_direction.dot(target_direction.normalized())
	return abs(previous_direction.angle_to(target_direction)) >= TURN_TRIGGER_ANGLE or direction_dot < 0.0

func _begin_turn(target_direction: Vector2) -> void:
	turn_active = true
	turn_elapsed = 0.0
	turn_start_direction = current_move_direction.normalized()
	turn_target_direction = target_direction.normalized()
	turn_angle = abs(turn_start_direction.angle_to(turn_target_direction))
	var angle_factor: float = clampf(
		(turn_angle - TURN_ANGLE_SHORT) / (PI - TURN_ANGLE_SHORT),
		0.0,
		1.0
	)
	turn_duration = lerpf(TURN_DURATION_SHORT, TURN_DURATION_LONG, angle_factor)
	cutback_active = true
	if turn_angle < TURN_ANGLE_SHORT:
		animation_player.play("turn_45")
	elif turn_angle < TURN_ANGLE_LONG:
		animation_player.play("turn_90")
	else:
		animation_player.play("turn_180")

func _process_turn(delta: float, target_direction: Vector2) -> void:
	if target_direction.length() > 0.01:
		turn_target_direction = target_direction.normalized()
	turn_elapsed += delta
	var progress: float = clampf(turn_elapsed / turn_duration, 0.0, 1.0)
	var eased: float = progress * progress * (3.0 - 2.0 * progress)
	current_move_direction = turn_start_direction.slerp(turn_target_direction, eased).normalized()
	# 前半段先刹停，后半段再逐渐恢复，形成清晰的收球、转髋、拨球节奏。
	var speed_multiplier: float
	if progress < 0.55:
		var brake_progress: float = smoothstep(0.0, 1.0, progress / 0.55)
		speed_multiplier = lerpf(TURN_MAX_SPEED_MULTIPLIER, TURN_MIN_SPEED_MULTIPLIER, brake_progress)
	else:
		var recovery_progress: float = smoothstep(0.0, 1.0, (progress - 0.55) / 0.45)
		speed_multiplier = lerpf(TURN_MIN_SPEED_MULTIPLIER, TURN_MAX_SPEED_MULTIPLIER, recovery_progress)
	player.velocity = current_move_direction * player.speed * speed_multiplier
	is_moving = true
	if progress >= 0.5:
		player.heading = Vector2.LEFT if turn_target_direction.x < 0 else Vector2.RIGHT
	if progress >= 1.0:
		turn_active = false
		cutback_active = false
		current_move_direction = turn_target_direction
		player.velocity = current_move_direction * player.speed * TURN_MAX_SPEED_MULTIPLIER
		animation_player.play("run")

func get_dribble_direction() -> Vector2:
	if turn_active:
		return current_move_direction
	return current_move_direction if is_moving else player.heading


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
