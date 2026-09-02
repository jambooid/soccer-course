class_name BallStateKicked
extends BallState

const BallTrajectoryScript := preload("res://utils/ball_trajectory.gd")

## 被有意识踢出的球（传球、解围、大脚等）
## 与 FREEFORM 的区别：
## - 有明确的 kicker（踢球者）
## - 有独立的衰减曲线
## - 有 pass_lock（队友保护期）
## - 对手随时可以拦截
## - 可以在空中被争顶/拦截

## 物理常量（使用 PitchConstants 集中管理）
const AIR_FRICTION_MULTIPLIER := PitchConstants.BALL.KICKED_AIR_FRICTION_MULT
const GROUND_FRICTION_BASE := PitchConstants.BALL.KICKED_GROUND_FRICTION
const TRANSITION_TO_FREEFORM_SPEED := PitchConstants.BALL.KICKED_TRANSITION_SPEED
const MAX_BOUNCES_BEFORE_FREEFORM := PitchConstants.BALL.KICKED_MAX_BOUNCES

var kicker : Player = null
var bounce_count := 0
var time_since_kick := Time.get_ticks_msec()

func _enter_tree() -> void:
	time_since_kick = Time.get_ticks_msec()
	kicker = state_data.kicker
	bounce_count = 0
	player_detection_area.body_entered.connect(on_player_enter.bind())
	player_detection_area.monitoring = false
	set_ball_animation_from_velocity()

func _process(delta: float) -> void:
	var elapsed := Time.get_ticks_msec() - time_since_kick
	player_detection_area.monitoring = elapsed > state_data.lock_duration

	set_ball_animation_from_velocity()

	var friction: float
	if ball.height > 0:
		friction = GROUND_FRICTION_BASE * AIR_FRICTION_MULTIPLIER
	else:
		friction = GROUND_FRICTION_BASE

	ball.velocity = ball.velocity.move_toward(Vector2.ZERO, friction * delta)

	var prev_height := ball.height
	process_gravity(delta, ball.BOUNCINESS)
	if prev_height > 0 and ball.height <= 0.001 and ball.height_velocity > 0:
		bounce_count += 1

	move_and_bounce_kicked(delta)

	if ball.velocity.length() < TRANSITION_TO_FREEFORM_SPEED and ball.height <= 0.001:
		transition_state(Ball.State.FREEFORM)
	elif bounce_count >= MAX_BOUNCES_BEFORE_FREEFORM:
		transition_state(Ball.State.FREEFORM)

func move_and_bounce_kicked(delta: float) -> void:
	var collision := ball.move_and_collide(ball.velocity * delta)
	if collision != null:
		ball.velocity = BallTrajectoryScript.bounce_velocity(
			ball.velocity, collision.get_normal(), ball.BOUNCINESS)
		SoundPlayer.play(SoundPlayer.Sound.BOUNCE)

func on_player_enter(body: Player) -> void:
	if not ball.can_be_picked_up_by(body):
		return

	# 守门员专用抱球逻辑（高度阈值比普通球员高）
	if body.role == Player.Role.GOALIE:
		if ball.height <= PitchConstants.HEIGHT_GOALIE_CATCH_MAX:
			ball.hold_by_goalkeeper(body)  # 内部已切换状态，无需再调 transition_state
		return

	if not body.can_carry_ball():
		return
	if ball.height > PitchConstants.HEIGHT_KICKED_PICKUP_MAX:
		return

	if kicker == null:
		ball.carrier = body
		body.control_ball()
		transition_state(Ball.State.DRIBBLING)
		return

	if body.country != kicker.country:
		ball.carrier = body
		body.control_ball()
		transition_state(Ball.State.DRIBBLING)
		return

	if body != kicker:
		ball.carrier = body
		body.control_ball()
		transition_state(Ball.State.DRIBBLING)

func can_air_interact() -> bool:
	return true

func is_ball_free() -> bool:
	return true
