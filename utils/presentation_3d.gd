class_name Presentation3D
extends RefCounted

## Maps deterministic match coordinates (x/y) to a 3D pitch (X/Z).
## Ball height remains the Y component and never changes the ground point.

static func to_world(position: Vector2, height: float = 0.0, scale: float = 1.0) -> Vector3:
	return Vector3(position.x * scale, height * scale, position.y * scale)

static func from_world(position: Vector3, scale: float = 1.0) -> Vector2:
	var safe_scale := maxf(scale, 0.0001)
	return Vector2(position.x / safe_scale, position.z / safe_scale)
