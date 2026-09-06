extends SceneTree

const Rules := preload("res://utils/match3d_rules.gd")
const FeelRules := preload("res://utils/match_feel_rules.gd")
const Pitch3D := preload("res://scenes/world3d/pitch_3d.gd")
const BallTrajectory3DScript := preload("res://utils/ball_trajectory_3d.gd")

var passed := 0
var failed := 0

func _init() -> void:
	var result := run_suite()
	quit(0 if result.failed == 0 else 1)

func run_suite() -> Dictionary:
	passed = 0
	failed = 0
	print("=== 3D Match Rules Tests ===")
	_test_player_motion_is_bounded()
	_test_player_turn_is_arc_based()
	_test_directional_pass_prefers_forward_teammate()
	_test_safe_pass_avoids_intercepted_lane()
	_test_pass_speed_and_shot_speed_are_distinct()
	_test_goal_detection()
	_test_3d_goal_height()
	_test_trajectory_events_and_pitch_bounds()
	_test_camera_target()
	_test_nearest_player_filtering()
	_test_switch_target()
	_test_player_separation()
	_test_visible_goal_matches_scoring_mouth()
	_test_visible_goal_front_frames_are_on_goal_lines()
	_test_goal_depth_extends_outside_pitch()
	_test_action_intent_contact_windows()
	_test_arrival_race_and_receive_area()
	_test_first_touch_and_metric_records()
	_test_goalkeeper_outcome_table()
	print("Results: %d passed, %d failed" % [passed, failed])
	return {"passed": passed, "failed": failed}

