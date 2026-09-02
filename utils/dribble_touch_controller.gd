class_name DribbleTouchController
extends RefCounted

const DribblePhysicsScript := preload("res://utils/dribble_physics.gd")
const SeededRngScript := preload("res://utils/seeded_rng.gd")

var rng
var cooldown := 0.0
var tick := 0
var events: Array[Dictionary] = []

func _init(seed: int) -> void:
	rng = SeededRngScript.new(seed)

func first_touch(incoming_velocity: Vector2, control_direction: Vector2, technique: float) -> Vector2:
	return DribblePhysicsScript.compute_first_touch_velocity(
		incoming_velocity, control_direction, technique, rng.randf())

func advance(
	delta: float,
	ball_position: Vector2,
	player_position: Vector2,
	player_direction: Vector2,
	ball_velocity: Vector2,
	player_velocity: Vector2,
	player_max_speed: float,
	technique: float,
	mode: int,
	movement_intended: bool
) -> Dictionary:
	tick += 1
	cooldown = maxf(0.0, cooldown - delta)
	if cooldown > 0.0 or not movement_intended \
			or player_velocity.length() < DribblePhysicsScript.IDLE_SPEED_THRESHOLD:
		return {}
	if not DribblePhysicsScript.is_ball_in_touch_zone(
		ball_position, player_position, player_direction, technique, mode):
		return {}
	var velocity := DribblePhysicsScript.compute_touch_impulse(
		ball_velocity, player_velocity, player_max_speed, technique, mode, rng.randf())
	if velocity.dot(player_direction) <= ball_velocity.dot(player_direction):
		return {}
	cooldown = DribblePhysicsScript.get_min_touch_interval(technique, mode)
	var event := {"tick": tick, "velocity": velocity, "mode": mode}
	events.append(event)
	return event
