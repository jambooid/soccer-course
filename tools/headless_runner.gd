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
const GoalkeeperDecisionPolicyScript := preload("res://utils/goalkeeper_decision_policy.gd")
const PlayerSwitchSelectorScript := preload("res://utils/player_switch_selector.gd")
const DribbleTurnReplayScript := preload("res://utils/dribble_turn_replay.gd")
const ActionPhaseTimelineScript := preload("res://utils/action_phase_timeline.gd")
const TackleEligibilityPolicyScript := preload("res://utils/tackle_eligibility_policy.gd")
const MatchFlowAdapterScript := preload("res://utils/match_flow_adapter.gd")
const CpuMatchDiagnosticScript := preload("res://utils/cpu_match_diagnostic.gd")
const DribbleTouchControllerScript := preload("res://utils/dribble_touch_controller.gd")
const CpuActionSelectorScript := preload("res://utils/cpu_action_selector.gd")

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
	_run_suite("goalkeeper_decision_policy", _test_goalkeeper_decision_policy)
	_run_suite("player_switch_selector", _test_player_switch_selector)
	_run_suite("dribble_turn_replay", _test_dribble_turn_replay)
	_run_suite("action_phase_timeline", _test_action_phase_timeline)
	_run_suite("tackle_eligibility_policy", _test_tackle_eligibility_policy)
	_run_suite("match_flow_adapter", _test_match_flow_adapter)
	_run_suite("cpu_match_diagnostic", _test_cpu_match_diagnostic)
	_run_suite("dribble_touch_controller", _test_dribble_touch_controller)
	_run_suite("cpu_action_selector", _test_cpu_action_selector)
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
	var clamped_wide := TeamTacticsScript.clamp_support_target(
		support_assignments[3].target, 95.0, 1, 50.0)
	_expect(clamped_wide.x < 95.0, "forward support target is constrained by offside line")
	_expect(TeamTacticsScript.arrival_intent(
		Vector2.ZERO, Vector2(5.0, 0.0), 8.0, 55.0) == Vector2.ZERO,
		"player settles inside tactical target stop radius")
	var slowing_intent: Vector2 = TeamTacticsScript.arrival_intent(
		Vector2.ZERO, Vector2(30.0, 0.0), 8.0, 55.0)
	_expect(slowing_intent.length() > 0.0 and slowing_intent.length() < 1.0,
		"player slows while approaching tactical target")
	_expect(is_equal_approx(TeamTacticsScript.arrival_intent(
		Vector2.ZERO, Vector2(100.0, 0.0), 8.0, 55.0).length(), 1.0),
		"distant tactical target requests full movement speed")

	var full_team: Array[Dictionary] = [
		{"id": 2, "position": Vector2(165.0, 110.0), "spawn_position": Vector2(165.0, 110.0)},
		{"id": 3, "position": Vector2(185.0, 155.0), "spawn_position": Vector2(185.0, 155.0)},
		{"id": 4, "position": Vector2(185.0, 205.0), "spawn_position": Vector2(185.0, 205.0)},
		{"id": 5, "position": Vector2(165.0, 250.0), "spawn_position": Vector2(165.0, 250.0)},
		{"id": 6, "position": Vector2(275.0, 135.0), "spawn_position": Vector2(275.0, 135.0)},
		{"id": 8, "position": Vector2(285.0, 180.0), "spawn_position": Vector2(285.0, 180.0)},
		{"id": 10, "position": Vector2(275.0, 225.0), "spawn_position": Vector2(275.0, 225.0)},
		{"id": 7, "position": Vector2(375.0, 105.0), "spawn_position": Vector2(375.0, 105.0)},
		{"id": 9, "position": Vector2(395.0, 180.0), "spawn_position": Vector2(395.0, 180.0)},
		{"id": 11, "position": Vector2(375.0, 255.0), "spawn_position": Vector2(375.0, 255.0)},
	]
	var full_assignments := TeamTacticsScript.build_attacking_assignments(
		full_team, Vector2(470.0, 120.0), 1, 10)
	_expect(full_assignments.size() == 9, "11v11 attack assigns every off-ball outfielder")
	var safety_count := 0
	var distinct_targets := {}
	for assignment: Dictionary in full_assignments.values():
		if assignment.role == "SAFETY":
			safety_count += 1
		var target: Vector2 = assignment.target
		distinct_targets[Vector2i(roundi(target.x), roundi(target.y))] = true
	_expect(safety_count == 1, "11v11 attack retains exactly one safety outlet")
	_expect(distinct_targets.size() == full_assignments.size(),
		"11v11 off-ball players receive distinct formation targets")
	_expect((full_assignments[7].target as Vector2).y < (full_assignments[9].target as Vector2).y \
		and (full_assignments[9].target as Vector2).y < (full_assignments[11].target as Vector2).y,
		"11v11 forward line preserves left, central, and right lanes")
	var rear_target_x: float = (full_assignments[3].target as Vector2).x
	var forward_target_x: float = (full_assignments[9].target as Vector2).x
	_expect(forward_target_x - rear_target_x > 120.0,
		"11v11 support targets preserve defensive-to-forward depth")

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

