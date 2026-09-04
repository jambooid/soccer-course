class_name PitchCoordinate3D
extends RefCounted

## Canonical match coordinates are world coordinates: X runs goal-to-goal,
## Y is height, and Z runs touchline-to-touchline. No simulation projection is
## maintained alongside this representation.

const WORLD_SCALE := PitchConstants.WORLD_SCALE
const PITCH_SIZE := PitchConstants.WORLD_PITCH_SIZE
const HALF_PITCH := Vector3(PITCH_SIZE.x * 0.5, 0.0, PITCH_SIZE.z * 0.5)
const GOAL_HALF_WIDTH := 5.2

static func ground(position: Vector3) -> Vector3:
	return Vector3(position.x, 0.0, position.z)

static func clamp_pitch(position: Vector3, margin: float = 0.0) -> Vector3:
	var safe_margin := maxf(margin, 0.0)
	return Vector3(clampf(position.x, safe_margin, PITCH_SIZE.x - safe_margin),
		position.y, clampf(position.z, safe_margin, PITCH_SIZE.z - safe_margin))

static func is_inside_pitch(position: Vector3, margin: float = 0.0) -> bool:
	var safe_margin := maxf(margin, 0.0)
	return position.x >= safe_margin and position.x <= PITCH_SIZE.x - safe_margin \
		and position.z >= safe_margin and position.z <= PITCH_SIZE.z - safe_margin

static func in_goal_mouth(position: Vector3) -> bool:
	return absf(position.z - PITCH_SIZE.z * 0.5) <= GOAL_HALF_WIDTH

static func camera_target(position: Vector3, margin := Vector3(10.0, 0.0, 7.0)) -> Vector3:
	return Vector3(clampf(position.x, margin.x, PITCH_SIZE.x - margin.x), 0.0,
		clampf(position.z, margin.z, PITCH_SIZE.z - margin.z))
