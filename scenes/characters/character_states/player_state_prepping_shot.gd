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
	# Direction input is sampled for the final aim lane only. The player keeps
	# the velocity and heading from the moment charge began.

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
