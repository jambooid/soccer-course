extends SceneTree

const DemoScene := preload("res://features/match3d/dribble_goalie_demo.tscn")

var passed := 0
var failed := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var demo := DemoScene.instantiate()
	root.add_child(demo)
	await process_frame
	demo.kickoff_timer = 0.0
	var camera := demo.get_node("Camera") as Camera3D
	_expect(camera.position.distance_to(demo.DEMO_CAMERA_BASE_FOCUS) < 45.0,
		"dribble lab uses a close inspection camera")
	_expect(demo.players.size() == 2, "dribble lab creates one carrier and one goalkeeper")
	_expect(demo.carrier_id == demo.DEMO_PLAYER_ID and demo.controlled_id == demo.DEMO_PLAYER_ID,
		"dribble lab starts with the carrier under manual control")
	var start: Vector3 = demo._player_by_id(demo.DEMO_PLAYER_ID).position
	Input.action_press("p1_right")
	for _i in range(18):
		demo._process(1.0 / 60.0)
	Input.action_release("p1_right")
	var carrier: Dictionary = demo._player_by_id(demo.DEMO_PLAYER_ID)
	_expect((carrier.position as Vector3).x > start.x + 0.2, "dribble lab carrier responds to movement input")
	_expect(demo.ball_velocity.length() > 0.1, "dribble lab ball receives a foot impulse")
	var turn_ball_start: Vector3 = demo.ball_position
	Input.action_press("p1_left")
	for _i in range(8):
		demo._process(1.0 / 60.0)
	_expect(demo.ball_position.x < turn_ball_start.x - 0.05 or demo.ball_velocity.x < -0.8,
		"dribble lab redirects the ball toward the new side within the first turn ticks")
	for _i in range(16):
		demo._process(1.0 / 60.0)
	Input.action_release("p1_left")
	carrier = demo._player_by_id(demo.DEMO_PLAYER_ID)
	var relative: Vector3 = demo.ball_position - (carrier.position as Vector3)
	_expect(relative.x < 1.0, "dribble lab reverse turn brings ball back to the leading side")
	carrier.velocity = Vector3.ZERO
	demo.players[demo.DEMO_PLAYER_ID] = carrier
	demo.ball_position = carrier.position + Vector3(0.3, 0.08, 0.0)
	demo.ball_velocity = Vector3(7.0, 0.0, 0.0)
	demo.dribble_touch_timer = 0.2
	for _i in range(8):
		demo._step_dribbling_ball(carrier, 1.0 / 60.0)
	_expect(demo.ball_velocity.length() < 0.1,
		"dribble lab stops residual ball rolling almost immediately when idle")
	var keeper: Dictionary = demo._player_by_id(demo.DEMO_KEEPER_ID)
	var keeper_start_z := (keeper.position as Vector3).z
	demo.ball_position = Vector3(18.0, 0.08, 27.0)
	for _i in range(30):
		demo._process(1.0 / 60.0)
	keeper = demo._player_by_id(demo.DEMO_KEEPER_ID)
	_expect((keeper.position as Vector3).z > keeper_start_z + 0.35,
		"goalkeeper tracks the ball laterally along the goal line")
	carrier = demo._player_by_id(demo.DEMO_PLAYER_ID)
	keeper.position = Vector3(76.0, 0.0, 18.0)
	carrier.position = Vector3(74.7, 0.0, 18.0)
	demo.players[demo.DEMO_KEEPER_ID] = keeper
	demo.players[demo.DEMO_PLAYER_ID] = carrier
	demo.ball_position = Vector3(74.7, 0.08, 18.0)
	demo.ball_velocity = Vector3.ZERO
	demo.carrier_id = demo.DEMO_PLAYER_ID
	demo._resolve_cpu_tackle(carrier)
	_expect(demo.carrier_id == -1, "goalkeeper wins a close dribble challenge")
	_expect(demo.ball_velocity.x < -0.1, "goalkeeper challenge sends the ball away from goal")
	demo._reset_kickoff(true)
	carrier = demo._player_by_id(demo.DEMO_PLAYER_ID)
	_expect((carrier.position as Vector3).is_equal_approx(demo.DEMO_START) and
		demo.carrier_id == demo.DEMO_PLAYER_ID,
		"dribble lab reset restores the carrier and ball setup")
	demo.free()
	print("=== Dribble Goalie Lab Tests ===")
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _expect(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("  [PASS] %s" % label)
	else:
		failed += 1
		print("  [FAIL] %s" % label)
