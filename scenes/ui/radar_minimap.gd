class_name RadarMinimap
extends Control

## 雷达小地图 — 显示全场球员和球的位置
## 位于屏幕左下角，每 3 帧重绘一次

const UPDATE_FRAME_INTERVAL := 3
const PITCH_MIN := Vector2(0, 0)
const PITCH_MAX := Vector2(850, 360)

const COLOR_PITCH_BG := Color(0.1, 0.25, 0.08, 0.9)
const COLOR_PITCH_LINE := Color(0.9, 0.9, 0.9, 0.6)
const COLOR_HOME := Color(0.95, 0.95, 0.3, 1.0)
const COLOR_AWAY := Color(0.85, 0.3, 0.3, 1.0)
const COLOR_BALL := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_PLAYER_RING := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_OFFSIDE_LINE := Color(1.0, 0.3, 0.3, 0.5)

const PLAYER_DOT_RADIUS := 1.5
const BALL_DOT_RADIUS := 1.0
const RING_RADIUS := 3.5

var _frame_count := 0
var _actors_container: Node2D = null
var _home_country := ""
var _away_country := ""

var show_offside_line := false
var offside_line_x_home := 0.0
var offside_line_x_away := 0.0


func setup(actors_container: Node2D, home_country: String, away_country: String) -> void:
	_actors_container = actors_container
	_home_country = home_country
	_away_country = away_country
	queue_redraw()


func _process(_delta: float) -> void:
	_frame_count += 1
	if _frame_count % UPDATE_FRAME_INTERVAL == 0:
		queue_redraw()


func _draw() -> void:
	if _actors_container == null:
		return

	var radar_size := size
	var pitch_size := PITCH_MAX - PITCH_MIN
	var scale_x := radar_size.x / pitch_size.x
	var scale_y := radar_size.y / pitch_size.y

	# --- 球场背景 ---
	draw_rect(Rect2(Vector2.ZERO, radar_size), COLOR_PITCH_BG)

	# --- 球场边线 ---
	draw_rect(Rect2(Vector2.ZERO, radar_size), COLOR_PITCH_LINE, false, 1.0)

	# --- 中线 ---
	var mid_x := radar_size.x * 0.5
	draw_line(Vector2(mid_x, 0), Vector2(mid_x, radar_size.y), COLOR_PITCH_LINE, 1.0)

	# --- 中圈 ---
	draw_arc(Vector2(mid_x, radar_size.y * 0.5), min(radar_size.x, radar_size.y) * 0.12,
			0.0, TAU, 16, COLOR_PITCH_LINE, 1.0)

	# --- 越位线（可选）---
	if show_offside_line:
		if offside_line_x_home > 0:
			var ox := (offside_line_x_home - PITCH_MIN.x) * scale_x
			draw_line(Vector2(ox, 0), Vector2(ox, radar_size.y), COLOR_OFFSIDE_LINE, 1.0)
		if offside_line_x_away > 0:
			var ox := (offside_line_x_away - PITCH_MIN.x) * scale_x
			draw_line(Vector2(ox, 0), Vector2(ox, radar_size.y), COLOR_OFFSIDE_LINE, 1.0)

	# --- 球员 ---
	var home_squad := _actors_container.get("squad_home") as Array[Player]
	var away_squad := _actors_container.get("squad_away") as Array[Player]
	var ball := _actors_container.get("ball") as Ball

	for player in home_squad:
		if is_instance_valid(player):
			var pos := _world_to_radar(player.global_position, radar_size, scale_x, scale_y)
			_draw_player_dot(pos, COLOR_HOME, player)

	for player in away_squad:
		if is_instance_valid(player):
			var pos := _world_to_radar(player.global_position, radar_size, scale_x, scale_y)
			_draw_player_dot(pos, COLOR_AWAY, player)

	# --- 球 ---
	if is_instance_valid(ball):
		var ball_pos := _world_to_radar(ball.global_position, radar_size, scale_x, scale_y)
		draw_circle(ball_pos, BALL_DOT_RADIUS, COLOR_BALL)


func _world_to_radar(world_pos: Vector2, radar_size: Vector2, sx: float, sy: float) -> Vector2:
	## 世界坐标 → 雷达坐标
	var clamped := Vector2(
		clamp(world_pos.x, PITCH_MIN.x, PITCH_MAX.x),
		clamp(world_pos.y, PITCH_MIN.y, PITCH_MAX.y)
	)
	return Vector2(
		(clamped.x - PITCH_MIN.x) * sx,
		(clamped.y - PITCH_MIN.y) * sy
	)


func _draw_player_dot(pos: Vector2, team_color: Color, player: Player) -> void:
	## 绘制球员点，人类控制的球员加白圈
	draw_circle(pos, PLAYER_DOT_RADIUS, team_color)

	if player.control_scheme != Player.ControlScheme.CPU:
		# 用环形线高亮当前控制球员
		draw_arc(pos, RING_RADIUS, 0.0, TAU, 12, COLOR_PLAYER_RING, 1.0)
