class_name BallStateSaved
extends BallState

## 被守门员扑出的球
## 大幅减速，方向由门将扑救方向决定
## 门将可以二次扑救抱住

const TRANSITION_SPEED := 25.0
const MAX_DURATION_MS := 1500

var time_started := 0
var goalie : Player = null

func _enter_tree() -> void:
	time_started = Time.get_ticks_msec()
	goalie = state_data.kicker
	player_detection_area.body_entered.connect(on_player_enter.bind())
	player_detection_area.monitoring = true
	SoundPlayer.play(SoundPlayer.Sound.SAVE)
	set_ball_animation_from_velocity()

func _process(delta: float) -> void:
	var friction := ball.friction_ground * 1.5
	if ball.height > 0:
		friction = ball.friction_ground * 0.4
	ball.velocity = ball.velocity.move_toward(Vector2.ZERO, friction * delta)

	process_gravity(delta, ball.BOUNCINESS * 0.8)
	move_and_bounce(delta)
	set_ball_animation_from_velocity()

	var elapsed := Time.get_ticks_msec() - time_started
	if elapsed > MAX_DURATION_MS:
		transition_state(Ball.State.FREEFORM)
	elif ball.velocity.length() < TRANSITION_SPEED and ball.height == 0:
		transition_state(Ball.State.FREEFORM)

func on_player_enter(body: Player) -> void:
	if body.role == Player.Role.GOALIE and goalie != null and body == goalie:
		if ball.height < 15.0:
			ball.carrier = body
			carrier = body
			transition_state(Ball.State.HELD_BY_GOALKEEPER)
	elif body.can_carry_ball() and ball.height < 8.0:
		ball.carrier = body
		body.control_ball()
		transition_state(Ball.State.CARRIED)

func can_air_interact() -> bool:
	return true
