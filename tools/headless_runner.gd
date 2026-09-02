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
const InterceptResolverScript := preload("res://utils/intercept_resolver.gd")
const OffsideJudgeScript := preload("res://utils/offside_judge.gd")
const GoalkeeperInteractionPolicyScript := preload("res://utils/goalkeeper_interaction_policy.gd")
const DribbleTouchControllerScript := preload("res://utils/dribble_touch_controller.gd")

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
	_run_suite("intercept_resolver", _test_intercept_resolver)
	_run_suite("offside_judge", _test_offside_judge)
	_run_suite("goalkeeper_interaction_policy", _test_goalkeeper_interaction_policy)
	_run_suite("dribble_touch_controller", _test_dribble_touch_controller)
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
	for scenario in [
		{"distance": 30.0, "arrival": 0.20},
		{"distance": 120.0, "arrival": 0.55},
		{"distance": 250.0, "arrival": 0.90},
	]:
		var pass_target := Vector2(float(scenario.distance), 0.0)
		var pass_velocity := BallTrajectoryScript.velocity_for_ground_target_at_time(
			Vector2.ZERO, pass_target, 60.0, float(scenario.arrival))
		var arrival_position := BallTrajectoryScript.ground_position_after(
			Vector2.ZERO, pass_velocity, 60.0, float(scenario.arrival))
		_expect(arrival_position.distance_to(pass_target) < 0.01,
			"timed ground pass reaches %d px target" % int(scenario.distance))
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
	var snapshot := MatchSnapshotScript.new()
	snapshot.tick = 18
	var inactive_tackle := BallInteractionResolverScript.create_intent(
		BallInteractionResolverScript.Kind.TACKLE, 8,
		{"distance": 1.0, "active_window": false})
	var collection := BallInteractionResolverScript.create_intent(
		BallInteractionResolverScript.Kind.COLLECT, 4, {"distance": 3.0})
	var event := BallInteractionResolverScript.resolve_and_commit(
		snapshot, [inactive_tackle, collection])
	_expect(int(event.player_id) == 4, "inactive actions cannot win a contest")
	_expect(int(snapshot.ball.carrier_id) == 4, "one resolved capture assigns one carrier")
	_expect(snapshot.events.size() == 1, "one committed interaction emits one event")
	var release_event := BallInteractionResolverScript.resolve_and_commit(snapshot, [
		BallInteractionResolverScript.create_intent(BallInteractionResolverScript.Kind.CONTROL, 4),
		BallInteractionResolverScript.create_intent(BallInteractionResolverScript.Kind.KICK, 4),
	])
	_expect(int(release_event.kind) == BallInteractionResolverScript.Kind.KICK,
		"active kick wins over passive control")
	_expect(int(snapshot.ball.carrier_id) == -1, "kick releases the current carrier")
	var callback_a := BallInteractionResolverScript.create_intent(
		BallInteractionResolverScript.Kind.CONTROL, 12, {"distance": 5.0})
	var callback_b := BallInteractionResolverScript.create_intent(
		BallInteractionResolverScript.Kind.CONTROL, 4, {"distance": 5.0})
	var callback_first := BallInteractionResolverScript.resolve([callback_a, callback_b])
	var callback_reversed := BallInteractionResolverScript.resolve([callback_b, callback_a])
	_expect(callback_first.player_id == callback_reversed.player_id and callback_first.player_id == 4,
		"callback ordering cannot change free-ball winner")
	var transition_sim := MatchSimulationScript.new(9, snapshot)
	transition_sim.queue_state_transition(7, "PREPPING_SHOT", "SHOOTING", {"power": 1.0})
	transition_sim.queue_state_transition(7, "SHOOTING", "RECOVERING")
	transition_sim.queue_state_transition(2, "FREEFORM", "SAVED")
	transition_sim.queue_state_transition(3, "FREEFORM", "DRIBBLING")
	var transitioned := transition_sim.advance()
	var transitions: Array = transitioned.events.filter(func(item: Dictionary) -> bool:
		return item.get("type") == "state_transition")
	_expect(transitions.size() == 3, "same-tick transitions commit once per owner")
	_expect(int(transitions[0].owner_id) == 2 and int(transitions[1].owner_id) == 3,
		"transition commits use stable owner ordering")
	_expect(int(transitions[2].owner_id) == 7 and transitions[2].to == "RECOVERING",
		"latest transition for an owner is committed at tick end")

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
	var defensive_assignments := TeamTacticsScript.build_defensive_assignments(
		team, Vector2(50.0, 20.0), Vector2(0.0, 0.0))
	_expect(defensive_assignments[1].role == "PRESS", "only nearest defender presses")
	_expect(defensive_assignments[2].role == "COVER", "next defender provides goal-side cover")
	_expect(defensive_assignments[3].role == "HOLD", "remaining defender retains shape")
	_expect((defensive_assignments[2].target as Vector2).x < 50.0,
		"cover target stays goal-side of the ball")
	var attacking_team: Array[Dictionary] = [
		{"id": 1, "position": Vector2(20.0, -70.0), "spawn_position": Vector2(20.0, -70.0)},
		{"id": 2, "position": Vector2(80.0, 0.0), "spawn_position": Vector2(80.0, 0.0)},
		{"id": 3, "position": Vector2(120.0, 70.0), "spawn_position": Vector2(120.0, 70.0)},
		{"id": 4, "position": Vector2(150.0, 0.0), "spawn_position": Vector2(150.0, 0.0)},
	]
	var support_assignments := TeamTacticsScript.build_attacking_assignments(
		attacking_team, Vector2(80.0, 0.0), 1, 2)
	_expect(support_assignments[1].role == "SAFETY", "attack retains a safety outlet")
	_expect(support_assignments[3].role == "WIDE", "attack retains a wide outlet")
	_expect(support_assignments[4].role == "CENTRAL", "attack retains a central outlet")

