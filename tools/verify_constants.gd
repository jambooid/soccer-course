extends Node
## 运行时验证 - 作为场景节点运行
## 用法: 在 Godot 编辑器中运行此场景，或通过 test_runner.gd 调用

func _ready():
	print("\n=== Runtime Constants Verification ===\n")

	verify_pitch_constants()
	verify_ai_constants()
	verify_ball_constants()
	verify_player_constants()
	verify_scaling_functions()

	print("\n✅ All constants verified successfully!")
	print("Ready to test different pitch sizes.\n")

	# 自动退出（测试模式）
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()

func verify_pitch_constants():
	print("📐 PitchConstants Core:")
	print("  WIDTH = %.0f, HEIGHT = %.0f" % [PitchConstants.WIDTH, PitchConstants.HEIGHT])
	print("  REFERENCE = %.0f × %.0f" % [PitchConstants.REFERENCE_WIDTH, PitchConstants.REFERENCE_HEIGHT])
	print("  SCALE_FACTOR = %.2f" % PitchConstants.SCALE_FACTOR)
	print("  GRAVITY = %.1f px/s²" % PitchConstants.GRAVITY)
	assert(PitchConstants.SCALE_FACTOR == PitchConstants.WIDTH / PitchConstants.REFERENCE_WIDTH)
	print("  ✓ Core values correct")

func verify_ai_constants():
	print("\n🤖 AI Constants:")
	print("  SHOT_DISTANCE = %.1f px" % PitchConstants.AI.SHOT_DISTANCE)
	print("  TACKLE_DISTANCE = %.1f px" % PitchConstants.AI.TACKLE_DISTANCE)
	print("  SPRINT_DIST_TO_GOAL_MAX = %.1f px (should equal HALFPITCH_X)" % PitchConstants.AI.SPRINT_DIST_TO_GOAL_MAX)
	assert(abs(PitchConstants.AI.SPRINT_DIST_TO_GOAL_MAX - PitchConstants.HALFPITCH_X) < 0.01)
	print("  ✓ AI constants correct")

func verify_ball_constants():
	print("\n⚽ BALL Constants:")
	print("  BOUNCINESS = %.1f" % PitchConstants.BALL.BOUNCINESS)
	print("  DISTANCE_HIGH_PASS = %.1f px" % PitchConstants.BALL.DISTANCE_HIGH_PASS)
	print("  KICKED_GROUND_FRICTION = %.1f px/s²" % PitchConstants.BALL.KICKED_GROUND_FRICTION)
	print("  SHOT_GROUND_FRICTION = %.1f px/s²" % PitchConstants.BALL.SHOT_GROUND_FRICTION)
	assert(PitchConstants.BALL.BOUNCINESS == 0.8)
	print("  ✓ BALL constants correct")

func verify_player_constants():
	print("\n🏃 PLAYER Constants:")
	print("  PASSING_ASSIST_MAGNET_RANGE_SHORT = %.1f px" % PitchConstants.PLAYER.PASSING_ASSIST_MAGNET_RANGE_SHORT)
	print("  MOVING_SPRINT_SPEED_MULTIPLIER = %.1f" % PitchConstants.PLAYER.MOVING_SPRINT_SPEED_MULTIPLIER)
	print("  HURT_BALL_TUMBLE_SPEED = %.1f px/s" % PitchConstants.PLAYER.HURT_BALL_TUMBLE_SPEED)
	assert(PitchConstants.PLAYER.MOVING_SPRINT_SPEED_MULTIPLIER == 1.6)
	print("  ✓ PLAYER constants correct")

func verify_scaling_functions():
	print("\n🔧 Scaling Functions:")
	var test_val := 100.0
	var scaled := PitchConstants.scaled(test_val)
	var absolute := PitchConstants.absolute(test_val)
	print("  scaled(%.1f) = %.1f" % [test_val, scaled])
	print("  absolute(%.1f) = %.1f" % [test_val, absolute])
	assert(scaled == test_val * PitchConstants.SCALE_FACTOR)
	assert(absolute == test_val)
	print("  ✓ Scaling functions correct")
