class_name Presentation3D
extends RefCounted

## Maps deterministic match coordinates (x/y) to a 3D pitch (X/Z).
## Ball height remains the Y component and never changes the ground point.
const DEFAULT_SCALE := 0.1

static func to_world(position: Vector2, height: float = 0.0, scale: float = 1.0) -> Vector3:
	var safe_scale := maxf(scale, 0.0001)
	return Vector3(position.x * safe_scale, height * safe_scale, position.y * safe_scale)

static func from_world(position: Vector3, scale: float = 1.0) -> Vector2:
	var safe_scale := maxf(scale, 0.0001)
	return Vector2(position.x / safe_scale, position.z / safe_scale)

static func to_world_3d(position: Vector3, scale: float = DEFAULT_SCALE) -> Vector3:
	return position * maxf(scale, 0.0001)

static func from_world_3d(position: Vector3, scale: float = DEFAULT_SCALE) -> Vector3:
	return position / maxf(scale, 0.0001)