func _test_goalkeeper_decision_policy() -> void:
	var base := {
		"keeper_position": Vector2(15.0, 0.0), "keeper_speed": 50.0,
		"goal_position": Vector2.ZERO, "goal_top": -20.0, "goal_bottom": 20.0,
		"ball_position": Vector2(30.0, 4.0), "ball_velocity": Vector2(-200.0, 0.0),
		"ball_height": 4.0, "height_velocity": 0.0, "friction": 60.0, "gravity": 600.0,
		"dive_range": 60.0, "save_height_max": 58.0, "inside_rush_zone": true,
	}
	var dive := GoalkeeperDecisionPolicyScript.decide(base)
	_expect(int(dive.kind) == GoalkeeperDecisionPolicyScript.Kind.DIVE,
		"fast goal-bound shot selects a trajectory-led dive")
	var set_data := base.duplicate(true)
	set_data.keeper_position = Vector2(5.0, 0.0)
	var set := GoalkeeperDecisionPolicyScript.decide(set_data)
	_expect(int(set.kind) == GoalkeeperDecisionPolicyScript.Kind.SET,
		"reachable goal-bound shot selects a set position")
	var claim_data := base.duplicate(true)
	claim_data.can_collect_now = true
	var claim := GoalkeeperDecisionPolicyScript.decide(claim_data)
	_expect(int(claim.kind) == GoalkeeperDecisionPolicyScript.Kind.CLAIM,
		"legal current collection beats a dive decision")
	var rush_data := base.duplicate(true)
	rush_data.erase("can_collect_now")
	rush_data.ball_position = Vector2(40.0, 0.0)
	rush_data.ball_velocity = Vector2.ZERO
	rush_data.ball_height = 20.0
	rush_data.keeper_position = Vector2(10.0, 0.0)
	rush_data.keeper_speed = 200.0
	var rush := GoalkeeperDecisionPolicyScript.decide(rush_data)
	_expect(int(rush.kind) == GoalkeeperDecisionPolicyScript.Kind.RUSH,
		"reachable loose-ball landing selects a rush")
	var safe_option := {"player_id": 2, "rule_legal": true, "receiver_eta": 0.0,
		"ball_eta": 0.7, "opponent_eta": 1.1, "utility": 0.6}
	var blocked_option := {"player_id": 1, "rule_legal": true, "receiver_eta": 0.0,
		"ball_eta": 0.7, "opponent_eta": 0.4, "utility": 0.9}
	var distribution := GoalkeeperDecisionPolicyScript.select_distribution([blocked_option, safe_option])
	_expect(int(distribution.player_id) == 2, "distribution rejects an opponent-reachable lane")
	var line_data := base.duplicate(true)
	line_data.inside_rush_zone = false
	line_data.ball_velocity = Vector2(0.0, 80.0)
	var line := GoalkeeperDecisionPolicyScript.decide(line_data)
	_expect(int(line.kind) == GoalkeeperDecisionPolicyScript.Kind.LINE,
		"non-threatening trajectory keeps the keeper on the line")
	var held := GoalkeeperDecisionPolicyScript.decide({"holding_ball": true, "held_seconds": 1.6,
		"distribution_delay": 1.5, "distribution_long": true})
	_expect(int(held.kind) == GoalkeeperDecisionPolicyScript.Kind.DISTRIBUTE_KICK,
		"held ball releases through deterministic long distribution")

func _test_player_switch_selector() -> void:
	var candidates: Array[Dictionary] = [
		{"id": 1, "position": Vector2(20.0, 0.0), "speed": 60.0, "tactical_role": "PRESS"},
		{"id": 2, "position": Vector2(10.0, 30.0), "speed": 70.0},
		{"id": 3, "position": Vector2(2.0, 0.0), "speed": 80.0, "goalkeeper": true},
	]
	var loose_ball := PlayerSwitchSelectorScript.select(candidates, Vector2.ZERO, Vector2.LEFT)
	_expect(int(loose_ball.id) == 1, "defensive switch favors reachable presser in input direction")
	candidates[1].has_ball = true
	var possession := PlayerSwitchSelectorScript.select(candidates, Vector2.ZERO)
	_expect(int(possession.id) == 2, "possession switch favors the new carrier")
	_expect(possession == PlayerSwitchSelectorScript.select(candidates, Vector2.ZERO),
		"same loose-ball snapshot has a stable switch target")

