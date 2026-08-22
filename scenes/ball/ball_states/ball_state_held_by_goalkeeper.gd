class_name BallStateHeldByGoalkeeper
extends BallState

## 被守门员抱在手中的状态
## 球跟随门将，不能被抢断，有持球时间限制

const HOLD_DURATION_MAX_MS := 3000
const HOLD_OFFSET_Y := -10.0   ## 抱球高度（相对于球员脚部，负值=向上）
const HOLD_OFFSET_X := 6.0     ## 抱球水平偏移（身前距离）

var time_held := 0

func _enter_tree() -> void:
	assert(carrier != null)
	assert(carrier.role == Player.Role.GOALIE)
	time_held = Time.get_ticks_msec()
	ball.velocity = Vector2.ZERO
	ball.height = 0.0
	ball.height_velocity = 0.0
	GameEvents.ball_possessed.emit(carrier.fullname)
	GameEvents.ball_possessed_by.emit(carrier)
	animation_player.play("idle")

func _process(_delta: float) -> void:
	# 球在守门员身前（手中），根据朝向调整水平偏移
	var offset := Vector2(carrier.heading.x * HOLD_OFFSET_X, HOLD_OFFSET_Y)
	ball.position = carrier.position + offset

	if Time.get_ticks_msec() - time_held > HOLD_DURATION_MAX_MS:
		_auto_kick()

func _auto_kick() -> void:
	var direction := carrier.heading
	var kick_velocity := direction * carrier.power * 0.7
	ball.velocity = kick_velocity
	ball.height_velocity = 6.0
	var gk_ref := carrier
	carrier = null
	ball.carrier = null
	transition_state(Ball.State.KICKED, BallStateData.build().set_kicker(gk_ref))

func release_with_throw(target_pos: Vector2) -> void:
	var direction := ball.position.direction_to(target_pos)
	var distance := ball.position.distance_to(target_pos)
	var intensity := sqrt(2 * distance * ball.friction_ground) * 0.8
	ball.velocity = direction * intensity
	var gk_ref := carrier
	carrier = null
	ball.carrier = null
	transition_state(Ball.State.KICKED, BallStateData.build().set_kicker(gk_ref))

func release_with_kick(target_pos: Vector2) -> void:
	var direction := ball.position.direction_to(target_pos)
	var distance := ball.position.distance_to(target_pos)
	var intensity := sqrt(2 * distance * ball.friction_ground * 0.7)
	ball.velocity = direction * intensity
	ball.height_velocity = BallState.GRAVITY * distance / (1.5 * intensity)
	var gk_ref := carrier
	carrier = null
	ball.carrier = null
	transition_state(Ball.State.KICKED, BallStateData.build().set_kicker(gk_ref))

func put_down() -> void:
	ball.position = carrier.position + carrier.heading * 8.0
	ball.velocity = Vector2.ZERO
	transition_state(Ball.State.CARRIED)

func is_ball_free() -> bool:
	return false
