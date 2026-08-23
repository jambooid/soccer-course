# 带球物理数学验证脚本
# 用法：
#   1. 在 Godot 编辑器中，将此脚本附加到任意节点场景中运行
#   2. 或通过命令行：godot --path . -s tools/test_dribbling.gd
# 验证 DribblePhysics 的关键函数是否返回预期值
#
# 注意：需要在 Godot 环境中运行（依赖 GDScript 和 DribblePhysics 类）。
#       不是 headless 单元测试，而是快速验证数学正确性的辅助脚本。

extends Node

var _passed := 0
var _failed := 0

func _ready() -> void:
	print("=== Dribble Physics Tests ===")
	print()

	test_friction()
	test_touch_zone()
	test_stop_distance()
	test_predict_position()
	test_touch_zone_length()
	test_max_control_distance()
	test_touch_impulse()

	print()
	print("========================================")
	print("Results: %d passed, %d failed" % [_passed, _failed])
	if _failed == 0:
		print("All tests passed!")
	else:
		print("Some tests FAILED.")
	print("========================================")

	get_tree().quit()

# ---- 辅助函数 ----
func _assert(condition: bool, test_name: String, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % test_name)
	else:
		_failed += 1
		if detail == "":
			print("  [FAIL] %s" % test_name)
		else:
			print("  [FAIL] %s  (%s)" % [test_name, detail])

func _approx(a: float, b: float, tolerance: float = 0.01) -> bool:
	return abs(a - b) < tolerance

# ---- 测试用例 ----

func test_friction() -> void:
	print("-- Friction Tests --")

	# t=0 时速度不应变化
	var v0 := Vector2(100.0, 0.0)
	var result_0 := DribblePhysics.apply_friction(v0, 0.0)
	_assert(result_0 == v0, "Friction at t=0 unchanged",
		"expected %s got %s" % [v0, result_0])

	# 1 秒后速度应衰减到 f 倍（GROUND_FRICTION_PER_SEC = 0.35）
	var result_1s := DribblePhysics.apply_friction(v0, 1.0)
	var expected_1s := 100.0 * DribblePhysics.GROUND_FRICTION_PER_SEC
	_assert(_approx(result_1s.x, expected_1s),
		"Friction after 1s matches GROUND_FRICTION_PER_SEC",
		"expected %.4f got %.4f" % [expected_1s, result_1s.x])

	# 2 秒后速度 = v0 * f^2
	var result_2s := DribblePhysics.apply_friction(v0, 2.0)
	var expected_2s := 100.0 * pow(DribblePhysics.GROUND_FRICTION_PER_SEC, 2.0)
	_assert(_approx(result_2s.x, expected_2s),
		"Friction after 2s follows f^t decay",
		"expected %.4f got %.4f" % [expected_2s, result_2s.x])

	# 方向保持不变
	var v_diag := Vector2(60.0, 80.0)
	var result_diag := DribblePhysics.apply_friction(v_diag, 0.5)
	var ratio_x := result_diag.x / v_diag.x
	var ratio_y := result_diag.y / v_diag.y
	_assert(_approx(ratio_x, ratio_y, 0.001),
		"Friction preserves direction",
		"x_ratio=%.4f y_ratio=%.4f" % [ratio_x, ratio_y])

	# 零速度保持零
	var v_zero := Vector2.ZERO
	var result_zero := DribblePhysics.apply_friction(v_zero, 1.0)
	_assert(result_zero == Vector2.ZERO, "Friction on zero velocity stays zero")

	print()

func test_touch_zone() -> void:
	print("-- Touch Zone Tests --")

	var player_pos := Vector2.ZERO
	var player_dir := Vector2.RIGHT
	var tech := 64.0

	# 正前方应该在区内（触球区前端在 6px，长度随技术变化）
	var zone_length := DribblePhysics.get_touch_zone_length(tech)
	var front_offset := DribblePhysics.TOUCH_ZONE_FRONT_OFFSET
	var mid_point := Vector2(front_offset + zone_length * 0.5, 0.0)
	_assert(DribblePhysics.is_ball_in_touch_zone(mid_point, player_pos, player_dir, tech),
		"Ball in front middle is in touch zone",
		"pos=%s zone_len=%.1f" % [mid_point, zone_length])

	# 正前方、刚好在起点上
	var edge_start := Vector2(front_offset, 0.0)
	_assert(DribblePhysics.is_ball_in_touch_zone(edge_start, player_pos, player_dir, tech),
		"Ball at zone start edge is in touch zone (boundary inclusive)")

	# 正前方、刚好在终点上
	var edge_end := Vector2(front_offset + zone_length, 0.0)
	_assert(DribblePhysics.is_ball_in_touch_zone(edge_end, player_pos, player_dir, tech),
		"Ball at zone end edge is in touch zone (boundary inclusive)")

	# 正后方应该不在
	var behind := Vector2(-5.0, 0.0)
	_assert(not DribblePhysics.is_ball_in_touch_zone(behind, player_pos, player_dir, tech),
		"Ball behind player is NOT in touch zone",
		"pos=%s" % behind)

	# 太远的前方应该不在
	var far_front := Vector2(front_offset + zone_length + 10.0, 0.0)
	_assert(not DribblePhysics.is_ball_in_touch_zone(far_front, player_pos, player_dir, tech),
		"Ball too far forward is NOT in touch zone",
		"pos=%s zone_end=%.1f" % [far_front, front_offset + zone_length])

	# 侧面太远应该不在（宽度一半 = 4px）
	var half_width := DribblePhysics.TOUCH_ZONE_WIDTH / 2.0
	var side_far := Vector2(front_offset + zone_length * 0.5, half_width + 1.0)
	_assert(not DribblePhysics.is_ball_in_touch_zone(side_far, player_pos, player_dir, tech),
		"Ball too far sideways is NOT in touch zone",
		"pos=%s half_width=%.1f" % [side_far, half_width])

	# 侧面刚好在边界上
	var side_edge := Vector2(front_offset + zone_length * 0.5, half_width)
	_assert(DribblePhysics.is_ball_in_touch_zone(side_edge, player_pos, player_dir, tech),
		"Ball at side edge is in touch zone (boundary inclusive)")

	# 零方向向量应该返回 false
	_assert(not DribblePhysics.is_ball_in_touch_zone(
		Vector2(10, 0), player_pos, Vector2.ZERO, tech),
		"Zero direction returns false (no crash)")

	print()

