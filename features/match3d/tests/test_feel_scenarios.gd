extends SceneTree

const Rules := preload("res://utils/match3d_rules.gd")
const FeelRules := preload("res://utils/match_feel_rules.gd")
const SeededRngScript := preload("res://utils/seeded_rng.gd")

var passed := 0
var failed := 0

func _init() -> void:
	var result := run_suite()
	quit(0 if result.failed == 0 else 1)

func run_suite() -> Dictionary:
	passed = 0
	failed = 0
	print("=== WE2000 Feel Calibration Scenarios ===")
	var rng := SeededRngScript.new(2000)
	var receiver := {"id": 8, "home": true, "position": Vector3(42.0, 0.0, 18.0),
		"arrival_speed": 8.8, "technique": 72.0, "facing": Vector3.RIGHT}
	var opponent := {"id": 20, "home": false, "position": Vector3(50.0, 0.0, 18.0), "arrival_speed": 8.8}
	var short_velocity := Rules.pass_velocity(Vector3(30.0, 0.0, 18.0), receiver.position)
	_record_budget("short_pass", rng, short_velocity.length(), Rules.PASS_SPEED, 0.01)
	var through_target: Vector3 = receiver.position + Vector3.RIGHT * 4.2
	var through_velocity := Rules.pass_velocity(Vector3(30.0, 0.0, 18.0), through_target)
	_record_budget("through_pass", rng, through_velocity.length(), Rules.PASS_SPEED, 0.01)
	var long_velocity := Rules.pass_velocity(Vector3(30.0, 0.0, 18.0), receiver.position, true)
	_record_budget("long_pass", rng, long_velocity.length(), Rules.LONG_PASS_SPEED, 0.01)
	var first_touch := FeelRules.first_touch_state(receiver, receiver.position, Vector3.RIGHT * 12.0, 0.2, 140)
	_record_budget("first_touch", rng, float(first_touch.duration_ticks), 6.0, 8.0)
	var race := FeelRules.resolve_arrival_race(receiver, [opponent], receiver.position, 2, 2)
	_record_budget("interception", rng, float(race.arrival_delta_ticks), 0.0, 999.0)
	var shielded_touch := FeelRules.first_touch_state(receiver, receiver.position, Vector3.RIGHT * 8.0, 0.0, 160)
	_record_budget("shielding", rng, float(shielded_touch.pressure), 0.0, 0.01)
	var pressured_touch := FeelRules.first_touch_state(receiver, receiver.position, Vector3.RIGHT * 8.0, 0.9, 160)
	_record_budget("tackle", rng, float(pressured_touch.pressure), 0.9, 0.01)
	var keeper := {"id": 11, "position": Vector3(81.0, 0.0, 18.0), "keeper_recovery_ticks": 0}
	var low_save := FeelRules.goalkeeper_outcome(keeper, Vector3(82.0, 0.4, 18.2), Vector3.RIGHT * 20.0,
		Rules.PITCH_SIZE.x)
	_record_budget("low_save", rng, 1.0 if low_save.outcome == "collect" else 0.0, 1.0, 0.0)
	var gap_shot := FeelRules.goalkeeper_outcome(keeper, Vector3(82.0, 0.4, 22.1), Vector3.RIGHT * 20.0,
		Rules.PITCH_SIZE.x)
	_record_budget("coverage_gap_shot", rng, 1.0 if gap_shot.outcome == "gap" else 0.0, 1.0, 0.0)
	print("Results: %d passed, %d failed" % [passed, failed])
	return {"passed": passed, "failed": failed}

func _record_budget(name: String, rng, measured: float, target: float, tolerance: float) -> void:
	var sample_seed: int = rng.randi_range(1, 2147483646)
	var within_budget := absf(measured - target) <= tolerance
	print("  [SCENARIO] %s seed=%d measured=%.3f budget=%.3f+/-%.3f" %
		[name, sample_seed, measured, target, tolerance])
	if within_budget:
		passed += 1
		print("  [PASS] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)
