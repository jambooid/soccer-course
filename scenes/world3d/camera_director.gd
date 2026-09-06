class_name MatchCameraDirector
extends RefCounted

const Flow := preload("res://utils/match_flow.gd")

enum Shot { BROADCAST, GOAL_FOCUS, REPLAY, SET_PIECE }

var shot := Shot.BROADCAST
var hold_timer := 0.0
var focus_position := Vector3.ZERO

func consume_event(event) -> void:
	match event.name:
		"goal":
			shot = Shot.GOAL_FOCUS
			hold_timer = 0.8
			focus_position = event.payload.get("position", Vector3.ZERO) as Vector3
		"restart":
			shot = Shot.SET_PIECE
			hold_timer = 0.8
			focus_position = event.payload.get("position", Vector3.ZERO) as Vector3
		"full_time":
			shot = Shot.GOAL_FOCUS
			hold_timer = 1.2

func set_replay(active: bool) -> void:
	if active:
		shot = Shot.REPLAY
		hold_timer = INF
	elif shot == Shot.REPLAY:
		shot = Shot.BROADCAST
		hold_timer = 0.0

func advance(delta: float) -> void:
	if hold_timer == INF:
		return
	hold_timer = maxf(hold_timer - maxf(delta, 0.0), 0.0)
	if hold_timer <= 0.0 and shot != Shot.BROADCAST:
		shot = Shot.BROADCAST

func focus_override(default_focus: Vector3) -> Vector3:
	if shot == Shot.BROADCAST or shot == Shot.REPLAY:
		return default_focus
	return focus_position if not focus_position.is_zero_approx() else default_focus