func test_stop_distance() -> void:
	print("-- Stop Distance Tests --")

	# 停止距离应该是正值
	var dist_100 := DribblePhysics.compute_stop_distance(100.0)
	_assert(dist_100 > 0, "Stop distance is positive for v=100",
		"dist=%.2f" % dist_100)

	# 零速度停止距离为 0
	var dist_0 := DribblePhysics.compute_stop_distance(0.0)
	_assert(dist_0 == 0.0, "Stop distance is zero for v=0",
		"dist=%.2f" % dist_0)

	# 速度加倍，停止距离也应该加倍（线性关系）
	var dist_50 := DribblePhysics.compute_stop_distance(50.0)
	_assert(_approx(dist_100, dist_50 * 2.0),
		"Stop distance scales linearly with speed",
		"dist_100=%.2f dist_50*2=%.2f" % [dist_100, dist_50 * 2.0])

	# 解析解验证：S = v0 / -ln(f)
	var f := DribblePhysics.GROUND_FRICTION_PER_SEC
	var expected_dist := 100.0 / -log(f)
	_assert(_approx(dist_100, expected_dist),
		"Stop distance matches analytical formula v0 / -ln(f)",
		"got=%.4f expected=%.4f" % [dist_100, expected_dist])

	print("    Stop distance at 100px/s = %.2fpx" % dist_100)
	print("    Stop distance at 80px/s  = %.2fpx" % DribblePhysics.compute_stop_distance(80.0))
	print()

func test_predict_position() -> void:
	print("-- Position Prediction Tests --")

	var pos := Vector2(0.0, 0.0)
	var vel := Vector2(100.0, 0.0)

	# t=0 时位置不变
	var pred_0 := DribblePhysics.predict_ball_position(pos, vel, 0.0)
	_assert(pred_0 == pos, "Predict at t=0 returns original position",
		"got %s" % pred_0)

	# 1 秒后应该向前移动（摩擦力减速但仍有位移）
	var pred_1s := DribblePhysics.predict_ball_position(pos, vel, 1.0)
	_assert(pred_1s.x > 0, "Predict at t=1s moves forward",
		"x=%.2f" % pred_1s.x)

	# 位移应该小于 v0 * 1（因为有摩擦）
	_assert(pred_1s.x < 100.0, "Predict displacement < v0*t (friction slows it)",
		"x=%.2f" % pred_1s.x)

	# 位移应该大于停止距离（不完全停，但接近）
	var stop_dist := DribblePhysics.compute_stop_distance(100.0)
	_assert(pred_1s.x < stop_dist, "Predict at t=1s < stop distance (ball still moving)",
		"x=%.2f stop_dist=%.2f" % [pred_1s.x, stop_dist])

	# 解析解验证：x(t) = x0 + v0 * (f^t - 1) / ln(f)
	var f := DribblePhysics.GROUND_FRICTION_PER_SEC
	var expected_x := 100.0 * (pow(f, 1.0) - 1.0) / log(f)
	_assert(_approx(pred_1s.x, expected_x),
		"Predict matches analytical formula v0*(f^t-1)/ln(f)",
		"got=%.4f expected=%.4f" % [pred_1s.x, expected_x])

	# 长时间后位置趋近停止距离
	var pred_long := DribblePhysics.predict_ball_position(pos, vel, 10.0)
	_assert(_approx(pred_long.x, stop_dist, 1.0),
		"Predict at t=10s approaches stop distance",
		"x=%.2f stop_dist=%.2f" % [pred_long.x, stop_dist])

	# y 方向为 0 时不应有 y 位移
	_assert(_approx(pred_1s.y, 0.0), "Y-component stays zero when v_y=0",
		"y=%.4f" % pred_1s.y)

	# 对角线方向测试
	var vel_diag := Vector2(60.0, 80.0)
	var pred_diag := DribblePhysics.predict_ball_position(pos, vel_diag, 0.5)
	var ratio := pred_diag.x / 60.0
	var ratio_y := pred_diag.y / 80.0
	_assert(_approx(ratio, ratio_y, 0.001),
		"Diagonal prediction preserves direction ratio",
		"x_ratio=%.4f y_ratio=%.4f" % [ratio, ratio_y])

	print()

