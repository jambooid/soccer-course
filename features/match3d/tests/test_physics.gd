extends SceneTree

const Rules := preload("res://utils/match3d_rules.gd")
const Pitch3D := preload("res://scenes/world3d/pitch_3d.gd")

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
	_test_directional_pass_prefers_forward_teammate()
	_test_pass_speed_and_shot_speed_are_distinct()
	_test_goal_detection()
	_test_camera_target()
	_test_nearest_player_filtering()
	_test_switch_target()
	_test_player_separation()
	_test_visible_goal_matches_scoring_mouth()
	_test_visible_goal_front_frames_are_on_goal_lines()
	_test_goal_depth_extends_outside_pitch()
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
	var moved := Rules.advance_player(Vector2(84.4, 0.5), Vector2.ZERO, Vector2(1.0, -1.0), 1.0, 12.0)
	var position: Vector2 = moved.position
	var velocity: Vector2 = moved.velocity
	_expect(position.x <= Rules.PITCH_SIZE.x - Rules.PLAYER_RADIUS + 0.001 and position.y >= Rules.PLAYER_RADIUS - 0.001,
		"player motion stays inside the playable pitch")
	_expect(velocity.length() <= 12.0,
		"player acceleration respects top speed")

func _test_directional_pass_prefers_forward_teammate() -> void:
	var players := [
		{"id": 1, "home": true, "position": Vector2(30.0, 18.0)},
		{"id": 2, "home": true, "position": Vector2(47.0, 18.0)},
		{"id": 3, "home": true, "position": Vector2(28.0, 7.0)},
		{"id": 4, "home": false, "position": Vector2(44.0, 18.0)},
	]
	var target := Rules.select_pass_target(players, 1, true, Vector2.RIGHT, Vector2(30.0, 18.0))
	_expect(int(target.id) == 2, "rightward pass selects the forward teammate")
	var reverse := Rules.select_pass_target(players, 1, true, Vector2.UP, Vector2(30.0, 18.0))
	_expect(int(reverse.id) == 3, "vertical input selects the vertical outlet")

func _test_pass_speed_and_shot_speed_are_distinct() -> void:
	var short_kick := Rules.pass_velocity(Vector2.ZERO, Vector2(10.0, 0.0))
	var long_pass := Rules.pass_velocity(Vector2.ZERO, Vector2(10.0, 0.0), true)
	var shot := Rules.shot_velocity(Vector2(35.0, 18.0), true)
	_expect(is_equal_approx(short_kick.length(), Rules.PASS_SPEED), "short pass has a stable launch speed")
	_expect(long_pass.length() > short_kick.length() and shot.length() > long_pass.length(),
		"long pass and shot have readable speed tiers")

func _test_goal_detection() -> void:
	_expect(Rules.goal_scoring_team(Vector2(-0.1, 18.0)) == -1, "left goal awards the away team")
	_expect(Rules.goal_scoring_team(Vector2(85.1, 18.0)) == 1, "right goal awards the home team")
	_expect(Rules.goal_scoring_team(Vector2(-0.1, 1.0)) == 0, "ball outside goal mouth is not a goal")

func _test_nearest_player_filtering() -> void:
	var players := [
		{"id": 1, "home": true, "position": Vector2(10.0, 10.0)},
		{"id": 2, "home": false, "position": Vector2(11.0, 10.0)},
		{"id": 3, "home": true, "position": Vector2(14.0, 10.0)},
	]
	_expect(Rules.nearest_player_id(players, Vector2(11.1, 10.0)) == 2, "nearest player wins free-ball selection")
	_expect(Rules.nearest_player_id(players, Vector2(11.1, 10.0), 1) == 1, "home filter selects nearest home player")

func _test_camera_target() -> void:
	var left := Rules.camera_target(Vector2(-20.0, -4.0))
	var right := Rules.camera_target(Vector2(100.0, 45.0))
	_expect(left == Vector2(Rules.CAMERA_TARGET_X_MIN, Rules.CAMERA_TARGET_Y_MIN),
		"camera clamps safely at the left/top pitch bounds")
	_expect(right == Vector2(Rules.CAMERA_TARGET_X_MAX, Rules.CAMERA_TARGET_Y_MAX),
		"camera clamps safely at the right/bottom pitch bounds")

func _test_player_separation() -> void:
	var resolved := Rules.resolve_pair_separation(Vector2.ZERO, Vector2.ZERO)
	var first: Vector2 = resolved.first
	var second: Vector2 = resolved.second
	_expect(first.distance_to(second) >= Rules.PLAYER_RADIUS * 2.0 - 0.001,
		"overlapping players separate to their footprint distance")

func _test_switch_target() -> void:
	var players := [
		{"id": 1, "home": true, "position": Vector2(10.0, 18.0)},
		{"id": 2, "home": true, "position": Vector2(18.0, 18.0)},
		{"id": 3, "home": true, "position": Vector2(10.0, 8.0)},
		{"id": 4, "home": false, "position": Vector2(12.0, 18.0)},
	]
	_expect(Rules.select_switch_target(players, 1, Vector2.RIGHT, Vector2(12.0, 18.0)) == 2,
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
