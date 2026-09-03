class_name PlayerStateChestControl
extends PlayerState

const DURATION_CONTROL := 500

var time_since_control := 0

func _enter_tree() -> void:
	animation_player.play("chest_control")
	player.velocity = Vector2.ZERO
	time_since_control = GameManager.get_match_time_ms()

func _physics_process(_delta: float) -> void:
	if GameManager.get_match_time_ms() - time_since_control > DURATION_CONTROL:
		transition_state(Player.State.MOVING)
	
func can_pass() -> bool:
	return true
