class_name BallStateFreeform
extends BallState

const BallInteractionResolverScript := preload("res://utils/ball_interaction_resolver.gd")

const MAX_CAPTURE_HEIGHT := PitchConstants.HEIGHT_FREEFORM_PICKUP_MAX

## 自动接球常量（使用 PitchConstants 集中管理）
const AUTO_CAPTURE_DISTANCE := PitchConstants.BALL.FREEFORM_AUTO_CAPTURE_DIST
const AUTO_CAPTURE_CHECK_INTERVAL := PitchConstants.BALL.FREEFORM_AUTO_CAPTURE_CHECK_INTERVAL

var time_since_freeform := Time.get_ticks_msec()
var capture_check_frame := 0
var _contact_candidates: Array[Player] = []

func _enter_tree() -> void:
	player_detection_area.body_entered.connect(on_player_enter.bind())
	time_since_freeform = Time.get_ticks_msec()

func on_player_enter(body: Player) -> void:
	# Area callbacks are broad-phase candidate collection only. Authoritative
	# capture is resolved once per physics tick in _check_auto_capture().
	if body != null and not _contact_candidates.has(body):
		_contact_candidates.append(body)

func _physics_process(delta: float) -> void:
	player_detection_area.monitoring = (Time.get_ticks_msec() - time_since_freeform > state_data.lock_duration)
	set_ball_animation_from_velocity()
	var friction := ball.friction_air if ball.height > 0 else ball.friction_ground
	ball.velocity = ball.velocity.move_toward(Vector2.ZERO, friction * delta)
	process_gravity(delta, ball.BOUNCINESS)
	move_and_bounce(delta)

	# 主动接球检测（每 3 帧检测一次）
	capture_check_frame += 1
	if capture_check_frame >= AUTO_CAPTURE_CHECK_INTERVAL:
		capture_check_frame = 0
		_check_auto_capture()

func can_air_interact() -> bool:
	return true

func _check_auto_capture() -> void:
	## 主动接球检测：球滚到球员脚边时自动获得球权
	## 解决问题：球员已经在 player_detection_area 内时，body_entered 不会触发

	# 只在 monitoring 开启且不处于开球等待时检测。
	if not player_detection_area.monitoring or not ball.is_pickup_enabled():
		return

	# 球太高不能接
	if ball.height >= MAX_CAPTURE_HEIGHT:
		return

	# 获取所有在检测区内的球员
	var nearby_players: Array[Node2D] = player_detection_area.get_overlapping_bodies()
	for candidate in _contact_candidates:
		if is_instance_valid(candidate) and not nearby_players.has(candidate):
			nearby_players.append(candidate)
	_contact_candidates.clear()
	if nearby_players.is_empty():
		return

	var intents: Array[Dictionary] = []
	for body in nearby_players:
		if not (body is Player):
			continue
		var player: Player = body
		if not ball.can_be_picked_up_by(player):
			continue
		var distance := player.position.distance_to(ball.position)
		if player.role == Player.Role.GOALIE:
			intents.append(BallInteractionResolverScript.create_intent(
				BallInteractionResolverScript.Kind.COLLECT,
				player.jersey_number, {"distance": distance,
				"eligible": ball.height <= PitchConstants.HEIGHT_GOALIE_CATCH_MAX}))
		elif player.can_carry_ball() and distance <= AUTO_CAPTURE_DISTANCE:
			intents.append(BallInteractionResolverScript.create_intent(
				BallInteractionResolverScript.Kind.CONTROL,
				player.jersey_number, {"distance": distance,
				"player": player}))

	var resolved := BallInteractionResolverScript.resolve(intents)
	if resolved.is_empty():
		return
	var winner: Player = null
	for body in nearby_players:
		if body is Player and (body as Player).jersey_number == int(resolved.player_id):
			winner = body
			break
	if winner == null:
		return
	if winner.role == Player.Role.GOALIE:
		ball.hold_by_goalkeeper(winner)
	else:
		ball.carrier = winner
		winner.control_ball()
		transition_state(Ball.State.DRIBBLING)
