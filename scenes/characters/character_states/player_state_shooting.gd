class_name PlayerStateShooting
extends PlayerState

var shot_fired := false

func _enter_tree() -> void:
	player.is_charging = false
	player.charge_display = 0.0
	# The kick animation is intentionally entered only after PREPPING_SHOT has
	# released its charge, matching the WE2000 startup/contact rhythm.
	animation_player.play("kick")

func on_animation_complete() -> void:
	if shot_fired:
		return
	shot_fired = true
	if player.control_scheme == Player.ControlScheme.CPU:
		transition_state(Player.State.RECOVERING)
	else:
		transition_state(Player.State.MOVING)
	if player.has_ball():
		shoot_ball()

func shoot_ball() -> void:
	SoundPlayer.play(SoundPlayer.Sound.SHOT)
	var direction := state_data.shot_direction
	var power := state_data.shot_power
	if direction.length_squared() < 0.01:
		var goal_center := player.target_goal.get_center_target_position()
		var shot := ShootingPhysics.build_shot(
			player.position, player.heading, goal_center, Vector2.ZERO,
			player.power, player.shooting, 1.0, player.technique
		)
		direction = shot.direction
		power = shot.power
	ball.shoot(direction.normalized() * maxf(power, 1.0))

func _exit_tree() -> void:
	player.is_charging = false
	player.charge_display = 0.0
