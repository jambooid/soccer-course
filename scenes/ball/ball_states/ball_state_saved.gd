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
	# 球刚被扑出时门将可能已经在检测区内，立即检查一次
	call_deferred("_check_immediate_goalie_catch")

func _process(delta: float) -> void:
	var friction := ball.friction_ground * 1.5
	if ball.height > 0:
		friction = ball.friction_ground * 0.4
	ball.velocity = ball.velocity.move_toward(Vector2.ZERO, friction * delta)

	process_gravity(delta, ball.BOUNCINESS * 0.8)
	move_and_bounce(delta)
	set_ball_animation_from_velocity()

	# 持续检测门将是否在附近（二次扑救兜底）
	_check_nearby_goalie()

	var elapsed := Time.get_ticks_msec() - time_started
	if elapsed > MAX_DURATION_MS:
		transition_state(Ball.State.FREEFORM)
	elif ball.velocity.length() < TRANSITION_SPEED and ball.height == 0:
		transition_state(Ball.State.FREEFORM)

func _check_immediate_goalie_catch() -> void:
	## 立即检测门将是否在球旁边（body_entered 的补充，处理门将已在检测区内的情况）
	if goalie == null:
		return
	var bodies := player_detection_area.get_overlapping_bodies()
	for body in bodies:
		if not (body is Player):
			continue
		if body == goalie and ball.height <= PitchConstants.HEIGHT_SAVED_GOALIE_CATCH:
			ball.carrier = body
			carrier = body
			transition_state(Ball.State.HELD_BY_GOALKEEPER)
			return

func _check_nearby_goalie() -> void:
	## 每帧检查：门将是否进入检测区（作为 body_entered 的兜底，处理球慢速滚动时的接触）
	if goalie == null:
		return
	if goalie.position.distance_to(ball.position) <= 12.0 \
			and ball.height <= PitchConstants.HEIGHT_SAVED_GOALIE_CATCH:
		ball.carrier = goalie
		carrier = goalie
		transition_state(Ball.State.HELD_BY_GOALKEEPER)

func on_player_enter(body: Player) -> void:
	if body.role == Player.Role.GOALIE and goalie != null and body == goalie:
		if ball.height < PitchConstants.HEIGHT_SAVED_GOALIE_CATCH:
			ball.carrier = body
			carrier = body
			transition_state(Ball.State.HELD_BY_GOALKEEPER)
	elif body.can_carry_ball() and ball.height < PitchConstants.HEIGHT_SAVED_PLAYER_PICKUP:
		ball.carrier = body
		body.control_ball()
		transition_state(Ball.State.CARRIED)

func can_air_interact() -> bool:
	return true
