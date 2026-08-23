class_name DribbleDebugDraw
extends Node2D

## 带球调试可视化脚本
## 用法：作为 Node2D 附加到 Ball 节点（或场景中任意位置），
##       在 inspector 中设置 ball_ref 指向球节点。
## 绘制内容（仅在 DRIBBLING 状态且 enabled=true 时显示）：
##   1. 触球区（绿色半透明胶囊形）
##   2. 球的速度向量（黄色箭头）
##   3. 最大可控距离圈（白色虚线圆）
##   4. 球的运动轨迹点（可选，通过 show_trajectory 控制）

@export var ball_ref: Ball
@export var enabled := true
@export var show_touch_zone := true
@export var show_velocity_arrow := true
@export var show_control_circle := true
@export var show_trajectory := false

# 轨迹点历史长度（帧数）
const MAX_TRAJECTORY_POINTS := 30
var _trajectory_points: Array[Vector2] = []

# ---- 颜色配置 ----
const COLOR_TOUCH_ZONE := Color(0.3, 1.0, 0.3, 0.3)
const COLOR_TOUCH_ZONE_BORDER := Color(0.3, 1.0, 0.3, 0.8)
const COLOR_VELOCITY_ARROW := Color(1.0, 0.8, 0.0, 0.9)
const COLOR_CONTROL_CIRCLE := Color(1.0, 1.0, 1.0, 0.4)
const COLOR_TRAJECTORY := Color(0.5, 0.5, 1.0, 0.7)

func _process(_delta: float) -> void:
	# 记录轨迹点
	if show_trajectory and enabled and ball_ref:
		if _is_ball_dribbling():
			_trajectory_points.append(ball_ref.position)
			if _trajectory_points.size() > MAX_TRAJECTORY_POINTS:
				_trajectory_points.pop_front()
		elif not _is_ball_dribbling():
			_trajectory_points.clear()

	queue_redraw()

func _draw() -> void:
	if not enabled or not ball_ref:
		return
	if not _is_ball_dribbling():
		return

	var carrier := ball_ref.carrier
	if not carrier or not is_instance_valid(carrier):
		return

	var technique := carrier.technique
	var player_dir := _get_player_direction(carrier)

	# 1. 触球区
	if show_touch_zone:
		_draw_touch_zone(carrier.position, player_dir, technique)

	# 2. 速度向量箭头
	if show_velocity_arrow:
		_draw_velocity_arrow(ball_ref.position, ball_ref.velocity)

	# 3. 最大可控距离圈
	if show_control_circle:
		_draw_control_circle(carrier.position, technique)

	# 4. 轨迹点
	if show_trajectory:
		_draw_trajectory()

# ---- 判断球是否处于 DRIBBLING 状态 ----
func _is_ball_dribbling() -> bool:
	if not ball_ref or not is_instance_valid(ball_ref):
		return false
	return ball_ref.current_state is BallStateDribbling

# ---- 获取球员方向（与 BallStateDribbling 保持一致） ----
func _get_player_direction(player: Player) -> Vector2:
	if player.velocity.length() > 5.0:
		return player.velocity.normalized()
	return player.heading

