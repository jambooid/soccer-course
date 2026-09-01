class_name PlayerStatePreppingShot
extends PlayerState

const MAX_CHARGE_SECONDS := ShootingPhysics.MAX_CHARGE_SECONDS
const CANCEL_WINDOW_MS := 150  ## 起手窗口内可改为传球

var elapsed_charge := 0.0

func _enter_tree() -> void:
	# Charging does not own the player movement.  The ball remains in the
	# dribbling state and the existing momentum is preserved until release.
	player.is_charging = true
	player.charge_display = 0.0
	elapsed_charge = 0.0

func _process(delta: float) -> void:
	if not player.has_ball():
		_cancel_charge()
		transition_state(Player.State.MOVING)
		return

	var input_direction := Vector2.ZERO
	if player.control_scheme != Player.ControlScheme.CPU:
		input_direction = KeyUtils.get_input_vector(player.control_scheme)
	# Direction input never cancels charge. It still controls the dribble so the
	# player can reposition while charging; the same input is sampled again on
	# release for the shot's vertical aim lane.
	_apply_charge_movement(input_direction, delta)

	elapsed_charge += delta
	var ratio := ShootingPhysics.charge_ratio(elapsed_charge)
	player.charge_display = ratio
	var shoot_released := false
	if player.control_scheme != Player.ControlScheme.CPU:
		shoot_released = KeyUtils.is_action_just_released(player.control_scheme, KeyUtils.Action.SHOOT) \
			or not KeyUtils.is_action_pressed(player.control_scheme, KeyUtils.Action.SHOOT)
	if shoot_released \
			or elapsed_charge >= MAX_CHARGE_SECONDS:
		_release_shot(input_direction, ratio)
		return

	# 起手窗口内可取消为传球（短传 > 长传 > 直塞）。
	if elapsed_charge * 1000.0 < CANCEL_WINDOW_MS:
		_check_cancel_input()

func _release_shot(input_direction: Vector2, ratio: float) -> void:
	var goal_center := player.target_goal.get_center_target_position()
	var shot := ShootingPhysics.build_shot(
		player.position,
		player.heading,
		goal_center,
		input_direction,
		player.power,
		player.shooting,
		ratio,
		player.technique
	)
	_cancel_charge()
	# Only now, after charge release, does SHOOTING start its kick animation.
	transition_state(Player.State.SHOOTING, PlayerStateData.build()
		.set_shot_power(shot.power)
		.set_shot_direction(shot.direction))

func _cancel_charge() -> void:
	player.is_charging = false
	player.charge_display = 0.0

func _apply_charge_movement(input_direction: Vector2, delta: float) -> void:
	if player.control_scheme == Player.ControlScheme.CPU:
		return
	if input_direction.length() > 0.1:
		var direction := input_direction.normalized()
		var speed_multiplier := PitchConstants.PLAYER.MOVING_SPRINT_SPEED_MULTIPLIER \
			if KeyUtils.is_action_pressed(player.control_scheme, KeyUtils.Action.SPRINT) else 1.0
		player.dribble_mode = DribblePhysics.Mode.SPRINT \
			if speed_multiplier > 1.0 else DribblePhysics.Mode.JOG
		player.velocity = direction * player.speed * speed_multiplier
		if abs(direction.x) > 0.1:
			player.heading = Vector2.LEFT if direction.x < 0.0 else Vector2.RIGHT
		player.set_movement_animation()
	else:
		# Keep the pre-charge momentum when no new direction is held.
		player.velocity = player.velocity.move_toward(Vector2.ZERO, player.speed * 2.0 * delta)

func _check_cancel_input() -> void:
	## 蓄力起手窗口内可取消为传球
	if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.SHORT_PASS):
		_cancel_charge()
		transition_state(Player.State.PASSING, PlayerStateData.build()
			.set_pass_type(PlayerStateData.PassType.SHORT))
		return
	if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.LONG_PASS):
		_cancel_charge()
		transition_state(Player.State.PASSING, PlayerStateData.build()
			.set_pass_type(PlayerStateData.PassType.LONG))
		return
	if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.THROUGH_PASS):
		_cancel_charge()
		transition_state(Player.State.PASSING, PlayerStateData.build()
			.set_pass_type(PlayerStateData.PassType.THROUGH))
		return

func can_pass() -> bool:
	return true
