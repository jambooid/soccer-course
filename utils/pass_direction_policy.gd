class_name PassDirectionPolicy
extends RefCounted

static func resolve(input_direction: Vector2, fallback_direction: Vector2) -> Vector2:
	if input_direction.length_squared() > 0.01:
		return input_direction.normalized()
	return fallback_direction.normalized()