# ---- 绘制触球区（胶囊形 = 矩形 + 两个半圆封头） ----
func _draw_touch_zone(player_pos: Vector2, player_dir: Vector2, technique: float) -> void:
	if player_dir.length() < 0.001:
		return

	var zone_len := DribblePhysics.get_touch_zone_length(technique)
	var zone_width := DribblePhysics.TOUCH_ZONE_WIDTH
	var zone_start := DribblePhysics.TOUCH_ZONE_FRONT_OFFSET
	var zone_end := zone_start + zone_len

	var dir_norm := player_dir.normalized()
	var perp := dir_norm.rotated(PI / 2.0)

	# 本地坐标系原点 = player_pos，+x = dir_norm，+y = perp
	# 触球区 = [zone_start, zone_end] × [-zone_width/2, zone_width/2]

	# 矩形的四个角（球员本地坐标系）
	var tl := player_pos + dir_norm * zone_start + perp * (-zone_width / 2.0)
	var tr := player_pos + dir_norm * zone_start + perp * (zone_width / 2.0)
	var br := player_pos + dir_norm * zone_end + perp * (zone_width / 2.0)
	var bl := player_pos + dir_norm * zone_end + perp * (-zone_width / 2.0)

	# 填充矩形主体
	draw_polygon([tl, tr, br, bl], [COLOR_TOUCH_ZONE])
	# 边框
	draw_line(tl, tr, COLOR_TOUCH_ZONE_BORDER, 1.5)
	draw_line(tr, br, COLOR_TOUCH_ZONE_BORDER, 1.5)
	draw_line(br, bl, COLOR_TOUCH_ZONE_BORDER, 1.5)
	draw_line(bl, tl, COLOR_TOUCH_ZONE_BORDER, 1.5)

	# 前端和后端半圆封头（可选，更精确的触球区形状）
	# 前端封头圆心 = zone_start 处，半径 = zone_width/2
	var front_center := player_pos + dir_norm * zone_start
	var back_center := player_pos + dir_norm * zone_end
	var radius := zone_width / 2.0
	draw_arc(front_center, radius, dir_norm.angle() + PI / 2.0, dir_norm.angle() + 3.0 * PI / 2.0, 16, COLOR_TOUCH_ZONE_BORDER, 1.5)
	draw_arc(back_center, radius, dir_norm.angle() - PI / 2.0, dir_norm.angle() + PI / 2.0, 16, COLOR_TOUCH_ZONE_BORDER, 1.5)

# ---- 绘制速度向量箭头 ----
func _draw_velocity_arrow(ball_pos: Vector2, velocity: Vector2) -> void:
	if velocity.length() < 1.0:
		return  # 速度太小不画

	var arrow_len: float = min(velocity.length() * 0.5, 60.0)  # 限制最大长度
	var arrow_end := ball_pos + velocity.normalized() * arrow_len

	# 主线
	draw_line(ball_pos, arrow_end, COLOR_VELOCITY_ARROW, 2.0)

	# 箭头头部
	var arrow_dir := velocity.normalized()
	var arrow_side1 := arrow_end - arrow_dir.rotated(deg_to_rad(150)) * 8.0
	var arrow_side2 := arrow_end - arrow_dir.rotated(deg_to_rad(-150)) * 8.0
	draw_line(arrow_end, arrow_side1, COLOR_VELOCITY_ARROW, 2.0)
	draw_line(arrow_end, arrow_side2, COLOR_VELOCITY_ARROW, 2.0)

# ---- 绘制最大可控距离圈（虚线圆） ----
func _draw_control_circle(player_pos: Vector2, technique: float) -> void:
	var max_control := DribblePhysics.get_max_control_distance(technique)
	# 虚线圆：每隔一段画一段弧
	const SEGMENT_COUNT := 32
	const DASH_RATIO := 0.5  # 画一半留一半
	for i in range(SEGMENT_COUNT):
		if i % 2 == 0:  # 偶数段画，奇数段跳过
			var angle_start := (i / float(SEGMENT_COUNT)) * TAU
			var angle_end := ((i + DASH_RATIO) / float(SEGMENT_COUNT)) * TAU
			draw_arc(player_pos, max_control, angle_start, angle_end, 8, COLOR_CONTROL_CIRCLE, 1.5)

# ---- 绘制球的运动轨迹点 ----
func _draw_trajectory() -> void:
	if _trajectory_points.size() < 2:
		return
	for i in range(_trajectory_points.size() - 1):
		var p1 := _trajectory_points[i]
		var p2 := _trajectory_points[i + 1]
		# 轨迹点越老越淡
		var alpha := (i / float(_trajectory_points.size())) * COLOR_TRAJECTORY.a
		var color := Color(COLOR_TRAJECTORY.r, COLOR_TRAJECTORY.g, COLOR_TRAJECTORY.b, alpha)
		draw_line(p1, p2, color, 1.5)