func _expect(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("  [PASS] %s" % label)
	else:
		failed += 1
		print("  [FAIL] %s" % label)

func _test_player_motion_is_bounded() -> void:
	var moved := Rules.advance_player(Vector3(84.4, 0.0, 0.5), Vector3.ZERO, Vector3(1.0, 0.0, -1.0), 1.0, 12.0)
	var position: Vector3 = moved.position
	var velocity: Vector3 = moved.velocity
	_expect(position.x <= Rules.PITCH_SIZE.x - Rules.PLAYER_RADIUS + 0.001 and position.z >= Rules.PLAYER_RADIUS - 0.001,
		"player motion stays inside the playable pitch")
	_expect(velocity.length() <= 12.0,
		"player acceleration respects top speed")

func _test_player_turn_is_arc_based() -> void:
	var first := Rules.advance_player(Vector3.ZERO, Vector3(8.8, 0.0, 0.0), Vector3(0.0, 0.0, 1.0),
		1.0 / 60.0, 8.8)
	var turned: Vector3 = first.velocity
	_expect(turned.x > 0.0 and turned.z > 0.0,
		"high-speed direction changes bend through an arc instead of snapping")

func _test_directional_pass_prefers_forward_teammate() -> void:
	var players := [
		{"id": 1, "home": true, "position": Vector3(30.0, 0.0, 18.0)},
		{"id": 2, "home": true, "position": Vector3(47.0, 0.0, 18.0)},
		{"id": 3, "home": true, "position": Vector3(28.0, 0.0, 7.0)},
		{"id": 4, "home": false, "position": Vector3(44.0, 0.0, 18.0)},
	]
	var target := Rules.select_pass_target(players, 1, true, Vector3.RIGHT, Vector3(30.0, 0.0, 18.0))
	_expect(int(target.id) == 2, "rightward pass selects the forward teammate")
	var reverse := Rules.select_pass_target(players, 1, true, Vector3.FORWARD, Vector3(30.0, 0.0, 18.0))
	_expect(int(reverse.id) == 3, "vertical input selects the vertical outlet")

func _test_safe_pass_avoids_intercepted_lane() -> void:
	var players := [
		{"id": 1, "home": true, "position": Vector3(30.0, 0.0, 18.0)},
		{"id": 2, "home": true, "position": Vector3(46.0, 0.0, 18.0)},
		{"id": 3, "home": true, "position": Vector3(41.0, 0.0, 28.0)},
		{"id": 4, "home": false, "position": Vector3(38.0, 0.0, 18.2)},
	]
	var target := Rules.select_safe_pass_target(players, 1, true, Vector3(30.0, 0.0, 18.0))
	_expect(int(target.id) == 3,
		"safe pass selection rejects the forward lane occupied by an interceptor")

func _test_pass_speed_and_shot_speed_are_distinct() -> void:
	var short_kick := Rules.pass_velocity(Vector3.ZERO, Vector3(10.0, 0.0, 0.0))
	var long_pass := Rules.pass_velocity(Vector3.ZERO, Vector3(10.0, 0.0, 0.0), true)
	var shot := Rules.shot_velocity(Vector3(35.0, 0.0, 18.0), true)
	_expect(is_equal_approx(short_kick.length(), Rules.PASS_SPEED), "short pass has a stable launch speed")
	_expect(long_pass.length() > short_kick.length() and shot.length() > long_pass.length(),
		"long pass and shot have readable speed tiers")

func _test_goal_detection() -> void:
	_expect(Rules.goal_scoring_team(Vector3(-0.1, 0.2, 18.0)) == -1, "left goal awards the away team")
	_expect(Rules.goal_scoring_team(Vector3(85.1, 0.2, 18.0)) == 1, "right goal awards the home team")
	_expect(Rules.goal_scoring_team(Vector3(-0.1, 0.2, 1.0)) == 0, "ball outside goal mouth is not a goal")

func _test_3d_goal_height() -> void:
	_expect(Rules.goal_scoring_team(Vector3(-0.1, 1.2, 18.0)) == -1,
		"low ball crossing the goal line scores in 3D")
	_expect(Rules.goal_scoring_team(Vector3(-0.1, Rules.GOAL_HEIGHT + 0.1, 18.0)) == 0,
		"ball above the crossbar does not score")

func _test_trajectory_events_and_pitch_bounds() -> void:
	var impact := BallTrajectory3DScript.step(Vector3(2.0, 0.1, 2.0), Vector3(0.0, -4.0, 0.0),
		0.1, 22.0, 14.0, 4.0, 0.5)
	_expect(bool(impact.ground_contact) and float(impact.impact_speed) > 0.0,
		"3D trajectory reports ground contact and impact speed")
	var wall := BallTrajectory3DScript.step_on_pitch(Vector3(1.0, 0.0, 0.2), Vector3(0.0, 0.0, -8.0),
		0.1, 22.0, 14.0, 4.0, 0.0, Rules.PITCH_SIZE, Rules.GOAL_HALF_WIDTH,
		Rules.GOAL_HEIGHT, 0.62)
	_expect(bool(wall.boundary_hit) and wall.boundary_axis == "z" and wall.position.z >= 0.0,
		"pitch boundary reflects and reports the touched axis")
	var goal := BallTrajectory3DScript.step_on_pitch(Vector3(0.1, 1.0, 18.0), Vector3(-8.0, 0.0, 0.0),
		0.1, 22.0, 14.0, 4.0, 0.0, Rules.PITCH_SIZE, Rules.GOAL_HALF_WIDTH,
		Rules.GOAL_HEIGHT, 0.62)
	_expect(bool(goal.goal_crossed) and not bool(goal.boundary_hit),
		"low ball can cross the open goal mouth without reflecting")

func _test_nearest_player_filtering() -> void:
	var players := [
		{"id": 1, "home": true, "position": Vector3(10.0, 0.0, 10.0)},
		{"id": 2, "home": false, "position": Vector3(11.0, 0.0, 10.0)},
		{"id": 3, "home": true, "position": Vector3(14.0, 0.0, 10.0)},
	]
	_expect(Rules.nearest_player_id(players, Vector3(11.1, 0.0, 10.0)) == 2, "nearest player wins free-ball selection")
	_expect(Rules.nearest_player_id(players, Vector3(11.1, 0.0, 10.0), 1) == 1, "home filter selects nearest home player")

func _test_camera_target() -> void:
	var left := Rules.camera_target(Vector3(-20.0, 5.0, -4.0))
	var right := Rules.camera_target(Vector3(100.0, 5.0, 45.0))
	_expect(left == Vector3(Rules.CAMERA_TARGET_X_MIN, 0.0, Rules.CAMERA_TARGET_Z_MIN),
		"camera clamps safely at the left/top pitch bounds")
	_expect(right == Vector3(Rules.CAMERA_TARGET_X_MAX, 0.0, Rules.CAMERA_TARGET_Z_MAX),
		"camera clamps safely at the right/bottom pitch bounds")

func _test_player_separation() -> void:
	var resolved := Rules.resolve_pair_separation(Vector3.ZERO, Vector3.ZERO)
	var first: Vector3 = resolved.first
	var second: Vector3 = resolved.second
	_expect(first.distance_to(second) >= Rules.PLAYER_RADIUS * 2.0 - 0.001,
		"overlapping players separate to their footprint distance")

func _test_switch_target() -> void:
	var players := [
		{"id": 1, "home": true, "position": Vector3(10.0, 0.0, 18.0)},
		{"id": 2, "home": true, "position": Vector3(18.0, 0.0, 18.0)},
		{"id": 3, "home": true, "position": Vector3(10.0, 0.0, 8.0)},
		{"id": 4, "home": false, "position": Vector3(12.0, 0.0, 18.0)},
	]
	_expect(Rules.select_switch_target(players, 1, Vector3.RIGHT, Vector3(12.0, 0.0, 18.0)) == 2,
		"directional switch selects a teammate in the requested lane")

func _test_visible_goal_matches_scoring_mouth() -> void:
	_expect(is_equal_approx(Pitch3D.GOAL_WIDTH, 10.4),
		"visible 3D goal uses the intended 10.4 metre mouth width")
	_expect(is_equal_approx(Pitch3D.GOAL_WIDTH, Rules.GOAL_HALF_WIDTH * 2.0),
		"visible 3D goal width matches the scoring mouth width")

func _test_visible_goal_front_frames_are_on_goal_lines() -> void:
	var pitch := Pitch3D.new()
	pitch._add_goals()
	var has_left_front_frame := false
	var has_right_front_frame := false
	for child in pitch.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null:
			continue
		var box := mesh_instance.mesh as BoxMesh
		if box == null or not is_equal_approx(box.size.y, 0.18) or not is_equal_approx(box.size.z, Pitch3D.GOAL_WIDTH):
			continue
		if is_zero_approx(mesh_instance.position.x):
			has_left_front_frame = true
		if is_equal_approx(mesh_instance.position.x, Rules.PITCH_SIZE.x):
			has_right_front_frame = true
	pitch.free()
	_expect(has_left_front_frame and has_right_front_frame,
		"visible goal front frames sit on both scoring goal lines")

func _test_goal_depth_extends_outside_pitch() -> void:
	var pitch := Pitch3D.new()
	pitch._add_goals()
	var has_left_rear_frame := false
	var has_right_rear_frame := false
	for child in pitch.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null:
			continue
		var box := mesh_instance.mesh as BoxMesh
		if box == null or not is_equal_approx(box.size.y, 0.18) or not is_equal_approx(box.size.z, Pitch3D.GOAL_WIDTH):
			continue
		if is_equal_approx(mesh_instance.position.x, -Pitch3D.GOAL_DEPTH):
			has_left_rear_frame = true
		if is_equal_approx(mesh_instance.position.x, Rules.PITCH_SIZE.x + Pitch3D.GOAL_DEPTH):
			has_right_rear_frame = true
	pitch.free()
	_expect(has_left_rear_frame and has_right_rear_frame,
		"goal nets and rear frames extend outside the playable pitch")

func _test_action_intent_contact_windows() -> void:
	var intent := FeelRules.make_action_intent("pass", Vector3(0.6, 0.0, -0.8), 120, 6)
	var window := FeelRules.contact_window("pass", 123, 123)
	var held := FeelRules.consume_intent_at_window(intent, 122, window)
	var consumed := FeelRules.consume_intent_at_window(intent, 123, window)
	var expired := FeelRules.consume_intent_at_window(intent, 127, window)
	var stored_direction: Array = consumed.intent.direction
	_expect(not bool(held.consumed) and bool(consumed.consumed) and
		is_equal_approx(float(stored_direction[0]), 0.6) and
		is_equal_approx(float(stored_direction[2]), -0.8),
		"single-slot intent retains its sampled direction until the first compatible contact")
	_expect(bool(expired.expired) and (expired.intent as Dictionary).is_empty(),
		"expired buffered input has no later effect")

func _test_arrival_race_and_receive_area() -> void:
	var receiver := {"id": 8, "home": true, "position": Vector3(12.0, 0.0, 18.0),
		"velocity": Vector3.RIGHT * 5.0, "arrival_speed": 8.0}
	var target := FeelRules.predict_receive_area(receiver.position, receiver.velocity,
		Vector3(8.0, 0.0, 18.0), Vector3.RIGHT * 20.0)
	var late_interceptor := {"id": 20, "home": false, "position": Vector3(18.0, 0.0, 18.0), "arrival_speed": 8.0}
	var early_interceptor := {"id": 21, "home": false, "position": Vector3(14.0, 0.0, 18.0), "arrival_speed": 12.0}
	var receiver_wins := FeelRules.resolve_arrival_race(receiver, [late_interceptor], target, 2, 2)
	var interceptor_wins := FeelRules.resolve_arrival_race(
		{"id": 8, "home": true, "position": Vector3(12.0, 0.0, 18.0), "arrival_speed": 8.0},
		[{"id": 21, "home": false, "position": Vector3(19.4, 0.0, 18.0), "arrival_speed": 12.0}],
		Vector3(20.0, 0.0, 18.0), 2, 2)
	var tied := FeelRules.resolve_arrival_race({"id": 9, "home": true, "position": Vector3.ZERO,
		"arrival_speed": 8.0}, [{"id": 3, "home": false, "position": Vector3.ZERO,
		"arrival_speed": 8.0}], Vector3(10.0, 0.0, 0.0), 0, 0)
	_expect(target.x > receiver.position.x and int(receiver_wins.winner_id) == 8,
		"predicted receiving area leads a moving closer receiver")
	_expect(interceptor_wins.outcome == "interception" and int(interceptor_wins.winner_id) == 21,
		"a clearly earlier interceptor wins the directed-pass arrival race")
	_expect(bool(tied.tie) and int((tied.candidates as Array)[0].id) == 3 and
		int(tied.winner_id) == 9,
		"equal arrivals retain stable candidate ordering while the receiver keeps an unassisted tie")

func _test_first_touch_and_metric_records() -> void:
	var receiver := {"id": 8, "facing": Vector3.RIGHT, "technique": 70.0}
	var trap := FeelRules.first_touch_state(receiver, Vector3(20.0, 0.0, 18.0), Vector3.RIGHT * 2.0, 0.0, 40)
	var settle := FeelRules.first_touch_state(receiver, Vector3(20.0, 0.0, 18.0), Vector3.RIGHT * 18.0, 0.0, 40)
	var pressured := FeelRules.first_touch_state(receiver, Vector3(20.0, 0.0, 18.0), Vector3.RIGHT * 8.0, 0.9, 40)
	var metric := FeelRules.calibration_metric(44, "receive", 4, 8, Vector3.RIGHT,
		FeelRules.contact_window("receive", 43, 45), 52, 54, "settle", {"first_touch": settle})
	var encoded := JSON.stringify(metric)
	_expect(trap.outcome == "trap" and settle.outcome == "settle" and
		pressured.outcome == "contested_loose" and int(settle.duration_ticks) > int(trap.duration_ticks),
		"low-speed, high-speed, and pressured receptions create distinct bounded first-touch outcomes")
	_expect(not encoded.is_empty() and int(metric.arrival_delta) == 2 and
		(metric.direction as Array) == [1.0, 0.0, 0.0],
		"calibration metrics are serializable records with arrival and direction data")

func _test_goalkeeper_outcome_table() -> void:
	var keeper := {"position": Vector3(84.0, 0.0, 18.0), "keeper_recovery_ticks": 0}
	var collect := FeelRules.goalkeeper_outcome(keeper, Vector3(80.0, 0.4, 18.3), Vector3.RIGHT * 20.0,
		Rules.PITCH_SIZE.x)
	var late := FeelRules.goalkeeper_outcome(keeper, Vector3(84.2, 0.4, 18.0), Vector3.RIGHT * 30.0,
		Rules.PITCH_SIZE.x)
	var gap := FeelRules.goalkeeper_outcome(keeper, Vector3(80.0, 0.4, 22.1), Vector3.RIGHT * 20.0,
		Rules.PITCH_SIZE.x)
	var parry := FeelRules.goalkeeper_outcome(keeper, Vector3(80.0, 0.4, 20.0), Vector3.RIGHT * 20.0,
		Rules.PITCH_SIZE.x)
	var dive := FeelRules.goalkeeper_outcome(keeper, Vector3(80.0, 1.8, 20.0), Vector3.RIGHT * 20.0,
		Rules.PITCH_SIZE.x)
	var recovering_keeper := keeper.duplicate(true)
	recovering_keeper.keeper_recovery_ticks = 8
	var recovering := FeelRules.goalkeeper_outcome(recovering_keeper, Vector3(80.0, 0.4, 18.0),
		Vector3.RIGHT * 20.0, Rules.PITCH_SIZE.x)
	_expect(collect.outcome == "collect", "a reachable low shot produces a deterministic goalkeeper collection")
	_expect(parry.outcome == "parry" and dive.outcome == "dive",
		"edge low shots parry while reachable high shots select a dive")
	_expect(late.outcome == "hold" and bool(late.late), "a late goalkeeper dive is rejected")
	_expect(recovering.outcome == "hold" and bool(recovering.late),
		"a recovering goalkeeper cannot begin a second impossible save")
	_expect(gap.outcome == "gap" and bool(gap.gap_hit), "configured goalkeeper coverage gaps remain scoreable")
