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
	Input.action_press("p1_left")
	for _i in range(24):
		demo._process(1.0 / 60.0)
	Input.action_release("p1_left")
	carrier = demo._player_by_id(demo.DEMO_PLAYER_ID)
	var relative: Vector3 = demo.ball_position - (carrier.position as Vector3)
	_expect(relative.x < 1.0, "dribble lab reverse turn brings ball back to the leading side")
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
