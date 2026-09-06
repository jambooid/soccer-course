class_name MatchFlowController
extends RefCounted

const Flow := preload("res://utils/match_flow.gd")
const Event := preload("res://utils/match_event.gd")

var half_duration := 90.0
var stoppage_duration := 0.0
var presentation_duration := 1.4
var halftime_duration := 3.0
var phase := Flow.Phase.KICKOFF
var half := 1
var clock := 90.0
var phase_timer := 1.4
var score_home := 0
var score_away := 0
var restart_team_home := true
var pending_restart: Dictionary = {}
var goal_records: Array[Dictionary] = []
var tick := 0
var _events: Array[MatchEvent] = []
var _goal_locked := false

func _init(config: Dictionary = {}) -> void:
	half_duration = float(config.get("half_duration", half_duration))
	stoppage_duration = float(config.get("stoppage_duration", stoppage_duration))
	presentation_duration = float(config.get("presentation_duration", presentation_duration))
	halftime_duration = float(config.get("halftime_duration", halftime_duration))
	clock = half_duration
	phase_timer = presentation_duration

func advance(delta: float) -> void:
	var step := maxf(delta, 0.0)
	tick += 1
	match phase:
		Flow.Phase.KICKOFF:
			phase_timer -= step
			if phase_timer <= 0.0:
				phase = Flow.Phase.FIRST_HALF if half == 1 else Flow.Phase.SECOND_HALF
				_emit("kickoff_live", {"half": half, "restart": pending_restart.duplicate(true)})
				pending_restart.clear()
		Flow.Phase.GOAL_RESULT, Flow.Phase.SET_PIECE:
			phase_timer -= step
			if phase_timer <= 0.0:
				phase = Flow.Phase.KICKOFF if pending_restart.get("type", Flow.RestartType.KICKOFF) == Flow.RestartType.KICKOFF else phase
				if phase == Flow.Phase.KICKOFF:
					phase_timer = presentation_duration
					_emit("restart_ready", pending_restart.duplicate(true))
				else:
					phase = Flow.Phase.SECOND_HALF if half == 2 else Flow.Phase.FIRST_HALF
					_emit("restart_live", pending_restart.duplicate(true))
				pending_restart.clear()
		Flow.Phase.FIRST_HALF, Flow.Phase.SECOND_HALF:
			clock = maxf(clock - step, 0.0)
			if clock <= 0.0:
				if phase == Flow.Phase.FIRST_HALF:
					half = 2
					phase = Flow.Phase.HALFTIME
					phase_timer = halftime_duration
					_emit("halftime", {"score_home": score_home, "score_away": score_away})
				else:
					phase = Flow.Phase.STOPPAGE_TIME
					phase_timer = stoppage_duration
					_emit("stoppage_time", {"duration": stoppage_duration})
		Flow.Phase.HALFTIME:
			phase_timer -= step
			if phase_timer <= 0.0:
				clock = half_duration
				phase = Flow.Phase.KICKOFF
				phase_timer = presentation_duration
				pending_restart = {"type": Flow.RestartType.KICKOFF, "team_home": restart_team_home}
				_emit("second_half_ready", {"half": 2})
		Flow.Phase.STOPPAGE_TIME:
			phase_timer -= step
			if phase_timer <= 0.0:
				phase = Flow.Phase.FULL_TIME
				_emit("full_time", {"score_home": score_home, "score_away": score_away,
					"goals": goal_records.duplicate(true)})

func force_live() -> void:
	if phase == Flow.Phase.KICKOFF:
		phase_timer = 0.0
		advance(0.0)

func record_goal(home_scored: bool, scorer_id: int = -1, assist_id: int = -1) -> bool:
	if _goal_locked or not Flow.is_live_phase(phase):
		return false
	_goal_locked = true
	if home_scored:
		score_home += 1
	else:
		score_away += 1
	var record := {"home": home_scored, "scorer_id": scorer_id,
		"assist_id": assist_id, "half": half, "minute": int(half_duration - clock)}
	goal_records.append(record)
	restart_team_home = not home_scored
	pending_restart = {"type": Flow.RestartType.KICKOFF, "team_home": restart_team_home,
		"reason": "GOAL", "position": Vector3.ZERO}
	phase = Flow.Phase.GOAL_RESULT
	phase_timer = presentation_duration
	_emit("goal", record)
	return true

func begin_restart(restart_type: int, team_home: bool, position: Vector3, reason := "BOUNDARY") -> void:
	pending_restart = {"type": restart_type, "team_home": team_home,
		"position": position, "reason": reason}
	if restart_type == Flow.RestartType.KICKOFF:
		phase = Flow.Phase.KICKOFF
		phase_timer = presentation_duration
	else:
		phase = Flow.Phase.SET_PIECE
		phase_timer = presentation_duration
	if restart_type != Flow.RestartType.KICKOFF:
		_emit("restart", pending_restart.duplicate(true))

func consume_events() -> Array[MatchEvent]:
	var events := _events
	_events = []
	return events

func _emit(name: String, payload: Dictionary) -> void:
	_events.append(Event.new(name, tick, payload))
	if name == "kickoff_live" or name == "restart_live":
		_goal_locked = false
