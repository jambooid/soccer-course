class_name BallStateDeflected
extends BallState

## 折射/反弹球：被球员身体挡到的球
## 被动碰撞，物理反射，衰减较少

const TRANSITION_SPEED := 30.0
const MAX_DURATION_MS := 1200
const LOCK_DURATION_MS := 200

var time_started := 0
var deflector : Player = null

func _enter_tree() -> void:
	time_started = Time.get_ticks_msec()
	deflector = state_data.kicker
	player_detection_area.body_entered.connect(on_player_enter.bind())
	player_detection_area.monitoring = false
	set_ball_animation_from_velocity()

func _process(delta: float) -> void:
	var elapsed := Time.get_ticks_msec() - time_started
	player_detection_area.monitoring = elapsed > LOCK_DURATION_MS

	var friction := ball.friction_ground * 0.8
	if ball.height > 0:
		friction = ball.friction_ground * 0.3
	ball.velocity = ball.velocity.move_toward(Vector2.ZERO, friction * delta)

	process_gravity(delta, ball.BOUNCINESS * 0.9)
	move_and_bounce(delta)
	set_ball_animation_from_velocity()

	if elapsed > MAX_DURATION_MS:
		transition_state(Ball.State.FREEFORM)
	elif ball.velocity.length() < TRANSITION_SPEED and ball.height == 0:
		transition_state(Ball.State.FREEFORM)

func on_player_enter(body: Player) -> void:
	# 守门员专用抱球逻辑（高度阈值比普通球员高）
	if body.role == Player.Role.GOALIE:
		if ball.height <= PitchConstants.HEIGHT_GOALIE_CATCH_MAX:
			ball.hold_by_goalkeeper(body)  # 内部已切换状态，无需再调 transition_state
		return

	if not body.can_carry_ball():
		return
	if ball.height > PitchConstants.HEIGHT_DEFLECTED_PICKUP_MAX:
		return
	ball.carrier = body
	body.control_ball()
	transition_state(Ball.State.DRIBBLING)

func can_air_interact() -> bool:
	return true
