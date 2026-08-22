class_name PlayerStateMoving
extends PlayerState

const SPRINT_SPEED_MULTIPLIER := 1.6

func _process(_delta: float) -> void:
	if player.control_scheme == Player.ControlScheme.CPU:
		ai_behavior.process_ai()
	else:
		handle_human_movement()
	player.set_movement_animation()
	player.set_heading()


func handle_human_movement() -> void:
	# 方向输入 + 加速
	var direction := KeyUtils.get_input_vector(player.control_scheme)
	var speed_multiplier := 1.0
	if KeyUtils.is_action_pressed(player.control_scheme, KeyUtils.Action.SPRINT):
		speed_multiplier = SPRINT_SPEED_MULTIPLIER
	player.velocity = direction * player.speed * speed_multiplier
	if player.velocity != Vector2.ZERO:
		teammate_detection_area.rotation = player.velocity.angle()

	# 短传：最常用，优先级高
	if KeyUtils.is_action_just_pressed(player.control_scheme, KeyUtils.Action.SHORT_PASS):
		if player.has_ball():
			transition_state(Player.State.PASSING, PlayerStateData.build()
				.set_pass_type(PlayerStateData.PassType.SHORT))
		elif can_teammate_pass_ball():
			ball.carrier.get_pass_request(player)
		else:
			player.swap_requested.emit(player)
		return

	# 长传：高球/传中
	if KeyUtils.is_action_just_pressed(player.control_scheme, KeyUtils.Action.LONG_PASS):
		if player.has_ball():
			transition_state(Player.State.PASSING, PlayerStateData.build()
				.set_pass_type(PlayerStateData.PassType.LONG))
		elif can_teammate_pass_ball():
			ball.carrier.get_pass_request(player)
		else:
			player.swap_requested.emit(player)
		return

	# 直塞：地面穿透球
	if KeyUtils.is_action_just_pressed(player.control_scheme, KeyUtils.Action.THROUGH_PASS):
		if player.has_ball():
			transition_state(Player.State.PASSING, PlayerStateData.build()
				.set_pass_type(PlayerStateData.PassType.THROUGH))
		elif can_teammate_pass_ball():
			ball.carrier.get_pass_request(player)
		return

	# 射门
	if KeyUtils.is_action_just_pressed(player.control_scheme, KeyUtils.Action.SHOOT):
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

	# 特殊键：切换球员（无球时） / 假动作（持球时，M2 实现）
	if KeyUtils.is_action_just_pressed(player.control_scheme, KeyUtils.Action.SPECIAL):
		if not player.has_ball():
			player.swap_requested.emit(player)

func can_carry_ball() -> bool:
	return player.role != Player.Role.GOALIE

func can_teammate_pass_ball() -> bool:
	return ball.carrier != null and ball.carrier.country == player.country and ball.carrier.control_scheme == Player.ControlScheme.CPU
	
func can_pass() -> bool:
	return true
