class_name BallStateFreeform
extends BallState

const MAX_CAPTURE_HEIGHT := PitchConstants.HEIGHT_FREEFORM_PICKUP_MAX

var time_since_freeform := Time.get_ticks_msec()

func _enter_tree() -> void:
	player_detection_area.body_entered.connect(on_player_enter.bind())
	time_since_freeform = Time.get_ticks_msec()

func on_player_enter(body: Player) -> void:
	# 守门员专用抱球逻辑
	if body.role == Player.Role.GOALIE:
		if ball.height <= PitchConstants.HEIGHT_GOALIE_CATCH_MAX:
			ball.hold_by_goalkeeper(body)  # 内部已切换状态，无需再调 transition_state
		return

	if body.can_carry_ball() and ball.height < MAX_CAPTURE_HEIGHT:
		ball.carrier = body
		body.control_ball()
		transition_state(Ball.State.DRIBBLING)

func _process(delta: float) -> void:
	player_detection_area.monitoring = (Time.get_ticks_msec() - time_since_freeform > state_data.lock_duration)
	set_ball_animation_from_velocity()
	var friction := ball.friction_air if ball.height > 0 else ball.friction_ground
	ball.velocity = ball.velocity.move_toward(Vector2.ZERO, friction * delta)
	process_gravity(delta, ball.BOUNCINESS)
	move_and_bounce(delta)

func can_air_interact() -> bool:
	return true
