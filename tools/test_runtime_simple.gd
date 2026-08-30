extends SceneTree
## 简单的运行时验证脚本
## 用法: godot --path . --headless --script tools/test_runtime_simple.gd

func _init():
	print("=== Runtime Verification Test ===\n")

	var success := true

	# 测试 1: PitchConstants 加载
	print("Test 1: PitchConstants Autoload")
	if PitchConstants:
		print("  ✅ PitchConstants loaded")
		print("  - WIDTH: %.0f" % PitchConstants.WIDTH)
		print("  - HEIGHT: %.0f" % PitchConstants.HEIGHT)
		print("  - SCALE_FACTOR: %.2f" % PitchConstants.SCALE_FACTOR)
	else:
		print("  ❌ PitchConstants not loaded")
		success = false

	# 测试 2: AI 常量
	print("\nTest 2: AI Constants")
	if PitchConstants.AI:
		print("  ✅ AI namespace exists")
		print("  - SHOT_DISTANCE: %.1f px" % PitchConstants.AI.SHOT_DISTANCE)
		print("  - TACKLE_DISTANCE: %.1f px" % PitchConstants.AI.TACKLE_DISTANCE)
		print("  - SPRINT_DIST_TO_GOAL_MAX: %.1f px" % PitchConstants.AI.SPRINT_DIST_TO_GOAL_MAX)

		# 验证缩放
		var expected_shot := 150.0 * PitchConstants.SCALE_FACTOR
		if abs(PitchConstants.AI.SHOT_DISTANCE - expected_shot) < 0.01:
			print("  ✅ SHOT_DISTANCE scaling correct")
		else:
			print("  ❌ SHOT_DISTANCE scaling incorrect")
			success = false
	else:
		print("  ❌ AI namespace missing")
		success = false

	# 测试 3: BALL 常量
	print("\nTest 3: BALL Constants")
	if PitchConstants.BALL:
		print("  ✅ BALL namespace exists")
		print("  - BOUNCINESS: %.1f" % PitchConstants.BALL.BOUNCINESS)
		print("  - DISTANCE_HIGH_PASS: %.1f px" % PitchConstants.BALL.DISTANCE_HIGH_PASS)
		print("  - SHOT_GROUND_FRICTION: %.1f px/s²" % PitchConstants.BALL.SHOT_GROUND_FRICTION)
	else:
		print("  ❌ BALL namespace missing")
		success = false

	# 测试 4: PLAYER 常量
	print("\nTest 4: PLAYER Constants")
	if PitchConstants.PLAYER:
		print("  ✅ PLAYER namespace exists")
		print("  - PASSING_ASSIST_MAGNET_RANGE_SHORT: %.1f px" % PitchConstants.PLAYER.PASSING_ASSIST_MAGNET_RANGE_SHORT)
		print("  - MOVING_SPRINT_SPEED_MULTIPLIER: %.1f" % PitchConstants.PLAYER.MOVING_SPRINT_SPEED_MULTIPLIER)
	else:
		print("  ❌ PLAYER namespace missing")
		success = false

	# 测试 5: 辅助函数
	print("\nTest 5: Helper Functions")
	var scaled_val := PitchConstants.scaled(100.0)
	var absolute_val := PitchConstants.absolute(100.0)
	print("  - scaled(100.0) = %.1f" % scaled_val)
	print("  - absolute(100.0) = %.1f" % absolute_val)
	if scaled_val == 100.0 * PitchConstants.SCALE_FACTOR:
		print("  ✅ scaled() working correctly")
	else:
		print("  ❌ scaled() not working")
		success = false
	if absolute_val == 100.0:
		print("  ✅ absolute() working correctly")
	else:
		print("  ❌ absolute() not working")
		success = false

	# 测试 6: 缩放一致性
	print("\nTest 6: Scaling Consistency")
	var aspect_preserved := PitchConstants.is_aspect_ratio_preserved()
	print("  - Aspect ratio preserved: %s" % aspect_preserved)
	if aspect_preserved:
		print("  ✅ Aspect ratio check passed")
	else:
		print("  ⚠️  Aspect ratio not preserved (might be intentional)")

	# 测试 7: 重力缩放
	print("\nTest 7: Gravity Scaling")
	var expected_gravity := 600.0 * PitchConstants.SCALE_FACTOR
	print("  - GRAVITY: %.1f px/s²" % PitchConstants.GRAVITY)
	print("  - Expected: %.1f px/s²" % expected_gravity)
	if abs(PitchConstants.GRAVITY - expected_gravity) < 0.01:
		print("  ✅ Gravity scaling correct")
	else:
		print("  ❌ Gravity scaling incorrect")
		success = false

	# 最终结果
	print("\n" + "=".repeat(50))
	if success:
		print("✅ All tests passed!")
		print("PitchConstants refactoring successful.")
		quit(0)
	else:
		print("❌ Some tests failed!")
		print("Please review the errors above.")
		quit(1)
