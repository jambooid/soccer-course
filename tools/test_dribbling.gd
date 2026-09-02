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
	var result := run_suite()
	get_tree().quit(0 if result.failed == 0 else 1)

func run_suite() -> Dictionary:
	_passed = 0
	_failed = 0
	print("=== Dribble Physics Tests ===")
	print()

	test_friction()
	test_touch_zone()
	test_stop_distance()
	test_predict_position()
	test_touch_zone_length()
	test_max_control_distance()
	test_touch_impulse()
	test_mode_touch_zone()
	test_mode_control_distance()
	test_mode_impulse()
	test_speed_penalty_within_mode()
	test_first_touch_quality()
	test_speed_penalty()
	test_mode_min_interval()

	print()
	print("========================================")
	print("Results: %d passed, %d failed" % [_passed, _failed])
	if _failed == 0:
		print("All tests passed!")
	else:
		print("Some tests FAILED.")
	print("========================================")

	return {"passed": _passed, "failed": _failed}

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
	var dist_100 := DribblePhysics.compute_stop_distance(Vector2.RIGHT * 100.0)
	_assert(dist_100 > 0, "Stop distance is positive for v=100",
		"dist=%.2f" % dist_100)

	# 零速度停止距离为 0
	var dist_0 := DribblePhysics.compute_stop_distance(Vector2.ZERO)
	_assert(dist_0 == 0.0, "Stop distance is zero for v=0",
		"dist=%.2f" % dist_0)

	# 速度加倍，停止距离也应该加倍（线性关系）
	var dist_50 := DribblePhysics.compute_stop_distance(Vector2.RIGHT * 50.0)
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
	print("    Stop distance at 80px/s  = %.2fpx" % DribblePhysics.compute_stop_distance(Vector2.RIGHT * 80.0))
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
	var stop_dist := DribblePhysics.compute_stop_distance(Vector2.RIGHT * 100.0)
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

	# 技术 50 应该在中间（注意 normalize_technique 的范围是 30-98）
	var len_50 := DribblePhysics.get_touch_zone_length(50.0)
	var t_norm_50: float = clamp((50.0 - DribblePhysics.TECHNIQUE_MIN) / (DribblePhysics.TECHNIQUE_MAX - DribblePhysics.TECHNIQUE_MIN), 0.0, 1.0)
	var expected_50: float = lerp(DribblePhysics.TOUCH_ZONE_LEN_MIN, DribblePhysics.TOUCH_ZONE_LEN_MAX, t_norm_50)
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

	# 技术 50 在中间（注意 normalize_technique 的范围是 30-98）
	var dist_50 := DribblePhysics.get_max_control_distance(50.0)
	var t_norm_50b: float = clamp((50.0 - DribblePhysics.TECHNIQUE_MIN) / (DribblePhysics.TECHNIQUE_MAX - DribblePhysics.TECHNIQUE_MIN), 0.0, 1.0)
	var expected_50b: float = lerp(DribblePhysics.MAX_CONTROL_DISTANCE_MIN, DribblePhysics.MAX_CONTROL_DISTANCE_MAX, t_norm_50b)
	_assert(_approx(dist_50, expected_50b),
		"Tech 50 -> lerp midpoint",
		"got=%.1f expected=%.1f" % [dist_50, expected_50b])

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

	# 推球方向与球员移动方向一致（同向时 y=0，有随机偏差和速度惩罚）
	_assert(abs(result.y) < 15.0, "Push direction roughly matches player direction",
		"result.y=%.4f" % result.y)

	# 球员速度为 1（边界值）不应触球
	player_vel = Vector2(0.5, 0.0)
	var result_slow := DribblePhysics.compute_touch_impulse(vel, player_vel, 100.0, 50.0)
	_assert(result_slow == vel, "Very slow player returns unchanged velocity")

	print()

