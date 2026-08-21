class_name BallStateCarried
extends BallState

## 带球状态：球按步点节奏跟随球员，不是胶水式粘附
## 核心机制：每步触一次球，两次触球之间球"离脚"=抢断窗口

const TOUCH_INTERVAL_MIN := 0.14
const TOUCH_INTERVAL_MAX := 0.32
const TOUCH_OFFSET_MIN := 5.0
const TOUCH_OFFSET_MAX := 16.0
const FREE_BALL_DURATION := 0.10
const BALL_SPEED_MULTIPLIER := 1.15

var touch_timer := 0.0
var touch_interval := 0.25
var _is_ball_free := false
var free_ball_timer := 0.0

func _enter_tree() -> void:
	assert(carrier != null)
	GameEvents.ball_possessed.emit(carrier.fullname)
	GameEvents.ball_possessed_by.emit(carrier)
	var technique_factor: float = clamp(carrier.technique / 100.0, 0.0, 1.0)
	touch_interval = lerp(TOUCH_INTERVAL_MAX, TOUCH_INTERVAL_MIN, technique_factor)
	var offset := carrier.heading * TOUCH_OFFSET_MIN
	ball.position = carrier.position + offset
	_is_ball_free = false
	touch_timer = 0.0
	free_ball_timer = 0.0
	# 连接对手检测（仅在离脚窗口生效）
	player_detection_area.body_entered.connect(_on_player_opponent_near.bind())
	player_detection_area.monitoring = false

func _process(delta: float) -> void:
	if carrier.velocity == Vector2.ZERO:
		_process_idle(delta)
	else:
		_process_running(delta)

	if carrier.velocity == Vector2.ZERO:
		animation_player.play("idle")
	elif carrier.heading.x >= 0:
		animation_player.play("roll")
		animation_player.advance(0)
	else:
		animation_player.play_backwards("roll")
		animation_player.advance(0)

func _process_idle(_delta: float) -> void:
	var offset := Vector2(carrier.heading.x * TOUCH_OFFSET_MIN, 4.0)
	ball.position = carrier.position + offset
	_is_ball_free = false
	touch_timer = 0.0

func _process_running(delta: float) -> void:
	touch_timer += delta

	if _is_ball_free:
		free_ball_timer -= delta
		ball.position += ball.velocity * delta
		ball.velocity = ball.velocity.move_toward(Vector2.ZERO, carrier.speed * 0.3 * delta)
		# 离脚窗口 = 抢断窗口，打开检测区
		player_detection_area.monitoring = true
		# 每帧检查一次自动断球（对检测区内的对手）
		_check_auto_intercept()

		if free_ball_timer <= 0.0:
			_is_ball_free = false
			ball.velocity = Vector2.ZERO
			player_detection_area.monitoring = false
	else:
		player_detection_area.monitoring = false

	if touch_timer >= touch_interval and not _is_ball_free:
		touch_timer = 0.0
		_perform_touch()

func _perform_touch() -> void:
	var speed := carrier.velocity.length()
	var speed_factor: float = clamp(speed / carrier.speed, 0.0, 1.0)
	var touch_distance: float = lerp(TOUCH_OFFSET_MIN, TOUCH_OFFSET_MAX, speed_factor)

	ball.position = carrier.position + carrier.heading * touch_distance
	ball.velocity = carrier.heading * speed * BALL_SPEED_MULTIPLIER

	_is_ball_free = true
	free_ball_timer = FREE_BALL_DURATION

func is_ball_free() -> bool:
	return _is_ball_free

func _check_auto_intercept() -> void:
	## 检查检测区内的对手球员是否能自动断球
	var bodies := player_detection_area.get_overlapping_bodies()
	var best_defender: Player = null
	var best_quality := -1.0

	for body in bodies:
		if not (body is Player):
			continue
		var p: Player = body
		# 只考虑对手球员
		if p.country == carrier.country:
			continue
		# 门将有专门的抱球逻辑，不走自动断球
		if p.role == Player.Role.GOALIE:
			continue
		# 不在控球状态的球员才能断球（正在做其他动作时不行）
		if not p.can_carry_ball():
			continue
		var result := InterceptResolver.check_auto_intercept(p, ball)
		if result.success and result.quality > best_quality:
			best_quality = result.quality
			best_defender = p

	if best_defender != null:
		_trigger_intercept(best_defender, best_quality)

func _trigger_intercept(defender: Player, quality: float) -> void:
	## 触发自动断球：球权转移给防守者
	# 带球的人进入受击/失球反馈
	if carrier.has_method("on_ball_stolen"):
		carrier.on_ball_stolen(defender)

	# 球转给防守者
	ball.carrier = defender
	defender.control_ball()
	defender.velocity = defender.velocity * 0.5  # 断球后稍微减速
	transition_state(Ball.State.CARRIED)

func _on_player_opponent_near(body: Node) -> void:
	## 对手球员刚进入检测区（作为补充触发）
	if not _is_ball_free:
		return
	if not (body is Player):
		return
	var p: Player = body
	if p.country == carrier.country:
		return
	if p.role == Player.Role.GOALIE:
		return
	# 立即检查一次断球
	var result := InterceptResolver.check_auto_intercept(p, ball)
	if result.success:
		_trigger_intercept(p, result.quality)

func _exit_tree() -> void:
	GameEvents.ball_released.emit()