func _test_intercept_resolver() -> void:
	var defender := {
		"position": Vector2(8.0, 0.0),
		"velocity": Vector2(100.0, 0.0),
		"defense": 90.0,
	}
	var dribbler := {
		"position": Vector2.ZERO,
		"technique": 40.0,
	}
	var distant_defender := {
		"position": Vector2(40.0, 0.0),
		"velocity": Vector2.ZERO,
		"defense": 90.0,
	}
	var probability := InterceptResolverScript.compute_intercept_probability(
		defender, dribbler, Vector2.ZERO, Vector2.RIGHT * 80.0)
	_expect(probability > 0.0, "eligible defender has a positive intercept chance")
	_expect(is_zero_approx(InterceptResolverScript.compute_intercept_probability(
		distant_defender, dribbler, Vector2.ZERO, Vector2.RIGHT * 80.0
	)), "distant defender is ineligible")
	var winner := InterceptResolverScript.find_best_interceptor_probability(
		[distant_defender, defender], dribbler, Vector2.ZERO, Vector2.RIGHT * 80.0)
	_expect(winner.player == defender, "highest probability interceptor wins")

func _test_offside_judge() -> void:
	var passer := {"global_position": Vector2(40.0, 0.0), "role": 2}
	var onside_attacker := {"global_position": Vector2(56.0, 0.0), "role": 3}
	var offside_attacker := {"global_position": Vector2(72.0, 0.0), "role": 3}
	var defenders := [
		{"global_position": Vector2(58.0, 0.0), "role": 1},
		{"global_position": Vector2(64.0, 0.0), "role": 1},
	]
	var result := OffsideJudgeScript.check_offside_at_pass(
		passer, [onside_attacker, offside_attacker], defenders, Vector2(40.0, 0.0), 1)
	_expect(result.is_offside, "forward beyond second-last defender is offside")
	_expect(result.offender == offside_attacker, "furthest offending attacker is selected")
	_expect(not OffsideJudgeScript.is_target_offside(
		Vector2(-10.0, 0.0), defenders, Vector2(40.0, 0.0), 1
	), "attacker in own half is never offside")