func test_mode_touch_zone() -> void:
	print("-- Mode: Touch Zone Tests --")

	var tech := 64.0
	var jog_len := DribblePhysics.get_touch_zone_length(tech, DribblePhysics.Mode.JOG)
	var sprint_len := DribblePhysics.get_touch_zone_length(tech, DribblePhysics.Mode.SPRINT)

	# SPRINT 触球区比 JOG 长
	_assert(sprint_len > jog_len, "SPRINT touch zone longer than JOG",
		"jog=%.1f sprint=%.1f" % [jog_len, sprint_len])

	# SPRINT 倍率约为 1.3
	var ratio := sprint_len / jog_len
	_assert(_approx(ratio, 1.3, 0.05), "SPRINT/JOG touch zone ratio ~ 1.3",
		"ratio=%.2f" % ratio)

	# is_ball_in_touch_zone 的 mode 参数生效
	var player_pos := Vector2.ZERO
	var player_dir := Vector2.RIGHT
	# 在 JOG 区外但在 SPRINT 区内的点
	var just_outside_jog := Vector2(DribblePhysics.TOUCH_ZONE_FRONT_OFFSET + jog_len + 2.0, 0.0)
	_assert(not DribblePhysics.is_ball_in_touch_zone(just_outside_jog, player_pos, player_dir, tech, DribblePhysics.Mode.JOG),
		"Point outside JOG zone returns false for JOG mode")
	# 只有当 sprint 区长足够包含这个点时才测
	if sprint_len > jog_len + 2.0:
		_assert(DribblePhysics.is_ball_in_touch_zone(just_outside_jog, player_pos, player_dir, tech, DribblePhysics.Mode.SPRINT),
			"Point outside JOG but inside SPRINT zone returns true for SPRINT mode")

	print()

func test_mode_control_distance() -> void:
	print("-- Mode: Control Distance Tests --")

	var tech := 64.0
	var jog_dist := DribblePhysics.get_max_control_distance(tech, DribblePhysics.Mode.JOG)
	var sprint_dist := DribblePhysics.get_max_control_distance(tech, DribblePhysics.Mode.SPRINT)

	_assert(sprint_dist > jog_dist, "SPRINT control distance > JOG",
		"jog=%.1f sprint=%.1f" % [jog_dist, sprint_dist])

	var ratio := sprint_dist / jog_dist
	_assert(_approx(ratio, 1.5, 0.1), "SPRINT/JOG control distance ratio ~ 1.5",
		"ratio=%.2f" % ratio)

	print()

func test_mode_impulse() -> void:
	print("-- Mode: Touch Impulse Tests --")

	var ball_vel := Vector2(40.0, 0.0)
	var player_vel := Vector2(60.0, 0.0)
	var max_speed := 80.0
	var tech := 64.0

	var jog_result := DribblePhysics.compute_touch_impulse(ball_vel, player_vel, max_speed, tech, DribblePhysics.Mode.JOG)
	var sprint_result := DribblePhysics.compute_touch_impulse(ball_vel, player_vel, max_speed, tech, DribblePhysics.Mode.SPRINT)

	# SPRINT 推球速度更快（冲量更大）
	_assert(sprint_result.length() > jog_result.length(), "SPRINT impulse > JOG impulse",
		"jog=%.1f sprint=%.1f" % [jog_result.length(), sprint_result.length()])

	print()

