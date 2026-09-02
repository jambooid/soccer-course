extends Node

var passed := 0
var failed := 0

func _ready() -> void:
	var result := run_suite()
	get_tree().quit(0 if result.failed == 0 else 1)

func run_suite() -> Dictionary:
	passed = 0
	failed = 0
	print("=== Shooting Physics Tests ===")
	test_charge_is_bounded()
	test_aim_assists_toward_goal()
	test_goal_assist_ignores_sideways_input()
	test_power_increases_with_charge()
	test_shooting_attribute_improves_power()
	test_technique_improves_power_control()
	test_direction_input_adjusts_vertical_lane()
	print("Results: %d passed, %d failed" % [passed, failed])
	return {"passed": passed, "failed": failed}

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
		print("  [PASS] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)

func test_charge_is_bounded() -> void:
	_assert(is_equal_approx(ShootingPhysics.charge_ratio(-1.0), 0.0), "negative charge clamps to zero")
	_assert(is_equal_approx(PitchConstants.PLAYER.SHOOT_MAX_CHARGE_SECONDS, 0.75), "charge duration is 0.75 seconds")
	_assert(is_equal_approx(ShootingPhysics.charge_ratio(99.0), 1.0), "long charge clamps to one")

func test_aim_assists_toward_goal() -> void:
	var direction := ShootingPhysics.compute_aim_direction(
		Vector2(100, 100), Vector2.RIGHT, Vector2(700, 100), Vector2.ZERO, 60.0)
	_assert(direction.x > 0.95 and abs(direction.y) < 0.1, "no aim input targets goal center")

func test_goal_assist_ignores_sideways_input() -> void:
	var direction := ShootingPhysics.compute_aim_direction(
		Vector2(100, 100), Vector2.RIGHT, Vector2(700, 100), Vector2.LEFT, 90.0)
	_assert(direction.x > 0.95 and abs(direction.y) < 0.1, "goal assist keeps the shot pointed at goal")

func test_power_increases_with_charge() -> void:
	var low := ShootingPhysics.compute_shot_speed(150.0, 50.0, 0.2, 300.0)
	var high := ShootingPhysics.compute_shot_speed(150.0, 50.0, 1.0, 300.0)
	_assert(high > low, "full charge produces greater shot speed")
	_assert(high <= ShootingPhysics.MAX_SHOT_SPEED, "shot speed has an upper bound")

func test_shooting_attribute_improves_power() -> void:
	var low := ShootingPhysics.compute_shot_speed(150.0, 30.0, 0.8, 260.0)
	var high := ShootingPhysics.compute_shot_speed(150.0, 90.0, 0.8, 260.0)
	_assert(high > low, "shooting attribute affects shot power")

func test_technique_improves_power_control() -> void:
	var low := ShootingPhysics.compute_shot_speed(150.0, 70.0, 0.8, 260.0, 20.0)
	var high := ShootingPhysics.compute_shot_speed(150.0, 70.0, 0.8, 260.0, 90.0)
	_assert(high > low, "technique affects controlled shot power")

func test_direction_input_adjusts_vertical_lane() -> void:
	var center := ShootingPhysics.compute_aim_direction(Vector2(100, 100), Vector2.RIGHT,
		Vector2(700, 100), Vector2.ZERO, 90.0, 90.0, 80.0)
	var high_lane := ShootingPhysics.compute_aim_direction(Vector2(100, 100), Vector2.RIGHT,
		Vector2(700, 100), Vector2.UP, 90.0, 90.0, 80.0)
	_assert(high_lane.y < center.y - 0.01, "up input shifts shot trajectory upward")
