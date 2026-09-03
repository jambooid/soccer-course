class_name GameStateScored
extends GameState

const DURATION_CELEBRATION := 3000

var time_since_celebration := 0

func _enter_tree() -> void:
	manager.increase_score(state_data.country_scored_on)
	time_since_celebration = manager.get_match_time_ms()

func _physics_process(_delta: float) -> void:
	if manager.get_match_time_ms() - time_since_celebration > DURATION_CELEBRATION:
		# 保留半场信息，传递给 RESET → KICKOFF 链路
		transition_state(GameManager.State.RESET, state_data)
