extends SceneTree

const MatchScene := preload("res://scenes/world3d/match3d_game.tscn")
const BallView := preload("res://scenes/world3d/ball_3d_view.gd")
const DribblePhysics3D := preload("res://utils/dribble_physics_3d.gd")
const Rules := preload("res://utils/match3d_rules.gd")
const Flow := preload("res://utils/match_flow.gd")

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
	# The remaining checks advance this instance explicitly. Keeping its engine
	# process callback disabled prevents auxiliary scene setup from adding ticks.
	game.set_process(false)
	_expect(game.players.size() == 22, "runtime creates a full 11v11 match")
	_expect(game.players[0].position is Vector3 and game.players[0].position.y == 0.0,
		"players expose canonical 3D positions")
	_expect(game.carrier_id >= 0 and game.controlled_id >= 0, "kickoff assigns a controllable carrier")
	game._sync_views()
	var carrier_view := game._views[game.carrier_id] as Player3DView
	_expect(carrier_view.carrier_marker.visible, "carrier has a readable on-pitch marker")
	for animation_name in [&"idle/clip", &"jog/clip", &"dribble/clip", &"turnaround/clip",
		&"pass/clip", &"shot/clip", &"tackle/clip", &"keeper_idle/clip"]:
		var clip := carrier_view.animation_player.get_animation(animation_name)
		_expect(_has_origin_locked_hips_track(clip),
			"%s animation keeps horizontal root motion at the player origin" % animation_name)
	var single_step_ball_view := BallView.new() as Ball3DView
	var split_step_ball_view := BallView.new() as Ball3DView
	root.add_child(single_step_ball_view)
	root.add_child(split_step_ball_view)
	await process_frame
	single_step_ball_view.sync_world_position(Vector3(12.0, 0.0, 18.0))
	single_step_ball_view.sync_world_position(Vector3(12.14, 0.0, 18.0))
	var single_step_basis := single_step_ball_view.model.basis
	split_step_ball_view.sync_world_position(Vector3(12.0, 0.0, 18.0))
	for offset in [0.035, 0.07, 0.105, 0.14]:
		split_step_ball_view.sync_world_position(Vector3(12.0 + offset, 0.0, 18.0))
	_expect(single_step_basis.is_equal_approx(split_step_ball_view.model.basis),
		"ball roll is determined by traveled distance instead of render cadence")
	single_step_ball_view.reset_roll_baseline()
	single_step_ball_view.sync_world_position(Vector3(42.5, 0.0, 18.0))
	_expect(single_step_basis.is_equal_approx(single_step_ball_view.model.basis),
		"ball reset establishes a roll baseline without a spin jump")
	_expect(single_step_ball_view.model.scale.is_equal_approx(Vector3.ONE) and
		is_equal_approx(single_step_ball_view.shadow.position.y, 0.006),
		"ball mesh and shadow use the authored ground-contact radius")
	single_step_ball_view.free()
	split_step_ball_view.free()
	var interpolation_game := MatchScene.instantiate()
	root.add_child(interpolation_game)
	await process_frame
	interpolation_game._previous_ball_position = Vector3(12.0, 0.0, 18.0)
	interpolation_game._has_previous_ball_position = true
	interpolation_game.carrier_id = -1
	interpolation_game.ball_position = Vector3(12.45, 0.0, 18.0)
	interpolation_game.ball_velocity = Vector3(27.0, 0.0, 0.0)
	interpolation_game._simulation_accumulator = interpolation_game.FIXED_TICK * 0.5
	interpolation_game._sync_views(true)
	_expect(interpolation_game._ball_view.global_position.is_equal_approx(Vector3(12.225, 0.0, 18.0)),
		"fast passed balls render between adjacent fixed simulation positions")
	interpolation_game.free()
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
		regression_game._update_camera(1.0 / 60.0)
	_expect(camera.position.distance_to(settled_camera_position) < 0.03,
		"camera remains stable while the ball and player are idle")
	var camera_carrier: Dictionary = regression_game._player_by_id(regression_game.carrier_id)
	camera_carrier.position = Vector3(24.0, 0.0, 12.0)
	camera_carrier.velocity = Vector3.ZERO
	regression_game.players[regression_game.carrier_id] = camera_carrier
	var carrier_camera_target: Vector3 = regression_game._camera_desired_focus()
	for _i in range(50):
		regression_game._update_camera(1.0 / 60.0)
	_expect(camera.position.distance_to(carrier_camera_target + regression_game.CAMERA_VIEW_OFFSET) < 1.1 and
		camera.rotation.is_equal_approx(settled_camera_rotation),
		"camera frames a carrier at the broadcast tracking anchor without rotating")
	camera_carrier = regression_game._player_by_id(regression_game.carrier_id)
	camera_carrier.position = Vector3(84.0, 0.0, 35.0)
	camera_carrier.velocity = Vector3.ZERO
	regression_game.players[regression_game.carrier_id] = camera_carrier
	var edge_camera_target: Vector3 = regression_game._camera_desired_focus()
	for _i in range(120):
		regression_game._update_camera(1.0 / 60.0)
	_expect(edge_camera_target.is_equal_approx(Vector3(regression_game.CAMERA_FOCUS_X_MAX, 0.0,
		regression_game.CAMERA_FOCUS_Z_MAX)) and
		camera.position.distance_to(edge_camera_target + regression_game.CAMERA_VIEW_OFFSET) < 1.0,
		"camera stops at pitch boundaries instead of tracking beyond the field")
	camera_carrier = regression_game._player_by_id(regression_game.carrier_id)
	camera_carrier.position = Vector3(42.5, 0.0, 3.0)
	camera_carrier.velocity = Vector3.ZERO
	regression_game.players[regression_game.carrier_id] = camera_carrier
	var far_side_camera_target: Vector3 = regression_game._camera_desired_focus()
	for _i in range(120):
		regression_game._update_camera(1.0 / 60.0)
	_expect(is_equal_approx(far_side_camera_target.z, regression_game.CAMERA_FOCUS_Z_MIN) and
		camera.position.z < regression_game.CAMERA_BASE_POSITION.z - 8.0 and
		camera.rotation.is_equal_approx(settled_camera_rotation),
		"camera follows play toward the far upper half without changing the broadcast angle")
	# The near touchline is the tightest part of this low broadcast angle. Keep
	# following a carrier that is still moving toward it, rather than allowing
	# interpolation to leave the player/ball below the viewport for a frame.
	camera_carrier = regression_game._player_by_id(regression_game.carrier_id)
	camera_carrier.position = Vector3(42.5, 0.0, Rules.PITCH_SIZE.z - Rules.PLAYER_RADIUS)
	camera_carrier.velocity = Vector3(0.0, 0.0, 4.25)
	regression_game.players[regression_game.carrier_id] = camera_carrier
	regression_game.ball_position = Vector3(42.5, 0.0, Rules.PITCH_SIZE.z - 0.12)
	regression_game.ball_velocity = Vector3(0.0, 0.0, 4.25)
	var near_edge_camera_target: Vector3 = regression_game._camera_desired_focus()
	for _i in range(120):
		regression_game._update_camera(1.0 / 60.0)
	var viewport_height := camera.get_viewport().get_visible_rect().size.y
	var carrier_screen := camera.unproject_position(camera_carrier.position + Vector3.UP * 1.0)
	var ball_screen := camera.unproject_position(regression_game.ball_position + Vector3.UP * 0.2)
	_expect(is_equal_approx(near_edge_camera_target.z, regression_game.CAMERA_FOCUS_Z_MAX) and
		camera.position.z > regression_game.CAMERA_BASE_POSITION.z + 1.0 and
		carrier_screen.y >= 0.0 and carrier_screen.y <= viewport_height and
		ball_screen.y >= 0.0 and ball_screen.y <= viewport_height and
		camera.rotation.is_equal_approx(settled_camera_rotation),
		"camera keeps a moving carrier and ball visible at the near touchline")
	camera_carrier.position = Vector3(Rules.PITCH_SIZE.x - Rules.PLAYER_RADIUS, 0.0,
		Rules.PITCH_SIZE.z - Rules.PLAYER_RADIUS)
	regression_game.players[regression_game.carrier_id] = camera_carrier
	regression_game.ball_position = Vector3(Rules.PITCH_SIZE.x - 0.12, 0.0,
		Rules.PITCH_SIZE.z - 0.12)
	var near_corner_camera_target: Vector3 = regression_game._camera_desired_focus()
	for _i in range(120):
		regression_game._update_camera(1.0 / 60.0)
	ball_screen = camera.unproject_position(regression_game.ball_position + Vector3.UP * 0.2)
	var viewport_width := camera.get_viewport().get_visible_rect().size.x
	_expect(near_corner_camera_target.is_equal_approx(Vector3(regression_game.CAMERA_FOCUS_X_MAX, 0.0,
		regression_game.CAMERA_FOCUS_Z_MAX)) and ball_screen.x >= 0.0 and ball_screen.x <= viewport_width and
		ball_screen.y >= 0.0 and ball_screen.y <= viewport_height,
		"camera keeps the ball visible in the near right corner")
	regression_game.carrier_id = -1
	regression_game.last_touch_home = true
	regression_game.ball_position = Vector3(38.0, 0.0, 16.0)
	regression_game.ball_velocity = Vector3.ZERO
	_expect(regression_game._camera_desired_focus().is_equal_approx(Vector3(
		38.0 + regression_game.CAMERA_SCREEN_X_OFFSET, 0.0,
		16.0 + regression_game.CAMERA_SCREEN_Z_OFFSET)),
		"a stationary loose ball keeps the normal attacking-side screen anchor")
	regression_game.ball_velocity = Vector3(30.0, 0.0, 0.0)
	var fast_ball_target: Vector3 = regression_game._camera_desired_focus()
	_expect(is_equal_approx(fast_ball_target.x, 38.0 + 30.0 * regression_game.CAMERA_BALL_LOOKAHEAD_SECONDS +
		regression_game.CAMERA_SCREEN_X_OFFSET) and
		is_equal_approx(fast_ball_target.z, 16.0 + regression_game.CAMERA_SCREEN_Z_OFFSET) and
		is_equal_approx(regression_game._camera_follow_response(), regression_game.CAMERA_FAST_BALL_FOLLOW_RESPONSE),
		"a fast loose ball receives capped trajectory lookahead and faster camera response")
	regression_game.ball_velocity = Vector3.ZERO
	regression_game.camera_focus = regression_game.CAMERA_BASE_FOCUS
	var deadzone_carrier: Dictionary = regression_game._player_by_id(regression_game.controlled_id)
	deadzone_carrier.position = Vector3(
		regression_game.CAMERA_BASE_FOCUS.x - regression_game.CAMERA_SCREEN_X_OFFSET + regression_game.CAMERA_FOCUS_DEADZONE_X * 0.5,
		0.0,
		regression_game.CAMERA_BASE_FOCUS.z - regression_game.CAMERA_SCREEN_Z_OFFSET + regression_game.CAMERA_FOCUS_DEADZONE_Z * 0.5)
	deadzone_carrier.velocity = Vector3.ZERO
	regression_game.players[regression_game.controlled_id] = deadzone_carrier
	regression_game.carrier_id = regression_game.controlled_id
	regression_game._update_camera(1.0 / 60.0)
	_expect(regression_game.camera_focus.is_equal_approx(regression_game.CAMERA_BASE_FOCUS),
		"small close-control movement remains inside the camera deadzone")
	regression_game.carrier_id = regression_game.controlled_id
	var paced_carrier: Dictionary = regression_game._player_by_id(regression_game.carrier_id)
	paced_carrier.position = Vector3(42.5, 0.0, 18.0)
	paced_carrier.velocity = Vector3.ZERO
	regression_game.players[regression_game.carrier_id] = paced_carrier
	regression_game.controlled_id = -1
	for _i in range(30):
		regression_game._step_players(1.0 / 60.0)
	paced_carrier = regression_game._player_by_id(regression_game.carrier_id)
	_expect(is_equal_approx(paced_carrier.velocity.length(), regression_game.JOG_DRIBBLE_TOP_SPEED) and
		is_equal_approx(regression_game.JOG_DRIBBLE_TOP_SPEED * 10.0, Rules.PITCH_SIZE.x * 0.5),
		"non-sprint ball carrying reaches the halfway line from a goal line in about ten seconds")
	regression_game.controlled_id = regression_game.carrier_id
	var force_carrier: Dictionary = regression_game._player_by_id(regression_game.carrier_id)
	force_carrier.velocity = Vector3.ZERO
	force_carrier.movement_intent = false
	regression_game.players[regression_game.carrier_id] = force_carrier
	regression_game.ball_position = force_carrier.position
	regression_game.ball_velocity = Vector3.ZERO
	regression_game.dribble_touch_timer = 0.0
	var parked_position: Vector3 = regression_game.ball_position
	regression_game._step_dribbling_ball(force_carrier, 1.0 / 60.0)
	_expect(regression_game.ball_velocity.length() < 0.001 and
		regression_game.ball_position.is_equal_approx(parked_position),
		"an idle carrier leaves a stationary ball completely at rest")
	force_carrier.velocity = Vector3.RIGHT * 4.0
	force_carrier.movement_intent = false
	regression_game.players[regression_game.carrier_id] = force_carrier
	var coast_start: Vector3 = force_carrier.position
	regression_game._step_players(1.0 / 60.0)
	force_carrier = regression_game._player_by_id(regression_game.carrier_id)
	_expect((force_carrier.position as Vector3).is_equal_approx(coast_start) and force_carrier.velocity.is_zero_approx(),
		"released dribble input immediately plants the controlled carrier")
	force_carrier.velocity = Vector3.RIGHT * 4.0
	force_carrier.facing = Vector3.RIGHT
	force_carrier.input_direction = Vector3.RIGHT
	force_carrier.movement_intent = true
	regression_game.players[regression_game.carrier_id] = force_carrier
	regression_game.ball_position = force_carrier.position + Vector3.RIGHT * 0.44
	regression_game.dribble_touch_timer = 0.0
	regression_game._step_dribbling_ball(force_carrier, 1.0 / 60.0)
	_expect(regression_game.ball_velocity.length() > 0.1,
		"a moving carrier applies a measurable foot impulse")
	_expect(is_zero_approx(regression_game.ball_position.y),
		"a moving human carrier keeps the ball at the pitch contact height")
	force_carrier.velocity = Vector3.RIGHT * 4.0
	force_carrier.movement_intent = false
	regression_game.players[regression_game.carrier_id] = force_carrier
	regression_game.ball_position = force_carrier.position + Vector3.RIGHT * 0.44
	regression_game.ball_velocity = Vector3.RIGHT * 6.0
	regression_game.dribble_touch_timer = 1.0
	var rolling_start: Vector3 = regression_game.ball_position
	var follower_start: Vector3 = force_carrier.position
	for _i in range(12):
		regression_game._step_players(1.0 / 60.0)
		force_carrier = regression_game._player_by_id(regression_game.carrier_id)
		regression_game._step_dribbling_ball(force_carrier, 1.0 / 60.0)
	var stop_roll_distance: float = regression_game.ball_position.x - rolling_start.x
	var carrier_stop_distance: float = (force_carrier.position as Vector3).x - follower_start.x
	var final_foot_gap: float = regression_game.ball_position.x - (force_carrier.position as Vector3).x
	_expect(stop_roll_distance > 0.10 and stop_roll_distance <= DribblePhysics3D.STOP_ROLL_DISTANCE_JOG + 0.01 and
		is_equal_approx(regression_game.ball_position.z, rolling_start.z) and regression_game.ball_velocity.is_zero_approx() and
		carrier_stop_distance > 0.08 and carrier_stop_distance < stop_roll_distance and
		absf(final_foot_gap - DribblePhysics3D.STOP_TRAP_FOOT_DISTANCE_JOG) < 0.02 and
		regression_game.carrier_id == int(force_carrier.id),
		"a moving carrier follows the short stop roll and traps the ball at the foot")
	force_carrier = regression_game._player_by_id(regression_game.carrier_id)
	force_carrier.velocity = Vector3.RIGHT * 0.70
	force_carrier.movement_intent = false
	regression_game.players[regression_game.carrier_id] = force_carrier
	regression_game.ball_position = force_carrier.position + Vector3.RIGHT * 0.62
	regression_game.ball_velocity = Vector3.RIGHT * 0.74
	var low_speed_position: Vector3 = regression_game.ball_position
	regression_game._step_dribbling_ball(force_carrier, 1.0 / 60.0)
	force_carrier = regression_game._player_by_id(regression_game.carrier_id)
	_expect(regression_game.ball_velocity.is_zero_approx() and force_carrier.velocity.is_zero_approx() and
		regression_game.ball_position.is_equal_approx(low_speed_position) and
		regression_game.carrier_id == int(force_carrier.id),
		"a released controlled carrier traps even a low-speed ball without pullback")
	regression_game.carrier_id = int(force_carrier.id)
	regression_game.controlled_id = int(force_carrier.id)
	regression_game.ball_position = force_carrier.position + Vector3.RIGHT * 0.62
	regression_game.ball_velocity = Vector3.ZERO
	regression_game.dribble_touch_timer = 0.0
	Input.action_press("p1_right")
	for _i in range(18):
		regression_game._process(1.0 / 60.0)
	Input.action_release("p1_right")
	Input.action_press("p1_left")
	for _i in range(12):
		regression_game._process(1.0 / 60.0)
	for _i in range(24):
		regression_game._process(1.0 / 60.0)
	Input.action_release("p1_left")
	var turned_carrier: Dictionary = regression_game._player_by_id(regression_game.carrier_id)
	var ball_relative_to_carrier: Vector3 = regression_game.ball_position - turned_carrier.position
	_expect(ball_relative_to_carrier.x < 0.9,
		"after a right-to-left cut the ball crosses to the new leading side")
	_expect(regression_game.carrier_id == regression_game.controlled_id,
		"turning with the ball keeps possession without opponent interference")
	var turn_carrier: Dictionary = regression_game._player_by_id(regression_game.carrier_id)
	turn_carrier.position = Vector3(42.0, 0.0, 18.0)
	turn_carrier.velocity = Vector3.RIGHT * 8.0
	turn_carrier.facing = Vector3.RIGHT
	turn_carrier.input_direction = Vector3.LEFT
	turn_carrier.movement_intent = true
	regression_game.players[regression_game.carrier_id] = turn_carrier
	regression_game.ball_position = turn_carrier.position + Vector3.RIGHT * 0.62
	regression_game.ball_velocity = Vector3.RIGHT * 9.0
	regression_game.dribble_touch_timer = 0.18
	regression_game.dribble_turn_anchor_timer = 0.0
	regression_game._step_dribbling_ball(turn_carrier, 1.0 / 60.0)
	_expect(regression_game.ball_velocity.x > 0.1,
		"turn input is queued until the next foot contact instead of steering each frame")
	var pre_anchor_ball_x: float = regression_game.ball_position.x
	regression_game.dribble_touch_timer = 0.0
	regression_game._step_dribbling_ball(turn_carrier, 1.0 / 60.0)
	var turnaround_view := regression_game._views[regression_game.carrier_id] as Player3DView
	_expect(regression_game.dribble_last_turn_type == DribblePhysics3D.TurnType.DEGREE_180 and
		regression_game.dribble_turn_anchor_timer > 0.0 and regression_game.ball_velocity.length() < 0.01 and
		turnaround_view.is_playing_action("turnaround"),
		"180 degree cut anchors the ball, clears its old velocity, and starts the turnaround clip")
	_expect(is_equal_approx(regression_game.ball_position.x, pre_anchor_ball_x),
		"180 degree cut keeps the ball at its contact position on the anchor's first frame")
	regression_game._step_dribbling_ball(turn_carrier, 1.0 / 60.0)
	_expect(regression_game.ball_position.x < pre_anchor_ball_x and regression_game.ball_position.x > turn_carrier.position.x - 0.24,
		"180 degree cut eases the ball toward the support foot instead of snapping it there")
	var planted_carrier: Dictionary = regression_game._player_by_id(regression_game.carrier_id)
	var planted_position: Vector3 = planted_carrier.position
	regression_game.controlled_id = -1
	for _i in range(3):
		regression_game._step_players(1.0 / 60.0)
	planted_carrier = regression_game._player_by_id(regression_game.carrier_id)
	_expect(planted_carrier.position.is_equal_approx(planted_position) and planted_carrier.velocity.length() < 0.01 and
		regression_game.dribble_turn_lock_timer > 0.0 and planted_carrier.facing.dot(Vector3.RIGHT) < 0.9,
		"180 degree cut plants the carrier while visibly rotating through the locked turn")
	var released_reverse := false
	for _i in range(12):
		regression_game._step_dribbling_ball(turn_carrier, 1.0 / 60.0)
		released_reverse = released_reverse or regression_game.ball_velocity.x < -0.1
	_expect(released_reverse,
		"180 degree cut releases the ball in the new reverse lane after the anchor")
	_expect(is_equal_approx(DribblePhysics3D.turn_speed_multiplier(DribblePhysics3D.TurnType.DEGREE_180), 0.15) and
		is_equal_approx(DribblePhysics3D.turn_anchor_duration(DribblePhysics3D.TurnType.DEGREE_180), 0.10),
		"180 degree cut uses the WE-style heavy penalty and short ball anchor")
	_expect(DribblePhysics3D.touch_offset(64.0, DribblePhysics3D.Mode.JOG) < 0.40 and
		DribblePhysics3D.touch_offset(64.0, DribblePhysics3D.Mode.JOG) < DribblePhysics3D.touch_offset(64.0, DribblePhysics3D.Mode.SPRINT),
		"non-sprint dribbling keeps the ball close to the controlling foot")
	_expect(DribblePhysics3D.JOG_MAX_BALL_DISTANCE < DribblePhysics3D.control_distance(64.0, DribblePhysics3D.Mode.JOG),
		"non-sprint ball-distance cap keeps loose touches inside the control radius")
	regression_game._reset_dribble_turn_state()
	regression_game.controlled_id = regression_game.carrier_id
	turn_carrier.input_direction = Vector3.FORWARD
	turn_carrier.velocity = Vector3.RIGHT * 8.0
	turn_carrier.facing = Vector3.RIGHT
	turn_carrier.movement_intent = true
	regression_game.players[regression_game.carrier_id] = turn_carrier
	regression_game.ball_position = turn_carrier.position + Vector3.RIGHT * 0.62
	regression_game.ball_velocity = Vector3.RIGHT * 11.0
	regression_game.dribble_touch_timer = 0.0
	regression_game.dribble_turn_anchor_timer = 0.0
	var pre_90_anchor_position: Vector3 = regression_game.ball_position
	regression_game._step_dribbling_ball(turn_carrier, 1.0 / 60.0)
	_expect(regression_game.dribble_last_turn_type == DribblePhysics3D.TurnType.DEGREE_90 and
		regression_game.dribble_phase == regression_game.DribblePhase.TURN_ANCHOR and
		regression_game.ball_velocity.length() < 0.01 and
		is_equal_approx(regression_game.ball_position.x, pre_90_anchor_position.x) and
		is_equal_approx(regression_game.ball_position.z, pre_90_anchor_position.z),
		"90 degree cut starts a short smooth anchor at the contact position")
	for _i in range(5):
		regression_game._step_dribbling_ball(turn_carrier, 1.0 / 60.0)
	_expect(regression_game.ball_velocity.x < 0.1 and regression_game.ball_velocity.z < -0.1,
		"90 degree cut clears old ball velocity and releases a lateral touch after the anchor")
	regression_game._reset_dribble_turn_state()
	turn_carrier.input_direction = Vector3(1.0, 0.0, -1.0)
	turn_carrier.velocity = Vector3.RIGHT * 8.0
	turn_carrier.facing = Vector3.RIGHT
	turn_carrier.movement_intent = true
	regression_game.players[regression_game.carrier_id] = turn_carrier
	regression_game.ball_position = turn_carrier.position + Vector3.RIGHT * 0.62
	regression_game.ball_velocity = Vector3.RIGHT * 9.0
	regression_game.dribble_touch_timer = 0.0
	regression_game._step_dribbling_ball(turn_carrier, 1.0 / 60.0)
	_expect(regression_game.dribble_last_turn_type == DribblePhysics3D.TurnType.DEGREE_45 and
		regression_game.dribble_phase == regression_game.DribblePhase.FREE_ROLL and
		regression_game.dribble_turn_lock_timer <= 0.0 and
		regression_game.ball_velocity.normalized().dot(Vector3(1.0, 0.0, -1.0).normalized()) > 0.99,
		"45 degree cut immediately redirects the ball into its new diagonal lane without anchoring")
	var turned_45_carrier: Dictionary = regression_game._player_by_id(regression_game.carrier_id)
	var expected_45_ball_speed := DribblePhysics3D.touch_target_speed(turn_carrier.velocity,
		int(turn_carrier.dribble_mode)) * 0.75
	_expect(is_equal_approx(regression_game.ball_velocity.length(), expected_45_ball_speed) and
		is_equal_approx(turned_45_carrier.velocity.length(), 7.6) and
		turned_45_carrier.velocity.normalized().dot(Vector3.RIGHT) > 0.99 and
		turned_45_carrier.facing.dot(Vector3.RIGHT) > 0.99 and
		is_equal_approx(DribblePhysics3D.turn_speed_multiplier(DribblePhysics3D.TurnType.DEGREE_45), 0.95) and
		is_equal_approx(DribblePhysics3D.turn_touch_multiplier(DribblePhysics3D.TurnType.DEGREE_45), 0.75),
		"45 degree contact sends the ball into its new lane before the player follows")
	var direct_45_velocity: Vector3 = regression_game.ball_velocity
	regression_game._step_dribbling_ball(turned_45_carrier, 1.0 / 60.0)
	_expect(regression_game.ball_velocity.normalized().dot(direct_45_velocity.normalized()) > 0.999 and
		regression_game.ball_velocity.length() < direct_45_velocity.length(),
		"45 degree ball free-rolls in its touched lane without carrier correction")
	regression_game._reset_dribble_turn_state()
	turn_carrier = regression_game._player_by_id(regression_game.carrier_id)
	turn_carrier.position = Vector3(42.0, 0.0, 18.0)
	turn_carrier.velocity = Vector3.RIGHT * 8.0
	turn_carrier.facing = Vector3.RIGHT
	turn_carrier.input_direction = Vector3.RIGHT
	turn_carrier.movement_intent = true
	regression_game.players[regression_game.carrier_id] = turn_carrier
	regression_game.ball_position = turn_carrier.position + Vector3.RIGHT * 0.62 + Vector3.UP * 0.08
	regression_game.ball_velocity = Vector3.RIGHT * 8.0
	regression_game.dribble_touch_timer = 0.04
	var pre_queued_turn_position: Vector3 = turn_carrier.position
	Input.action_press("p1_right")
	Input.action_press("p1_up")
	for _i in range(3):
		regression_game._step_players(1.0 / 60.0)
		turn_carrier = regression_game._player_by_id(regression_game.carrier_id)
		regression_game._step_dribbling_ball(turn_carrier, 1.0 / 60.0)
	turn_carrier = regression_game._player_by_id(regression_game.carrier_id)
	_expect(is_equal_approx(turn_carrier.position.z, pre_queued_turn_position.z) and
		regression_game.ball_velocity.z < -0.1 and turn_carrier.velocity.z > -0.01 and
		regression_game.dribble_45_turn_commit_timer > 0.0 and
		not regression_game.dribble_45_turn_pending_direction.is_zero_approx(),
		"45 degree touch gives the ball a short lead before the carrier turns")
	for _i in range(3):
		regression_game._step_players(1.0 / 60.0)
	turn_carrier = regression_game._player_by_id(regression_game.carrier_id)
	_expect(turn_carrier.velocity.z < -0.1,
		"45 degree carrier follows the ball into the committed diagonal lane")
	Input.action_release("p1_right")
	Input.action_release("p1_up")
	_expect(DribblePhysics3D.classify_turn(Vector3.RIGHT, Vector3(1.0, 0.0, 1.0)) ==
		DribblePhysics3D.TurnType.DEGREE_45 and DribblePhysics3D.classify_turn(Vector3.RIGHT, Vector3(-1.0, 0.0, 1.0)) ==
		DribblePhysics3D.TurnType.DEGREE_180 and DribblePhysics3D.classify_turn(Vector3.RIGHT, Vector3.LEFT) ==
		DribblePhysics3D.TurnType.DEGREE_180,
		"dribble contacts classify quantized 45 and 135-plus degree lanes")
	var safe_lane := DribblePhysics3D.steer_away_from_defender(Vector3.RIGHT, Vector3.ZERO,
		Vector3(1.4, 0.0, 0.0), Vector3.ZERO)
	_expect(safe_lane.z != 0.0 and safe_lane.dot(Vector3.RIGHT) > 0.0,
		"front defender selects a forward diagonal safety lane")
	var cpu_ground_game := MatchScene.instantiate()
	root.add_child(cpu_ground_game)
	await process_frame
	cpu_ground_game.kickoff_timer = 0.0
	var cpu_ground_carrier: Dictionary = cpu_ground_game._player_by_id(20)
	cpu_ground_carrier.position = Vector3(64.0, 0.0, 18.0)
	cpu_ground_carrier.velocity = Vector3.LEFT * 4.0
	cpu_ground_carrier.facing = Vector3.LEFT
	cpu_ground_carrier.input_direction = Vector3.LEFT
	cpu_ground_carrier.movement_intent = true
	cpu_ground_game.players[20] = cpu_ground_carrier
	cpu_ground_game.carrier_id = 20
	cpu_ground_game.controlled_id = -1
	cpu_ground_game.ball_position = cpu_ground_carrier.position + Vector3.LEFT * 0.44
	cpu_ground_game.ball_velocity = Vector3.ZERO
	cpu_ground_game.dribble_touch_timer = 0.0
	cpu_ground_game._step_dribbling_ball(cpu_ground_carrier, 1.0 / 60.0)
	_expect(is_zero_approx(cpu_ground_game.ball_position.y),
		"a moving CPU carrier keeps the ball at the pitch contact height")
	cpu_ground_game.free()
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
	_expect(game.ball_position.y > 0.0 and game._ball_view.global_position.is_equal_approx(game._previous_ball_position),
		"ball keeps canonical 3D physics coordinates while presentation interpolates its path")
	var prior_controlled: int = game.controlled_id
	Input.action_press("p1_switch")
	game._process(1.0 / 60.0)
	Input.action_release("p1_switch")
	_expect(game.controlled_id != prior_controlled, "switch input transfers control")
	var through_game := MatchScene.instantiate()
	root.add_child(through_game)
	await process_frame
	through_game.kickoff_timer = 0.0
	through_game.action_cooldown = 0.0
	through_game.cpu_tackle_cooldown = 999.0
	through_game.carrier_id = 9
	through_game.controlled_id = 9
	var through_carrier: Dictionary = through_game._player_by_id(9)
	through_game.ball_position = through_carrier.position
	Input.action_press("p1_through_pass")
	through_game._process(1.0 / 60.0)
	Input.action_release("p1_through_pass")
	_expect(through_game.carrier_id == -1 and through_game._event_label.text == "THROUGH" and
		through_game.ball_velocity.y > 2.0,
		"I executes an attacking through pass with extra lead and lift")
	through_game.free()
	var defensive_switch_game := MatchScene.instantiate()
	root.add_child(defensive_switch_game)
	await process_frame
	defensive_switch_game.kickoff_timer = 0.0
	defensive_switch_game.carrier_id = 20
	defensive_switch_game.controlled_id = 9
	var switch_ball_carrier: Dictionary = defensive_switch_game._player_by_id(20)
	var nearest_switch_player: Dictionary = defensive_switch_game._player_by_id(8)
	switch_ball_carrier.position = Vector3(50.0, 0.0, 18.0)
	nearest_switch_player.position = Vector3(49.0, 0.0, 18.0)
	defensive_switch_game.players[20] = switch_ball_carrier
	defensive_switch_game.players[8] = nearest_switch_player
	defensive_switch_game.ball_position = switch_ball_carrier.position
	Input.action_press("p1_switch")
	defensive_switch_game._process(1.0 / 60.0)
	Input.action_release("p1_switch")
	_expect(defensive_switch_game.controlled_id == 8,
		"U switches to the nearest available home player while defending")
	defensive_switch_game.free()
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
	# The remaster flow intentionally freezes live simulation during the goal
	# result/replay window. Resume the fixture explicitly before the following
	# isolated pressing checks.
	game.match_flow.phase = Flow.Phase.FIRST_HALF
	game.replay_active = false
	game._event_timer = 0.0
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
	game._update_tactical_roles()
	var close_press_assignment: Dictionary = game.tactical_assignments[17]
	_expect((close_press_assignment.target as Vector3).distance_to(game.ball_position) < 0.05,
		"a close primary presser attacks the ball instead of backing off to a jockey point")
	game._resolve_cpu_tackle(home_carrier)
	_expect(game.carrier_id == 17, "CPU defender wins a close active tackle while facing the carrier")
	_expect(game.ball_position.distance_to(game._player_by_id(17).position) < 0.6,
		"a successful AI tackle secures the ball at the winning defender's foot")
	var cpu_tackle_view := game._views[17] as Player3DView
	_expect(cpu_tackle_view.animation_player.current_animation == &"tackle/clip",
		"a successful AI tackle triggers the authored tackle animation")
	var recovering_tackler: Dictionary = game._player_by_id(17)
	var recovery_start: Vector3 = recovering_tackler.position
	_expect(float(recovering_tackler.tackle_recovery) > 0.5,
		"a successful tackle enters a short recovery window")
	game._step_players(0.25)
	recovering_tackler = game._player_by_id(17)
	_expect((recovering_tackler.position as Vector3).is_equal_approx(recovery_start) and
		float(recovering_tackler.tackle_recovery) > 0.0,
		"a recovering tackler cannot immediately move after winning the ball")
	var teammate_tackle_game := MatchScene.instantiate()
	root.add_child(teammate_tackle_game)
	await process_frame
	teammate_tackle_game.kickoff_timer = 0.0
	teammate_tackle_game.controlled_id = -1
	var away_carrier: Dictionary = teammate_tackle_game._player_by_id(20)
	var home_teammate: Dictionary = teammate_tackle_game._player_by_id(8)
	away_carrier.position = Vector3(49.0, 0.0, 18.0)
	home_teammate.position = Vector3(47.9, 0.0, 18.0)
	home_teammate.facing = Vector3.RIGHT
	teammate_tackle_game.players[20] = away_carrier
	teammate_tackle_game.players[8] = home_teammate
	teammate_tackle_game.carrier_id = 20
	teammate_tackle_game.ball_position = away_carrier.position
	teammate_tackle_game.cpu_tackle_cooldown = 0.0
	teammate_tackle_game._update_tactical_roles()
	teammate_tackle_game._resolve_cpu_tackle(away_carrier)
	_expect(teammate_tackle_game.carrier_id == 8,
		"an unselected home teammate can win the ball from a nearby CPU carrier")
	teammate_tackle_game.free()
	var pressure_game := MatchScene.instantiate()
	root.add_child(pressure_game)
	await process_frame
	pressure_game.kickoff_timer = 0.0
	pressure_game.controlled_id = 8
	var pressure_carrier: Dictionary = pressure_game._player_by_id(20)
	var pressure_defender: Dictionary = pressure_game._player_by_id(8)
	pressure_carrier.position = Vector3(49.0, 0.0, 18.0)
	pressure_carrier.facing = Vector3.LEFT
	pressure_defender.position = Vector3(47.9, 0.0, 18.0)
	pressure_defender.facing = Vector3.RIGHT
	pressure_defender.defense = 82.0
	pressure_game.players[20] = pressure_carrier
	pressure_game.players[8] = pressure_defender
	pressure_game.carrier_id = 20
	pressure_game.ball_position = pressure_carrier.position
	pressure_game._try_pressure(pressure_defender, pressure_carrier)
	_expect(pressure_game.carrier_id == 8,
		"user pressure can win possession without using the tackle action")
	var pressure_view := pressure_game._views[8] as Player3DView
	_expect(pressure_view.animation_player.current_animation == &"pressure/clip",
		"pressure uses the goalkeeper sidestep action while tackle remains separate")
	_expect(float(pressure_game._player_by_id(20).stumble_recovery) > 0.8,
		"a carrier who loses a pressure duel enters a stumble recovery")
	pressure_game.free()
	var protected_game := MatchScene.instantiate()
	root.add_child(protected_game)
	await process_frame
	protected_game.kickoff_timer = 0.0
	var protected_carrier: Dictionary = protected_game._player_by_id(20)
	var weak_defender: Dictionary = protected_game._player_by_id(8)
	protected_carrier.position = Vector3(49.0, 0.0, 18.0)
	protected_carrier.facing = Vector3.RIGHT
	weak_defender.position = Vector3(47.9, 0.0, 18.0)
	weak_defender.facing = Vector3.RIGHT
	weak_defender.defense = 58.0
	protected_game.players[20] = protected_carrier
	protected_game.players[8] = weak_defender
	protected_game.carrier_id = 20
	protected_game.ball_position = protected_carrier.position
	protected_game._try_pressure(weak_defender, protected_carrier)
	_expect(protected_game.carrier_id == 20,
		"a carrier facing away from a weak defender protects possession")
	protected_game.free()
	var rear_pressure_game := MatchScene.instantiate()
	root.add_child(rear_pressure_game)
	await process_frame
	rear_pressure_game.kickoff_timer = 0.0
	var rear_carrier: Dictionary = rear_pressure_game._player_by_id(20)
	var rear_defender: Dictionary = rear_pressure_game._player_by_id(8)
	rear_carrier.position = Vector3(49.0, 0.0, 18.0)
	rear_carrier.facing = Vector3.RIGHT
	rear_defender.position = Vector3(47.9, 0.0, 18.0)
	rear_defender.facing = Vector3.RIGHT
	rear_defender.defense = 58.0
	rear_pressure_game.players[20] = rear_carrier
	rear_pressure_game.players[8] = rear_defender
	rear_pressure_game.carrier_id = 20
	rear_pressure_game.ball_position = rear_carrier.position
	for _i in range(50):
		rear_defender = rear_pressure_game._player_by_id(8)
		rear_defender.pressure_cooldown = 0.0
		rear_pressure_game.players[8] = rear_defender
		rear_pressure_game._try_pressure(rear_defender, rear_carrier)
		rear_defender = rear_pressure_game._player_by_id(8)
		if float(rear_defender.stumble_recovery) > 0.0:
			break
	_expect(float(rear_defender.stumble_recovery) > 0.0,
		"sustained pressure from behind can make the defender stumble")
	rear_pressure_game.free()
	# 4-3-3 tactical layer: one defender presses, a second blocks the most
	# dangerous lane, and the remaining back line stays ball-relative.
	var tactics_game := MatchScene.instantiate()
	root.add_child(tactics_game)
	await process_frame
	tactics_game.kickoff_timer = 0.0
	tactics_game.controlled_id = -1
	var tactical_carrier: Dictionary = tactics_game._player_by_id(9)
	tactical_carrier.position = Vector3(57.0, 0.0, 28.0)
	tactical_carrier.velocity = Vector3.RIGHT * 4.0
	tactics_game.players[9] = tactical_carrier
	tactics_game.carrier_id = 9
	tactics_game.ball_position = tactical_carrier.position
	tactics_game._update_tactical_roles()
	var presser_id := int(tactics_game.primary_presser_by_team.away)
	var presser_assignment: Dictionary = tactics_game.tactical_assignments[presser_id]
	_expect(presser_id >= 11 and presser_assignment.state == "primary_press",
		"4-3-3 assigns exactly one away primary presser against a home carrier")
	var has_lane_cover := false
	for player: Dictionary in tactics_game.players:
		if not bool(player.home) and player.get("ai_state", "") == "lane_cover":
			has_lane_cover = true
	_expect(has_lane_cover, "4-3-3 assigns a second defender to cover a forward passing lane")
	var far_side_fullback: Dictionary = tactics_game._player_by_id(12)
	var far_side_assignment: Dictionary = tactics_game.tactical_assignments[12]
	_expect(absf((far_side_assignment.target as Vector3).z - far_side_fullback.spawn.z) > 1.0,
		"defensive formation shifts laterally with ball position instead of staying at spawn anchors")
	var advanced_winger: Dictionary = tactics_game._player_by_id(8)
	tactics_game._assign_team_tactics(true, tactical_carrier, true)
	var winger_assignment: Dictionary = tactics_game.tactical_assignments[int(advanced_winger.id)]
	_expect(winger_assignment.state == "forward_run" and (winger_assignment.target as Vector3).x > advanced_winger.spawn.x,
		"attacking 4-3-3 winger makes a forward support run when its lane is open")
	tactics_game.free()
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

func _has_origin_locked_hips_track(clip: Animation) -> bool:
	if clip == null:
		return false
	for track in clip.get_track_count():
		if clip.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var path := clip.track_get_path(track)
		if path.get_subname_count() != 1 or path.get_subname(0) != &"mixamorig5_Hips":
			continue
		for key in clip.track_get_key_count(track):
			var position := clip.track_get_key_value(track, key) as Vector3
			if not is_zero_approx(position.x) or not is_zero_approx(position.z):
				return false
		return true
	return false

func _expect(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("  [PASS] %s" % label)
	else:
		failed += 1
		print("  [FAIL] %s" % label)
