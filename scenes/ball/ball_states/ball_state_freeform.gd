class_name BallStateFreeform
extends BallState

const MAX_CAPTURE_HEIGHT := PitchConstants.HEIGHT_FREEFORM_PICKUP_MAX

## 自动接球常量（使用 PitchConstants 集中管理）
const AUTO_CAPTURE_DISTANCE := PitchConstants.BALL.FREEFORM_AUTO_CAPTURE_DIST
const AUTO_CAPTURE_CHECK_INTERVAL := PitchConstants.BALL.FREEFORM_AUTO_CAPTURE_CHECK_INTERVAL

var time_since_freeform := Time.get_ticks_msec()
var capture_check_frame := 0

func _enter_tree() -> void:
	player_detection_area.body_entered.connect(on_player_enter.bind())
	time_since_freeform = Time.get_ticks_msec()

func on_player_enter(body: Player) -> void:
	if not ball.can_be_picked_up_by(body):
		return

	# 守门员专用抱球逻辑
	if body.role == Player.Role.GOALIE:
		if ball.height <= PitchConstants.HEIGHT_GOALIE_CATCH_MAX:
			ball.hold_by_goalkeeper(body)  # 内部已切换状态，无需再调 transition_state
		return

	if body.can_carry_ball() and ball.height < MAX_CAPTURE_HEIGHT:
		ball.carrier = body
		body.control_ball()
		transition_state(Ball.State.DRIBBLING)

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
	if nearby_players.is_empty():
		return

	# 找到最近的、可以控球的球员
	var closest_player: Player = null
	var closest_distance := AUTO_CAPTURE_DISTANCE

	for body in nearby_players:
		if not (body is Player):
			continue
		var player: Player = body
		if not ball.can_be_picked_up_by(player):
			continue

		# 守门员有专门的抱球逻辑，跳过
		if player.role == Player.Role.GOALIE:
			continue

		# 只考虑可以控球的球员
		if not player.can_carry_ball():
			continue

		var distance := player.position.distance_to(ball.position)
		if distance < closest_distance:
			closest_distance = distance
			closest_player = player

	if closest_player == null:
		return

	# 检查是否有对抗：附近是否有对方球员距离更近或相近
	var has_contest := false
	for body in nearby_players:
		if not (body is Player):
			continue
		var other: Player = body
		if not ball.can_be_picked_up_by(other):
			continue

		# 跳过己方球员
		if other.country == closest_player.country:
			continue

		# 跳过不能控球的球员
		if not other.can_carry_ball():
			continue

		var other_distance := other.position.distance_to(ball.position)
		# 对方球员距离相近（5px 容差）→ 有对抗
		if other_distance < closest_distance + 5.0:
			has_contest = true
			break

	# 无对抗情况下，给予球权
	if not has_contest:
		ball.carrier = closest_player
		closest_player.control_ball()
		transition_state(Ball.State.DRIBBLING)
