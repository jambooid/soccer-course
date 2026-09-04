extends SceneTree

const MatchScene := preload("res://scenes/world3d/match3d_game.tscn")

var passed := 0
var failed := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := MatchScene.instantiate()
	root.add_child(game)
	await process_frame
	game.kickoff_timer = 0.0
	game._process(1.0 / 60.0)
	_expect(game.players.size() == 22, "runtime creates a full 11v11 match")
	_expect(game.players[0].position is Vector3 and game.players[0].position.y == 0.0,
		"players expose canonical 3D positions")
	_expect(game.carrier_id >= 0 and game.controlled_id >= 0, "kickoff assigns a controllable carrier")
	game._sync_views()
	var carrier_view := game._views[game.carrier_id] as Player3DView
	_expect(carrier_view.carrier_marker.visible, "carrier has a readable on-pitch marker")
	var regression_game := MatchScene.instantiate()
	root.add_child(regression_game)
	await process_frame
	regression_game.kickoff_timer = 0.0
	regression_game.cpu_tackle_cooldown = 999.0
	var regression_carrier: Dictionary = regression_game._player_by_id(regression_game.carrier_id)
	for i in regression_game.players.size():
		if i == regression_game.carrier_id:
			continue
		var isolated_player: Dictionary = regression_game.players[i]
		isolated_player.position = Vector3(4.0 + float(i % 2), 2.0, 2.0)
		regression_game.players[i] = isolated_player
	var idle_position: Vector3 = regression_carrier.position
	for _i in range(45):
		regression_game._process(1.0 / 60.0)
	var idle_after: Vector3 = regression_game._player_by_id(regression_game.controlled_id).position
	_expect(idle_after.distance_to(idle_position) < 0.05,
		"controlled player stays still when movement input is released")
	var camera := regression_game.get_node("Camera") as Camera3D
	var settled_camera_position := camera.position
	var settled_camera_rotation := camera.rotation
	for _i in range(20):
		regression_game._process(1.0 / 60.0)
	_expect(camera.position.distance_to(settled_camera_position) < 0.03,
		"camera remains stable while the ball and player are idle")
	regression_game.ball_position = Vector3(5.0, 0.08, 18.0)
	for _i in range(20):
		regression_game._process(1.0 / 60.0)
	var left_camera_position := camera.position
	_expect(left_camera_position.x < settled_camera_position.x - 0.5 and
		is_equal_approx(left_camera_position.y, settled_camera_position.y) and
		is_equal_approx(left_camera_position.z, settled_camera_position.z) and
		camera.rotation.is_equal_approx(settled_camera_rotation),
		"camera pans laterally while keeping depth, height, and rotation")
	regression_game.ball_position = Vector3(80.0, 0.08, 18.0)
	for _i in range(40):
		regression_game._process(1.0 / 60.0)
	_expect(camera.position.x > settled_camera_position.x + 0.5,
		"camera pans laterally when the ball changes sides")
	var force_carrier: Dictionary = regression_game._player_by_id(regression_game.carrier_id)
	regression_game.ball_position = force_carrier.position
	regression_game.ball_velocity = Vector3.ZERO
	regression_game.dribble_touch_timer = 0.0
	regression_game._step_dribbling_ball(force_carrier, 1.0 / 60.0)
	_expect(regression_game.ball_velocity.length() > 0.1,
		"a dribble contact applies a measurable foot force to a stationary ball")
	Input.action_press("p1_right")
	for _i in range(18):
		regression_game._process(1.0 / 60.0)
	Input.action_release("p1_right")
	var turn_ball_start: Vector3 = regression_game.ball_position
	Input.action_press("p1_left")
	for _i in range(12):
		regression_game._process(1.0 / 60.0)
	var turn_velocity: Vector3 = regression_game.ball_velocity
	_expect(regression_game.ball_position.x < turn_ball_start.x - 0.05 or turn_velocity.x < -0.5,
		"turning carrier redirects the ball toward the new input quickly")
	for _i in range(24):
		regression_game._process(1.0 / 60.0)
	Input.action_release("p1_left")
	var turned_carrier: Dictionary = regression_game._player_by_id(regression_game.carrier_id)
	var ball_relative_to_carrier: Vector3 = regression_game.ball_position - turned_carrier.position
	_expect(ball_relative_to_carrier.x < 0.9,
		"after a right-to-left cut the ball crosses to the new leading side")
	_expect(regression_game.carrier_id == regression_game.controlled_id,
		"turning with the ball keeps possession without opponent interference")
	regression_game.free()
	var controlled_before: Vector3 = game._player_by_id(game.controlled_id).position
	Input.action_press("p1_right")
	for _i in range(12):
		game._process(1.0 / 60.0)
	Input.action_release("p1_right")
	var controlled_after: Vector3 = game._player_by_id(game.controlled_id).position
	_expect(controlled_after.x > controlled_before.x + 0.12, "right input moves the controlled player")
	_expect(controlled_after.y == 0.0,
		"player motion stays on the X/Z ground plane")
	Input.action_press("p1_pass")
	game._process(1.0 / 60.0)
	Input.action_release("p1_pass")
	_expect(game.carrier_id == -1 and game.ball_velocity.length() > 0.0, "pass input releases the ball with velocity")
	_expect(game.ball_position.y > 0.0 and game._ball_view.global_position.is_equal_approx(game.ball_position),
		"ball keeps a canonical 3D position and view uses the same world units")
	var prior_controlled: int = game.controlled_id
	Input.action_press("p1_through_pass")
	game._process(1.0 / 60.0)
	Input.action_release("p1_through_pass")
	_expect(game.controlled_id != prior_controlled, "switch input transfers control")
	for _i in range(6):
		game._process(1.0 / 60.0)
	_expect(game.ball_position != game._player_by_id(game.controlled_id).position, "released ball simulates independently")
	var red_id := 20
	var red: Dictionary = game._player_by_id(red_id)
	red.position = Vector3(3.0, 0.0, 18.0)
	red.facing = Vector3.LEFT
	game.players[red_id] = red
	var isolated_defender: Dictionary = game._player_by_id(17)
	isolated_defender.position = Vector3(40.0, 0.0, 2.0)
	game.players[17] = isolated_defender
	for i in game.players.size():
		if i != red_id and i != 17:
			var distractor: Dictionary = game.players[i]
			distractor.position = Vector3(40.0, 0.0, 2.0)
			game.players[i] = distractor
	game.carrier_id = red_id
	game.cpu_action_cooldown = 0.0
	game.ball_position = red.position
	game.ball_velocity = Vector3.ZERO
	game.match_time = 20.0
	game._process(1.0 / 60.0)
	_expect(game.carrier_id == -1 and game.ball_velocity.x < 0.0, "CPU carrier shoots toward the goal")
	for _i in range(10):
		game._process(1.0 / 60.0)
		if game.score_away == 1:
			break
	_expect(game.score_away == 1 and game.kickoff_timer > 0.0, "goal increments score and restarts kickoff")
	_expect(game._event_label.text == "GOAL!", "goal feedback is not hidden by kickoff text")
	var home_carrier: Dictionary = game._player_by_id(9)
	var cpu_defender: Dictionary = game._player_by_id(17)
	home_carrier.position = Vector3(30.0, 0.0, 18.0)
	cpu_defender.position = Vector3(31.0, 0.0, 18.0)
	cpu_defender.facing = Vector3.LEFT
	game.players[9] = home_carrier
	game.players[17] = cpu_defender
	game.carrier_id = 9
	game.ball_position = home_carrier.position
	game.ball_velocity = Vector3.ZERO
	game.cpu_tackle_cooldown = 0.0
	game.kickoff_timer = 0.0
	game._resolve_cpu_tackle(home_carrier)
	_expect(game.carrier_id == 17, "CPU defender wins a close active tackle while facing the carrier")
	var kickoff_game := MatchScene.instantiate()
	root.add_child(kickoff_game)
	await process_frame
	Input.action_press("p1_pass")
	kickoff_game._process(1.0 / 60.0)
	Input.action_release("p1_pass")
	_expect(kickoff_game.kickoff_timer <= 0.0 and kickoff_game.carrier_id == -1,
		"kickoff pass responds before the countdown expires")
	kickoff_game.free()
	var charge_game := MatchScene.instantiate()
	root.add_child(charge_game)
	await process_frame
	charge_game.kickoff_timer = 0.0
	charge_game.action_cooldown = 0.0
	charge_game.carrier_id = 9
	charge_game.controlled_id = 9
	charge_game.cpu_tackle_cooldown = 999.0
	var charge_carrier: Dictionary = charge_game._player_by_id(9)
	charge_game.ball_position = charge_carrier.position
	charge_game.ball_velocity = Vector3.ZERO
	charge_game.last_touch_home = true
	for i in charge_game.players.size():
		if i != charge_game.carrier_id:
			var marker_test_player: Dictionary = charge_game.players[i]
			marker_test_player.position = Vector3(40.0, 0.0, 2.0)
			charge_game.players[i] = marker_test_player
	Input.action_press("p1_shoot")
	charge_game._process(1.0 / 60.0)
	charge_game._process(0.25)
	_expect(charge_game.shot_charging and charge_game.shot_charge > 0.0,
		"holding shoot enters a visible charge state")
	_expect(charge_game._power_bar.visible and charge_game._power_bar.value > 0.0,
		"holding shoot displays charge progress")
	Input.action_release("p1_shoot")
	charge_game._process(1.0 / 60.0)
	_expect(not charge_game.shot_charging and charge_game.carrier_id == -1 and charge_game.ball_velocity.length() > 0.0,
		"releasing shoot launches the charged ball")
	_expect(charge_game.ball_velocity.y > 0.0,
		"charged shot launches with an explicit vertical 3D component")
	charge_game.free()
	game.free()
	await _test_render_cadence_determinism()
	print("=== 3D Match Runtime Tests ===")
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_render_cadence_determinism() -> void:
	var low_rate := MatchScene.instantiate()
	var high_rate := MatchScene.instantiate()
	root.add_child(low_rate)
	root.add_child(high_rate)
	await process_frame
	for simulation in [low_rate, high_rate]:
		simulation.kickoff_timer = 0.0
		simulation.carrier_id = -1
		simulation.ball_position = Vector3(42.0, 1.5, 18.0)
		simulation.ball_velocity = Vector3(18.0, 6.0, 3.0)
		simulation._simulation_accumulator = 0.0
		simulation._simulation_tick = 0
	for _i in range(30):
		low_rate._process(1.0 / 30.0)
	for _i in range(120):
		high_rate._process(1.0 / 120.0)
	_expect(low_rate._simulation_tick == high_rate._simulation_tick,
		"render cadence advances the same number of fixed ticks")
	_expect(low_rate.ball_position.is_equal_approx(high_rate.ball_position),
		"render cadence produces the same 3D ball position")
	_expect(low_rate.ball_velocity.is_equal_approx(high_rate.ball_velocity),
		"render cadence produces the same 3D ball velocity")
	low_rate.free()
	high_rate.free()

func _expect(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("  [PASS] %s" % label)
	else:
		failed += 1
		print("  [FAIL] %s" % label)
