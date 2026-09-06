extends SceneTree

const Flow := preload("res://utils/match_flow.gd")
const Controller := preload("res://utils/match_flow_controller.gd")
const Snapshot := preload("res://utils/match_snapshot.gd")
const Replay := preload("res://utils/replay_buffer.gd")

var passed := 0
var failed := 0

func _init() -> void:
	_test_kickoff_and_goal()
	_test_restart_classification_payload()
	_test_halftime_and_full_time()
	_test_snapshot_isolation()
	_test_replay_fallback_and_copy()
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _expect(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("  [PASS] %s" % label)
	else:
		failed += 1
		print("  [FAIL] %s" % label)

func _test_kickoff_and_goal() -> void:
	var flow := Controller.new({"half_duration": 20.0, "presentation_duration": 0.2})
	flow.advance(0.2)
	_expect(flow.phase == Flow.Phase.FIRST_HALF, "kickoff enters first-half live phase")
	flow.advance(1.0)
	var before := flow.clock
	_expect(before < 20.0, "live phase advances match clock")
	_expect(flow.record_goal(true, 9, 8), "first goal is accepted")
	_expect(not flow.record_goal(true, 9, 8), "duplicate goal in result window is rejected")
	_expect(flow.score_home == 1 and flow.phase == Flow.Phase.GOAL_RESULT,
		"goal updates score once and pauses in result phase")
	var events := flow.consume_events()
	_expect(_has_event(events, "goal"), "goal emits a shared event")
	flow.advance(0.2)
	_expect(flow.phase == Flow.Phase.KICKOFF, "goal result schedules kickoff restart")

func _test_restart_classification_payload() -> void:
	var flow := Controller.new({"presentation_duration": 0.1})
	var corner := Vector3(0.0, 0.0, 0.0)
	flow.begin_restart(Flow.RestartType.CORNER, true, corner, "DEFENDER_LAST_TOUCH")
	_expect(flow.phase == Flow.Phase.SET_PIECE and flow.pending_restart.get("team_home") == true,
		"corner restart stores team and location")
	var events := flow.consume_events()
	_expect(_has_event(events, "restart"), "set piece emits a restart event")
	flow.advance(0.1)
	_expect(flow.phase == Flow.Phase.FIRST_HALF, "non-kickoff restart returns to live phase")

func _test_halftime_and_full_time() -> void:
	var flow := Controller.new({"half_duration": 0.1, "halftime_duration": 0.1,
		"presentation_duration": 0.05, "stoppage_duration": 0.1})
	flow.advance(0.05)
	flow.advance(0.1)
	_expect(flow.phase == Flow.Phase.HALFTIME and flow.half == 2,
		"first-half expiry enters halftime and increments half")
	_expect(_has_event(flow.consume_events(), "halftime"), "halftime emits a shared event")
	flow.advance(0.1)
	_expect(flow.phase == Flow.Phase.KICKOFF, "halftime schedules second-half kickoff")
	flow.advance(0.05)
	_expect(flow.phase == Flow.Phase.SECOND_HALF, "second-half kickoff becomes live")
	flow.advance(0.1)
	_expect(flow.phase == Flow.Phase.STOPPAGE_TIME, "second-half expiry enters stoppage time")
	flow.advance(0.1)
	_expect(flow.phase == Flow.Phase.FULL_TIME, "stoppage expiry enters full time")
	_expect(_has_event(flow.consume_events(), "full_time"), "full time emits exactly one terminal event")
	var phase_after := flow.phase
	flow.advance(1.0)
	_expect(flow.phase == phase_after, "full time remains terminal")

func _test_snapshot_isolation() -> void:
	var source := {"tick": 4, "players": [{"id": 1, "position": Vector3.ZERO}],
		"ball": {"position": Vector3(1.0, 0.0, 0.0)}, "radar": [{"id": 1, "x": 0.0}]}
	var snapshot := Snapshot.new(source)
	source.players[0].position = Vector3(9.0, 0.0, 0.0)
	var retained := snapshot.copy()
	retained.players[0].position = Vector3(7.0, 0.0, 0.0)
	_expect(snapshot.players[0].position == Vector3.ZERO,
		"snapshot construction and retained copies deep-copy nested player data")
	_expect(snapshot.ball.position == Vector3(1.0, 0.0, 0.0),
		"snapshot protects nested ball data")

func _test_replay_fallback_and_copy() -> void:
	var replay := Replay.new(2)
	_expect(replay.snapshot_frames().is_empty(), "empty replay history has a safe fallback")
	for tick in range(3):
		replay.append(Snapshot.new({"tick": tick, "players": [{"id": 1, "position": Vector3(tick, 0.0, 0.0)}]}))
	_expect(replay.size() == 2, "replay history is bounded")
	var frames := replay.snapshot_frames(2)
	frames[0].players[0].position = Vector3(99.0, 0.0, 0.0)
	_expect(replay.latest().players[0].position != Vector3(99.0, 0.0, 0.0),
		"replay returns copied frames")

func _has_event(events: Array, name: String) -> bool:
	for event in events:
		if event.name == name:
			return true
	return false