func _test_goalkeeper_interaction_policy() -> void:
	var catch_data := {
		"in_penalty_area": true,
		"release_locked": false,
		"teammate_carrier": false,
		"height": 12.0,
		"speed": 100.0,
		"distance": 10.0,
	}
	var catch_intent := GoalkeeperInteractionPolicyScript.resolve(1, catch_data)
	_expect(int(catch_intent.kind) == BallInteractionResolverScript.Kind.COLLECT,
		"valid low-speed ball is catchable")
	var parry_data := catch_data.duplicate(true)
	parry_data.speed = 260.0
	var parry_intent := GoalkeeperInteractionPolicyScript.resolve(1, parry_data)
	_expect(int(parry_intent.kind) == BallInteractionResolverScript.Kind.DEFLECT,
		"fast shot is parried instead of collected")
	var outside_data := catch_data.duplicate(true)
	outside_data.in_penalty_area = false
	_expect(GoalkeeperInteractionPolicyScript.resolve(1, outside_data).is_empty(),
		"keeper cannot collect outside the penalty area")
	var locked_data := catch_data.duplicate(true)
	locked_data.release_locked = true
	_expect(GoalkeeperInteractionPolicyScript.resolve(1, locked_data).is_empty(),
		"release lock blocks immediate recollection")
	var opponent_pass := catch_data.duplicate(true)
	opponent_pass.teammate_carrier = false
	_expect(int(GoalkeeperInteractionPolicyScript.resolve(1, opponent_pass).kind)
		== BallInteractionResolverScript.Kind.COLLECT,
		"opponent pass remains legally collectible")

func _test_dribble_touch_controller() -> void:
	var straight := _touch_sequence(Vector2.RIGHT, DribblePhysics.Mode.JOG, true)
	_expect(not straight.is_empty(), "straight dribble emits touch impulses")
	var straight_velocity: Vector2 = straight[0].velocity
	_expect(straight_velocity.dot(Vector2.RIGHT) > 0.0,
		"straight touch impulse follows movement direction")
	var stopped := _touch_sequence(Vector2.RIGHT, DribblePhysics.Mode.JOG, false)
	_expect(stopped.is_empty(), "stopping emits no magnetic touch correction")
	var turn_90 := _touch_sequence(Vector2.DOWN, DribblePhysics.Mode.JOG, true)
	var turn_90_velocity: Vector2 = turn_90[0].velocity if not turn_90.is_empty() else Vector2.ZERO
	_expect(not turn_90.is_empty() and turn_90_velocity.dot(Vector2.DOWN) > 0.0,
		"90-degree turn waits for an impulse in the new direction")
	var turn_180 := _touch_sequence(Vector2.LEFT, DribblePhysics.Mode.JOG, true)
	var turn_180_velocity: Vector2 = turn_180[0].velocity if not turn_180.is_empty() else Vector2.ZERO
	_expect(not turn_180.is_empty() and turn_180_velocity.dot(Vector2.LEFT) > 0.0,
		"180-degree turn waits for an impulse in the new direction")
	var sprint := _touch_sequence(Vector2.RIGHT, DribblePhysics.Mode.SPRINT, true)
	_expect(sprint.size() < straight.size(), "sprint uses a longer touch interval")
	_expect(straight == _touch_sequence(Vector2.RIGHT, DribblePhysics.Mode.JOG, true),
		"same seed produces the same touch sequence")

func _touch_sequence(direction: Vector2, mode: int, movement_intended: bool) -> Array[Dictionary]:
	var controller := DribbleTouchControllerScript.new(90210)
	var player_velocity := direction * 90.0
	var ball_position := direction * 6.0
	for ignored in range(30):
		controller.advance(1.0 / 60.0, ball_position, Vector2.ZERO, direction,
			Vector2.ZERO, player_velocity, 100.0, 70.0, mode, movement_intended)
	return controller.events.duplicate(true)

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
