class_name BallStateFactory

var states : Dictionary

func _init() -> void:
	states = {
		Ball.State.CARRIED: BallStateCarried,
		Ball.State.FREEFORM: BallStateFreeform,
		Ball.State.SHOT: BallStateShot,
		Ball.State.KICKED: BallStateKicked,
		Ball.State.SAVED: BallStateSaved,
		Ball.State.DEFLECTED: BallStateDeflected,
		Ball.State.HELD_BY_GOALKEEPER: BallStateHeldByGoalkeeper,
		Ball.State.DRIBBLING: BallStateDribbling,
	}

func get_fresh_state(state: Ball.State) -> BallState:
	assert(states.has(state), "state doesn't exist!")
	return states.get(state).new()
