class_name BallState
extends Node

signal state_transition_requested(new_state: Ball.State, data: BallStateData)

var animation_player : AnimationPlayer = null
var ball : Ball = null
var carrier : Player = null
var player_detection_area : Area2D = null
var shot_particles : GPUParticles2D = null
var sprite : Sprite2D = null
var state_data : BallStateData = null

func setup(context_ball: Ball, context_state_data: BallStateData, context_player_detection_area: Area2D, context_carrier: Player, context_animation_player: AnimationPlayer, context_sprite: Sprite2D, context_shot_particles: GPUParticles2D) -> void:
	ball = context_ball
	player_detection_area = context_player_detection_area
	carrier = context_carrier
	animation_player = context_animation_player
	sprite = context_sprite
	state_data = context_state_data
	shot_particles = context_shot_particles

func transition_state(new_state: Ball.State, data: BallStateData = BallStateData.new()) -> void:
	state_transition_requested.emit(new_state, data)

func set_ball_animation_from_velocity() -> void:
	# 摩擦减速会产生极小的非零速度，使用阈值避免静止后继续播放滚动动画。
	if ball.velocity.length() < 1.0:
		ball.velocity = Vector2.ZERO
		animation_player.play("idle")
	elif ball.velocity.x > 0:
		animation_player.play("roll")
		animation_player.advance(0)
	else:
		animation_player.play_backwards("roll")
		animation_player.advance(0)

func process_gravity(delta: float, bounciness: float = 0.0) -> void:
	if ball.height > 0 or ball.height_velocity > 0:
		ball.height_velocity -= PitchConstants.GRAVITY * delta
		ball.height += ball.height_velocity * delta
		if ball.height < 0:
			ball.height = 0
			if bounciness > 0 and ball.height_velocity < 0:
				ball.height_velocity = -ball.height_velocity * bounciness
				ball.velocity *= bounciness

func move_and_bounce(delta: float) -> bool:
	## 返回是否发生了碰撞，供子类决定是否切换状态
	var collision := ball.move_and_collide(ball.velocity * delta)
	if collision != null:
		ball.velocity = ball.velocity.bounce(collision.get_normal()) * ball.BOUNCINESS
		SoundPlayer.play(SoundPlayer.Sound.BOUNCE)
		return true
	return false

func can_air_interact() -> bool:
	return false

func is_ball_free() -> bool:
	## 球是否处于"离脚/自由"状态（可被抢断的窗口）
	## 由各状态子类重写，默认 false
	return false

func release_with_throw(_target_pos: Vector2) -> void:
	## 手抛球发球（默认空实现，HELD_BY_GOALKEEPER 状态重写）
	pass

func release_with_kick(_target_pos: Vector2) -> void:
	## 大脚开球（默认空实现，HELD_BY_GOALKEEPER 状态重写）
	pass
