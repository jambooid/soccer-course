class_name PlayerStatePreppingShot
extends PlayerState

const DURATION_MAX_BONUS := 1000.0
const EASE_REWARD_FACTOR := 2.0
const CANCEL_WINDOW_MS := 150  ## 蓄力前多少毫秒内可以取消为传球

var shot_direction := Vector2.ZERO
var time_start_shot := Time.get_ticks_msec()

func _enter_tree() -> void:
	animation_player.play("prep_kick")
	player.velocity = Vector2.ZERO
	time_start_shot = Time.get_ticks_msec()
	shot_direction = player.heading

func _process(delta: float) -> void:
	shot_direction += KeyUtils.get_input_vector(player.control_scheme) * delta

	# 起手窗口内可取消为传球（短传 > 长传 > 直塞）
	if Time.get_ticks_msec() - time_start_shot < CANCEL_WINDOW_MS:
		_check_cancel_input()
		return

	if KeyUtils.is_action_just_released(player.control_scheme, KeyUtils.Action.SHOOT):
		var duration_press := clampf(Time.get_ticks_msec() - time_start_shot, 0.0, DURATION_MAX_BONUS)
		var ease_time := duration_press / DURATION_MAX_BONUS
		var bonus := ease(ease_time, EASE_REWARD_FACTOR)
		var shot_power := player.power * (1 + bonus)
		if shot_direction.length() < 0.001:
			shot_direction = player.heading
		else:
			shot_direction = shot_direction.normalized()
		var data = PlayerStateData.build().set_shot_power(shot_power).set_shot_direction(shot_direction)
		transition_state(Player.State.SHOOTING, data)

func _check_cancel_input() -> void:
	## 蓄力起手窗口内可取消为传球
	if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.SHORT_PASS):
		transition_state(Player.State.PASSING, PlayerStateData.build()
			.set_pass_type(PlayerStateData.PassType.SHORT))
		return
	if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.LONG_PASS):
		transition_state(Player.State.PASSING, PlayerStateData.build()
			.set_pass_type(PlayerStateData.PassType.LONG))
		return
	if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.THROUGH_PASS):
		transition_state(Player.State.PASSING, PlayerStateData.build()
			.set_pass_type(PlayerStateData.PassType.THROUGH))
		return

func can_pass() -> bool:
	return true