func test_touch_zone_length() -> void:
	print("-- Touch Zone Length Tests --")

	# 技术 0 应该返回最小值
	var len_0 := DribblePhysics.get_touch_zone_length(0.0)
	_assert(_approx(len_0, DribblePhysics.TOUCH_ZONE_LEN_MIN),
		"Tech 0 -> min touch zone length",
		"got=%.1f expected=%.1f" % [len_0, DribblePhysics.TOUCH_ZONE_LEN_MIN])

	# 技术 100 应该返回最大值
	var len_100 := DribblePhysics.get_touch_zone_length(100.0)
	_assert(_approx(len_100, DribblePhysics.TOUCH_ZONE_LEN_MAX),
		"Tech 100 -> max touch zone length",
		"got=%.1f expected=%.1f" % [len_100, DribblePhysics.TOUCH_ZONE_LEN_MAX])

	# 技术 50 应该在中间
	var len_50 := DribblePhysics.get_touch_zone_length(50.0)
	var expected_50 := lerp(DribblePhysics.TOUCH_ZONE_LEN_MIN, DribblePhysics.TOUCH_ZONE_LEN_MAX, 0.5)
	_assert(_approx(len_50, expected_50),
		"Tech 50 -> lerp midpoint",
		"got=%.1f expected=%.1f" % [len_50, expected_50])

	# 负值应该钳制到 0
	var len_neg := DribblePhysics.get_touch_zone_length(-10.0)
	_assert(len_neg == DribblePhysics.TOUCH_ZONE_LEN_MIN,
		"Negative tech clamped to min",
		"got=%.1f" % len_neg)

	# 超过 100 应该钳制到 100
	var len_over := DribblePhysics.get_touch_zone_length(200.0)
	_assert(len_over == DribblePhysics.TOUCH_ZONE_LEN_MAX,
		"Tech > 100 clamped to max",
		"got=%.1f" % len_over)

	print()

func test_max_control_distance() -> void:
	print("-- Max Control Distance Tests --")

	# 技术 0 应该返回最小值
	var dist_0 := DribblePhysics.get_max_control_distance(0.0)
	_assert(_approx(dist_0, DribblePhysics.MAX_CONTROL_DISTANCE_MIN),
		"Tech 0 -> min control distance",
		"got=%.1f expected=%.1f" % [dist_0, DribblePhysics.MAX_CONTROL_DISTANCE_MIN])

	# 技术 100 应该返回最大值
	var dist_100 := DribblePhysics.get_max_control_distance(100.0)
	_assert(_approx(dist_100, DribblePhysics.MAX_CONTROL_DISTANCE_MAX),
		"Tech 100 -> max control distance",
		"got=%.1f expected=%.1f" % [dist_100, DribblePhysics.MAX_CONTROL_DISTANCE_MAX])

	# 技术 50 在中间
	var dist_50 := DribblePhysics.get_max_control_distance(50.0)
	var expected_50 := lerp(DribblePhysics.MAX_CONTROL_DISTANCE_MIN, DribblePhysics.MAX_CONTROL_DISTANCE_MAX, 0.5)
	_assert(_approx(dist_50, expected_50),
		"Tech 50 -> lerp midpoint",
		"got=%.1f expected=%.1f" % [dist_50, expected_50])

	print()

func test_touch_impulse() -> void:
	print("-- Touch Impulse Tests --")

	# 静止球员不应触球
	var vel := Vector2(50.0, 0.0)
	var player_vel := Vector2.ZERO
	var result_idle := DribblePhysics.compute_touch_impulse(vel, player_vel, 100.0, 50.0)
	_assert(result_idle == vel,
		"Idle player returns unchanged velocity",
		"got=%s expected=%s" % [result_idle, vel])

	# 移动球员应使球速变化
	player_vel = Vector2(60.0, 0.0)
	var result := DribblePhysics.compute_touch_impulse(vel, player_vel, 100.0, 50.0)
	_assert(result != vel, "Moving player changes ball velocity",
		"old=%.1f new=%.1f" % [vel.x, result.x])

	# 推球方向与球员移动方向一致（同向时 y=0）
	_assert(abs(result.y) < 5.0, "Push direction roughly matches player direction",
		"result.y=%.4f" % result.y)

	# 球员速度为 1（边界值）不应触球
	player_vel = Vector2(0.5, 0.0)
	var result_slow := DribblePhysics.compute_touch_impulse(vel, player_vel, 100.0, 50.0)
	_assert(result_slow == vel, "Very slow player returns unchanged velocity")

	print()