func _test_dribble_turn_replay() -> void:
	var inputs: Array[Vector2] = []
	for ignored in range(8):
		inputs.append(Vector2.RIGHT)
	for ignored in range(8):
		inputs.append(Vector2.UP)
	for ignored in range(8):
		inputs.append(Vector2.LEFT)
	var replay := DribbleTurnReplayScript.run(4269, inputs, Vector2.RIGHT * 260.0, 12.0)
	var repeated := DribbleTurnReplayScript.run(4269, inputs, Vector2.RIGHT * 260.0, 12.0)
	_expect(replay.touches == repeated.touches, "turn replay retains identical touch events")
	_expect(int(replay.loss_tick) == int(repeated.loss_tick) and int(replay.loss_tick) > 0,
		"turn replay retains the same loss-of-control tick")

func _test_action_phase_timeline() -> void:
	for action in ["PASS", "SHOT", "TACKLE", "AERIAL", "GOALKEEPER"]:
		var timeline := ActionPhaseTimelineScript.profile(action)
		_expect(not timeline.can_contact(), "%s cannot contact during startup" % action)
		timeline.advance(timeline.startup + 0.001)
		_expect(timeline.can_contact(), "%s contacts only during active phase" % action)
		timeline.advance(timeline.active + 0.001)
		_expect(not timeline.can_contact(), "%s cannot contact during recovery" % action)

func _test_tackle_eligibility_policy() -> void:
	var standing := {"distance": 8.0, "ball_first": true, "direction_dot": 0.9,
		"approach_speed": 25.0, "defense": 75.0, "technique": 60.0}
	_expect(int(TackleEligibilityPolicyScript.resolve(standing).outcome) == TackleEligibilityPolicyScript.Outcome.INTERCEPT,
		"front standing challenge intercepts")
	var slide := standing.duplicate(true)
	slide.sliding = true
	slide.approach_speed = 80.0
	_expect(int(TackleEligibilityPolicyScript.resolve(slide).outcome) == TackleEligibilityPolicyScript.Outcome.TACKLE_WIN,
		"fast forward slide wins ball first")
	var behind := slide.duplicate(true)
	behind.direction_dot = -0.5
	_expect(int(TackleEligibilityPolicyScript.resolve(behind).outcome) == TackleEligibilityPolicyScript.Outcome.MISS,
		"backward slide misses")
	var slow := slide.duplicate(true)
	slow.approach_speed = 20.0
	_expect(int(TackleEligibilityPolicyScript.resolve(slow).outcome) == TackleEligibilityPolicyScript.Outcome.MISS,
		"slow slide misses")
	var body_first := standing.duplicate(true)
	body_first.ball_first = false
	_expect(int(TackleEligibilityPolicyScript.resolve(body_first).outcome) == TackleEligibilityPolicyScript.Outcome.MISS,
		"body-first challenge cannot win ball")

func _test_match_flow_adapter() -> void:
	var snapshot := MatchSnapshotScript.new()
	var events := MatchFlowAdapterScript.playable_flow(snapshot)
	_expect(events.size() == 6, "kickoff pass shot save tackle flow is bounded")
	_expect(int(snapshot.ball.carrier_id) == 4, "tackle is the only final carrier")
	var unique_events := {}
	for event in events:
		unique_events["%s:%s" % [event.kind, event.player_id]] = true
	_expect(unique_events.size() == events.size(), "flow emits no duplicate possession event")

func _test_cpu_match_diagnostic() -> void:
	var first := CpuMatchDiagnosticScript.run(7788, 1200)
	var repeated := CpuMatchDiagnosticScript.run(7788, 1200)
	_expect(first == repeated, "long CPU diagnostic metrics replay identically")
	_expect(float(first.formation_spread) > 0.0, "diagnostic reports formation spread")

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

func _test_cpu_action_selector() -> void:
	var safe_pass := {"kind": "PASS", "eligible": true, "reachable": true, "rule_legal": true,
		"eta": 0.5, "utility": CpuActionSelectorScript.pass_utility(0.9, 0.5, 0.1, 80.0)}
	var blocked_pass := {"kind": "PASS", "eligible": true, "reachable": true, "rule_legal": false,
		"eta": 0.3, "utility": 1.0}
	var retain := {"kind": "RETAIN", "eligible": true, "reachable": true, "rule_legal": true,
		"eta": 0.0, "utility": 0.3}
	var selected := CpuActionSelectorScript.select([blocked_pass, retain, safe_pass])
	_expect(selected.kind == "PASS" and selected.rule_legal, "safe reachable pass beats retain and illegal lane")
	_expect(selected == CpuActionSelectorScript.select([retain, safe_pass, blocked_pass]),
		"same action snapshot selects deterministically")

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
