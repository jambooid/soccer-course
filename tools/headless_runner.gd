extends SceneTree

const SeededRngScript := preload("res://utils/seeded_rng.gd")
const DribblePhysicsScript := preload("res://utils/dribble_physics.gd")
const ShootingPhysicsScript := preload("res://utils/shooting_physics.gd")
const DribbleSuiteScript := preload("res://tools/test_dribbling.gd")
const ShootingSuiteScript := preload("res://features/shooting/tests/test_physics.gd")
const MatchSnapshotScript := preload("res://utils/match_snapshot.gd")
const MatchSimulationScript := preload("res://utils/match_simulation.gd")
const BallTrajectoryScript := preload("res://utils/ball_trajectory.gd")
const BallInteractionResolverScript := preload("res://utils/ball_interaction_resolver.gd")
const ControlProfileScript := preload("res://utils/control_profile.gd")
const TeamTacticsScript := preload("res://utils/team_tactics.gd")

var _passed := 0
var _failed := 0
var _current_suite := ""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_run_suite("seeded_rng", _test_seeded_rng)
	_run_suite("dribble_physics", _test_dribble_physics)
	_run_suite("shooting_physics", _test_shooting_physics)
	_run_suite("match_snapshot", _test_match_snapshot)
	_run_suite("match_simulation", _test_match_simulation)
	_run_suite("ball_trajectory", _test_ball_trajectory)
	_run_suite("ball_interaction_resolver", _test_ball_interaction_resolver)
	_run_suite("control_profile", _test_control_profile)
	_run_suite("team_tactics", _test_team_tactics)
	_run_suite("legacy_dribble_suite", _run_legacy_dribble_suite)
	_run_suite("legacy_shooting_suite", _run_legacy_shooting_suite)
	if "--headless-runner-fail" in OS.get_cmdline_user_args():
		_expect(false, "intentional failure fixture")
	print("HEADLESS_SUMMARY passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _run_suite(name: String, suite: Callable) -> void:
	_current_suite = name
	print("SUITE %s" % name)
	suite.call()

func _test_seeded_rng() -> void:
	var first := SeededRngScript.new(421337)
	var second := SeededRngScript.new(421337)
	for index in range(8):
		_expect(first.randf() == second.randf(), "same seed sample %d" % index)
	var saved_state := first.get_state()
	var expected := first.randf()
	first.set_state(saved_state)
	_expect(first.randf() == expected, "restored RNG state")

func _test_dribble_physics() -> void:
	var velocity := Vector2(100.0, 0.0)
	var after_one_second := DribblePhysicsScript.apply_friction(velocity, 1.0)
	_expect(is_equal_approx(after_one_second.x, 35.0), "exponential friction")
	_expect(DribblePhysicsScript.is_ball_in_touch_zone(
		Vector2(7.0, 0.0), Vector2.ZERO, Vector2.RIGHT, 64.0
	), "front touch zone")
	_expect(not DribblePhysicsScript.is_ball_in_touch_zone(
		Vector2(-2.0, 0.0), Vector2.ZERO, Vector2.RIGHT, 64.0
	), "back touch zone")

func _test_shooting_physics() -> void:
	var low_charge := ShootingPhysicsScript.compute_shot_speed(60.0, 60.0, 0.2, 120.0, 60.0)
	var high_charge := ShootingPhysicsScript.compute_shot_speed(60.0, 60.0, 1.0, 120.0, 60.0)
	_expect(high_charge >= low_charge, "shot charge does not reduce speed")
	var aim := ShootingPhysicsScript.compute_aim_direction(
		Vector2.ZERO, Vector2.RIGHT, Vector2(100.0, 0.0), Vector2(0.0, 1.0), 70.0
	)
	_expect(aim.x > 0.0 and aim.y > 0.0, "shot lane remains goal-directed")

func _test_match_snapshot() -> void:
	var snapshot := MatchSnapshotScript.new()
	snapshot.tick = 42
	snapshot.match_seed = 421337
	snapshot.rng_state = 9988
	snapshot.ball.position = Vector2(12.0, 18.0)
	snapshot.players = [{"id": 2, "position": Vector2(3.0, 4.0)}, {"id": 1, "position": Vector2(1.0, 2.0)}]
	var duplicate := snapshot.clone()
	_expect(snapshot.tick_hash() == duplicate.tick_hash(), "cloned snapshot has stable hash")
	duplicate.players.reverse()
	_expect(snapshot.tick_hash() == duplicate.tick_hash(), "player order does not change hash")

func _test_match_simulation() -> void:
	var initial := MatchSnapshotScript.new()
	initial.ball.velocity = Vector2(120.0, 0.0)
	var first := MatchSimulationScript.new(90, initial)
	var second := MatchSimulationScript.new(90, initial)
	for ignored in range(60):
		first.advance()
		second.advance()
	_expect(first.snapshot.tick == 60, "advances at fixed tick count")
	_expect(first.snapshot.tick_hash() == second.snapshot.tick_hash(), "same seed and ticks remain deterministic")
	_expect(is_equal_approx(first.snapshot.ball.position.x, 120.0), "fixed tick ball displacement")
	var at_30hz := MatchSimulationScript.new(90, initial)
	var at_120hz := MatchSimulationScript.new(90, initial)
	for ignored in range(30):
		at_30hz.advance_render(1.0 / 30.0)
	for ignored in range(120):
		at_120hz.advance_render(1.0 / 120.0)
	_expect(at_30hz.snapshot.tick_hash() == at_120hz.snapshot.tick_hash(), "render cadence does not change replay")
	var contest_a := MatchSimulationScript.new(1234, initial)
	var contest_b := MatchSimulationScript.new(1234, initial)
	var result_a := contest_a.resolve_seeded_event("contest", 0.5)
	var result_b := contest_b.resolve_seeded_event("contest", 0.5)
	_expect(result_a == result_b, "seeded contest result is repeatable")
	_expect(contest_a.snapshot.rng_state == contest_b.snapshot.rng_state, "contest records RNG state")

func _test_ball_trajectory() -> void:
	var initial := Vector2.ZERO
	var target := Vector2(120.0, 0.0)
	var velocity := BallTrajectoryScript.velocity_for_ground_target(initial, target, 60.0)
	var predicted := BallTrajectoryScript.ground_position_after(initial, velocity, 60.0, velocity.length() / 60.0)
	_expect(predicted.distance_to(target) < 0.01, "ground trajectory reaches target")
	var flight := BallTrajectoryScript.landing_time(0.0, 180.0, 600.0)
	_expect(is_equal_approx(flight, 0.6), "landing time uses shared gravity")
	var short_velocity := BallTrajectoryScript.velocity_for_ground_target(Vector2.ZERO, Vector2(60.0, 0.0), 60.0)
	var long_velocity := BallTrajectoryScript.velocity_for_ground_target(Vector2.ZERO, Vector2(240.0, 0.0), 60.0)
	_expect(long_velocity.length() > short_velocity.length(), "pass speed follows target distance")
	var bounced := BallTrajectoryScript.bounce_velocity(Vector2(10.0, 0.0), Vector2(-1.0, 0.0), 0.8)
	_expect(is_equal_approx(bounced.x, -8.0), "bounce reflects and loses energy")

func _test_ball_interaction_resolver() -> void:
	var intents: Array[Dictionary] = [
		{"eligible": true, "priority": 1, "distance": 4.0, "player_id": 8},
		{"eligible": true, "priority": 2, "distance": 8.0, "player_id": 9},
		{"eligible": false, "priority": 9, "distance": 0.0, "player_id": 1},
	]
	var resolved := BallInteractionResolverScript.resolve(intents)
	_expect(int(resolved.player_id) == 9, "higher priority wins interaction")
	var tie := BallInteractionResolverScript.resolve([
		{"eligible": true, "priority": 1, "distance": 4.0, "player_id": 8},
		{"eligible": true, "priority": 1, "distance": 4.0, "player_id": 3},
	])
	_expect(int(tie.player_id) == 3, "tie breaks by stable player id")

func _test_control_profile() -> void:
	_expect(ControlProfileScript.can_connect(ControlProfileScript.Kind.FOOT, 0.0), "foot controls ground ball")
	_expect(not ControlProfileScript.can_connect(ControlProfileScript.Kind.FOOT, 20.0), "foot rejects high ball")
	_expect(ControlProfileScript.can_connect(ControlProfileScript.Kind.HEAD, 30.0), "head controls aerial ball")
	_expect(ControlProfileScript.can_connect(ControlProfileScript.Kind.GOALKEEPER_HANDS, 20.0), "keeper hands control catchable ball")

func _test_team_tactics() -> void:
	var team: Array[Dictionary] = [
		{"id": 1, "position": Vector2(20.0, 0.0), "spawn_position": Vector2(10.0, 0.0)},
		{"id": 2, "position": Vector2(80.0, 0.0), "spawn_position": Vector2(70.0, 0.0)},
		{"id": 3, "position": Vector2(150.0, 0.0), "spawn_position": Vector2(140.0, 0.0)},
	]
	var opponents: Array[Dictionary] = [
		{"id": 10, "position": Vector2(90.0, 0.0)},
		{"id": 11, "position": Vector2(110.0, 0.0)},
	]
	var snapshot := TeamTacticsScript.build_snapshot(team, opponents, Vector2(50.0, 0.0), 1, 50.0)
	_expect(snapshot.presser_ids == [1], "one active presser is assigned")
	_expect(snapshot.cover_ids == [2], "nearby cover role is assigned")
	_expect(is_equal_approx(snapshot.offside_line_x, 50.0), "offside line respects ball position")
	var clamped := TeamTacticsScript.clamp_support_target(Vector2(100.0, 0.0), snapshot.offside_line_x, 1, 50.0)
	_expect(clamped.x < snapshot.offside_line_x, "support target stays onside")

func _run_legacy_dribble_suite() -> void:
	var suite := DribbleSuiteScript.new()
	var result: Dictionary = suite.run_suite()
	_expect(result.failed == 0, "legacy dribble suite")

func _run_legacy_shooting_suite() -> void:
	var suite := ShootingSuiteScript.new()
	var result: Dictionary = suite.run_suite()
	_expect(result.failed == 0, "legacy shooting suite")


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("PASS [%s] %s" % [_current_suite, label])
	else:
		_failed += 1
		printerr("FAIL [%s] %s" % [_current_suite, label])
