class_name MatchHUD
extends CanvasLayer

const Flow := preload("res://utils/match_flow.gd")

var score_label: Label
var clock_label: Label
var event_label: Label
var player_label: Label
var radar: Control
var power_bar: ProgressBar

func _ready() -> void:
	var top_bar := ColorRect.new()
	top_bar.position = Vector2(176, 4)
	top_bar.size = Vector2(208, 30)
	top_bar.color = Color(0.02, 0.05, 0.10, 0.82)
	add_child(top_bar)
	score_label = _label(14, HORIZONTAL_ALIGNMENT_CENTER)
	score_label.position = Vector2(178, 6)
	score_label.size = Vector2(204, 18)
	add_child(score_label)
	clock_label = _label(11, HORIZONTAL_ALIGNMENT_CENTER)
	clock_label.position = Vector2(178, 21)
	clock_label.size = Vector2(204, 12)
	add_child(clock_label)
	player_label = _label(11, HORIZONTAL_ALIGNMENT_LEFT)
	player_label.position = Vector2(8, 330)
	player_label.size = Vector2(170, 18)
	add_child(player_label)
	event_label = _label(18, HORIZONTAL_ALIGNMENT_CENTER)
	event_label.position = Vector2(160, 285)
	event_label.size = Vector2(240, 26)
	add_child(event_label)
	radar = RadarView.new()
	radar.position = Vector2(452, 286)
	radar.size = Vector2(100, 66)
	add_child(radar)
	power_bar = ProgressBar.new()
	power_bar.position = Vector2(8, 350)
	power_bar.size = Vector2(164, 5)
	power_bar.show_percentage = false
	power_bar.modulate = Color(1.0, 0.82, 0.24)
	power_bar.visible = false
	add_child(power_bar)

func update_from_snapshot(snapshot: Dictionary, shot_charging: bool, charge: float, charge_max: float) -> void:
	var half_label := "1st" if int(snapshot.get("half", 1)) == 1 else "2nd"
	score_label.text = "BLUE  %d - %d  RED" % [int(snapshot.get("score_home", 0)), int(snapshot.get("score_away", 0))]
	var seconds := ceili(float(snapshot.get("clock", 0.0)))
	clock_label.text = "%s  %d:%02d" % [half_label, seconds / 60, seconds % 60]
	var selected := int(snapshot.get("selected_player_id", -1))
	player_label.text = "P%d  %s" % [selected + 1, "FW" if selected >= 8 else "MF"] if selected >= 0 else ""
	event_label.text = str(snapshot.get("event_label", ""))
	power_bar.max_value = maxf(charge_max, 0.001)
	power_bar.value = charge
	power_bar.visible = shot_charging
	radar.players = snapshot.get("radar", []).duplicate(true)
	radar.ball = snapshot.get("ball", {}).get("position", Vector3.ZERO)
	radar.queue_redraw()

func _label(font_size: int, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

class RadarView extends Control:
	var players: Array = []
	var ball := Vector3.ZERO

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.16, 0.09, 0.82), true)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.78, 0.86, 0.78, 0.75), false, 1.0)
		draw_line(Vector2(size.x * 0.5, 0), Vector2(size.x * 0.5, size.y), Color(0.78, 0.86, 0.78, 0.55), 1.0)
		for player: Dictionary in players:
			var position := player.get("position", Vector3.ZERO) as Vector3
			var point := Vector2(position.x / 85.0 * size.x, position.z / 36.0 * size.y)
			draw_circle(point, 2.0, Color("3f7fe8") if bool(player.get("home", false)) else Color("e0524d"))
		var ball_point := Vector2(ball.x / 85.0 * size.x, ball.z / 36.0 * size.y)
		draw_circle(ball_point, 1.7, Color("f4dd4a"))
