class_name BallStateShot
extends BallState

## 射门状态：高速、带弧线的射门
## 有重力（会下落）、有摩擦（会减速），碰到障碍物或超时后转自由球

const DURATION_SHOT := 1500  ## ms
const SHOT_HEIGHT := 8.0       ## 射门初始高度（像素）
const SHOT_SPRITE_SCALE := 0.8
const AIR_FRICTION_MULTIPLIER := 0.2
const GROUND_FRICTION := 120.0  ## px/s²，射门球的地面摩擦
const SHOT_DROP_MS := 600      ## ms 后开始明显下落（延迟重力，模拟抽射）

var time_since_shot := Time.get_ticks_msec()

func _enter_tree() -> void:
	set_ball_animation_from_velocity()
	sprite.scale.y = SHOT_SPRITE_SCALE
	ball.height = SHOT_HEIGHT
	ball.height_velocity = 0.0  ## 初始平射，稍后下落
	time_since_shot = Time.get_ticks_msec()
	shot_particles.emitting = true
	GameEvents.impact_received.emit(ball.position, true)

func _process(delta: float) -> void:
	var elapsed := Time.get_ticks_msec() - time_since_shot
	if elapsed > DURATION_SHOT:
		transition_state(Ball.State.FREEFORM)
		return

	# 空气/地面摩擦减速
	var friction: float
	if ball.height > 0:
		friction = GROUND_FRICTION * AIR_FRICTION_MULTIPLIER
	else:
		friction = GROUND_FRICTION
	ball.velocity = ball.velocity.move_toward(Vector2.ZERO, friction * delta)

	# 抽射前半段近似平飞，后半段开始下落（延迟重力）
	var gravity_scale: float = 1.0
	if elapsed < SHOT_DROP_MS:
		# 前 600ms 重力逐步增加，模拟抽射的"飘"
		gravity_scale = float(elapsed) / SHOT_DROP_MS
	process_gravity(delta, ball.BOUNCINESS * 0.5, gravity_scale)

	if move_and_bounce(delta):
		# 射门撞到障碍物（门柱/墙）→ 转自由球
		transition_state(Ball.State.FREEFORM)
		return

	set_ball_animation_from_velocity()

func process_gravity(delta: float, bounciness: float = 0.0, scale: float = 1.0) -> void:
	## 带缩放系数的重力处理（抽射前期重力减弱）
	if ball.height > 0 or ball.height_velocity > 0:
		ball.height_velocity -= PitchConstants.GRAVITY * delta * scale
		ball.height += ball.height_velocity * delta
		if ball.height < 0:
			ball.height = 0
			if bounciness > 0 and ball.height_velocity < 0:
				ball.height_velocity = -ball.height_velocity * bounciness

func can_air_interact() -> bool:
	return true

func _exit_tree() -> void:
	sprite.scale.y = 1.0
	shot_particles.emitting = false
