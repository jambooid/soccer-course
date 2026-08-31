extends Node

var passed := 0
var failed := 0

func _ready() -> void:
	print("=== Shooting Physics Tests ===")
	test_charge_is_bounded()
	test_aim_assists_toward_goal()
	test_goal_assist_ignores_sideways_input()
	test_power_increases_with_charge()
	test_shooting_attribute_improves_power()
	print("Results: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
		print("  [PASS] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)

func test_charge_is_bounded() -> void:
	_assert(is_equal_approx(ShootingPhysics.charge_ratio(-1.0), 0.0), "negative charge clamps to zero")
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