func test_speed_penalty_within_mode() -> void:
	print("-- Speed Penalty Within Mode Tests --")

	# 验证：在同一模式（JOG）下，高速比低速有更大的方向偏差（速度惩罚生效）
	var ball_vel := Vector2(40.0, 0.0)
	var max_speed := 100.0
	var tech := 64.0
	var iterations := 200

	# 低速：player_speed / max_speed = 0.2
	var low_speed_vel := Vector2(20.0, 0.0)
	# 高速：player_speed / max_speed = 0.9
	var high_speed_vel := Vector2(90.0, 0.0)

	var low_speed_avg_abs_y := 0.0
	var high_speed_avg_abs_y := 0.0

	for i in range(iterations):
		var low_result := DribblePhysics.compute_touch_impulse(
			ball_vel, low_speed_vel, max_speed, tech, DribblePhysics.Mode.JOG)
		low_speed_avg_abs_y += abs(low_result.y)

		var high_result := DribblePhysics.compute_touch_impulse(
			ball_vel, high_speed_vel, max_speed, tech, DribblePhysics.Mode.JOG)
		high_speed_avg_abs_y += abs(high_result.y)

	low_speed_avg_abs_y /= float(iterations)
	high_speed_avg_abs_y /= float(iterations)

	_assert(high_speed_avg_abs_y > low_speed_avg_abs_y,
		"High speed has greater avg |y| deviation than low speed (speed penalty)",
		"low_speed_avg_abs_y=%.4f high_speed_avg_abs_y=%.4f" % [low_speed_avg_abs_y, high_speed_avg_abs_y])

	print("    Low speed avg |y|: %.4f" % low_speed_avg_abs_y)
	print("    High speed avg |y|: %.4f" % high_speed_avg_abs_y)
	print()

func test_first_touch_quality() -> void:
	print("-- First Touch Quality Tests --")

	var incoming := Vector2(80.0, 0.0)
	var control_dir := Vector2.RIGHT

	# 高技术停球慢（吸收多）
	var high_tech := DribblePhysics.compute_first_touch_velocity(incoming, control_dir, 90.0)
	# 低技术停球快（吸收少，球弹远）
	var low_tech := DribblePhysics.compute_first_touch_velocity(incoming, control_dir, 40.0)

	_assert(high_tech.length() < low_tech.length(),
		"High technique = slower first touch (better control)",
		"high_tech=%.1f low_tech=%.1f" % [high_tech.length(), low_tech.length()])

	# 高技术停球速应明显低于入射速度
	_assert(high_tech.length() < incoming.length() * 0.5,
		"High technique absorbs > 50% of incoming speed",
		"incoming=%.1f result=%.1f" % [incoming.length(), high_tech.length()])

	# 低技术也应吸收一部分（不可能全反弹）
	_assert(low_tech.length() < incoming.length(),
		"Low technique still absorbs some speed",
		"incoming=%.1f result=%.1f" % [incoming.length(), low_tech.length()])

	print()


func test_speed_penalty() -> void:
	print("-- Speed Penalty Tests --")

	var ball_vel := Vector2(30.0, 0.0)
	var max_speed := 100.0
	var tech := 64.0

	# 低速 vs 高速：高速时触球精度更低（多次运行统计 y 偏差更大）
	var low_speed_vel := Vector2(20.0, 0.0)
	var high_speed_vel := Vector2(90.0, 0.0)

	# 速度为 0 时不触球（已有测试覆盖），这里验证速度影响效率
	# 高速时球速提升应该更小（效率低）
	var low_result := DribblePhysics.compute_touch_impulse(ball_vel, low_speed_vel, max_speed, tech)
	var high_result := DribblePhysics.compute_touch_impulse(ball_vel, high_speed_vel, max_speed, tech)

	# 高速推球速度肯定更快（因为 player 速度快），但验证函数不崩溃
	_assert(high_result.length() > low_result.length(),
		"High speed push results in faster ball",
		"low=%.1f high=%.1f" % [low_result.length(), high_result.length()])

	print()


func test_mode_min_interval() -> void:
	print("-- Mode: Min Touch Interval Tests --")

	var tech := 64.0
	var jog_interval := DribblePhysics.get_min_touch_interval(tech, DribblePhysics.Mode.JOG)
	var sprint_interval := DribblePhysics.get_min_touch_interval(tech, DribblePhysics.Mode.SPRINT)

	_assert(sprint_interval > jog_interval, "SPRINT min interval > JOG",
		"jog=%.3f sprint=%.3f" % [jog_interval, sprint_interval])

	# 验证倍率 ~ 1.875（0.08 → 0.15）
	var ratio := sprint_interval / jog_interval
	_assert(_approx(ratio, 1.875, 0.05), "SPRINT/JOG interval ratio ~ 1.875",
		"ratio=%.3f" % ratio)

	print()
