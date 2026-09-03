class_name PlayerStateHurt
extends PlayerState

const AIR_FRICTION := 35.0
const DURATION_HURT := 1000
const HURT_HEIGHT_VELOCITY := 3.0

## 球滚动速度（使用 PitchConstants 集中管理）
const BALL_TUMBLE_SPEED := PitchConstants.PLAYER.HURT_BALL_TUMBLE_SPEED

var time_start_hurt := 0

func _enter_tree() -> void:
	animation_player.play("hurt")
	time_start_hurt = GameManager.get_match_time_ms()
	player.height_velocity = HURT_HEIGHT_VELOCITY
	player.height = 0.1
	if ball.carrier == player:
		ball.tumble(state_data.hurt_direction * BALL_TUMBLE_SPEED)
		SoundPlayer.play(SoundPlayer.Sound.HURT)
		GameEvents.impact_received.emit(player.position, false)

func _physics_process(delta: float) -> void:
	if GameManager.get_match_time_ms() - time_start_hurt > DURATION_HURT:
		transition_state(Player.State.RECOVERING)
	player.velocity = player.velocity.move_toward(Vector2.ZERO, delta * AIR_FRICTION)
