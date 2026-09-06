class_name MatchFlow
extends RefCounted

## Shared phase and restart vocabulary for simulation and presentation.

enum Phase {
	KICKOFF,
	FIRST_HALF,
	GOAL_RESULT,
	SET_PIECE,
	HALFTIME,
	SECOND_HALF,
	STOPPAGE_TIME,
	FULL_TIME,
}

enum RestartType {
	KICKOFF,
	THROW_IN,
	CORNER,
	GOAL_KICK,
	INDIRECT,
}

static func is_live_phase(phase: int) -> bool:
	return phase == Phase.FIRST_HALF or phase == Phase.SECOND_HALF or phase == Phase.STOPPAGE_TIME

static func phase_name(phase: int) -> String:
	match phase:
		Phase.KICKOFF: return "KICKOFF"
		Phase.FIRST_HALF: return "FIRST_HALF"
		Phase.GOAL_RESULT: return "GOAL_RESULT"
		Phase.SET_PIECE: return "SET_PIECE"
		Phase.HALFTIME: return "HALFTIME"
		Phase.SECOND_HALF: return "SECOND_HALF"
		Phase.STOPPAGE_TIME: return "STOPPAGE_TIME"
		Phase.FULL_TIME: return "FULL_TIME"
	return "UNKNOWN"

static func restart_name(restart_type: int) -> String:
	match restart_type:
		RestartType.KICKOFF: return "KICKOFF"
		RestartType.THROW_IN: return "THROW IN"
		RestartType.CORNER: return "CORNER"
		RestartType.GOAL_KICK: return "GOAL KICK"
		RestartType.INDIRECT: return "INDIRECT"
	return "RESTART"
