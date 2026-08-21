class_name GameStateFactory

var states : Dictionary

func _init() -> void:
	states = {
		GameManager.State.FIRST_HALF: GameStateFirstHalf,
		GameManager.State.SECOND_HALF: GameStateSecondHalf,
		GameManager.State.HALFTIME: GameStateHalftime,
		GameManager.State.GAMEOVER: GameStateGameOver,
		GameManager.State.IN_PLAY: GameStateInPlay,  # 保留兼容，实际不再使用
		GameManager.State.KICKOFF: GameStateKickoff,
		GameManager.State.OVERTIME: GameStateOvertime,
		GameManager.State.RESET: GameStateReset,
		GameManager.State.SCORED: GameStateScored,
	}

func get_fresh_state(state: GameManager.State) -> GameState:
	assert(states.has(state), "state does not exist")
	return states.get(state).new()
