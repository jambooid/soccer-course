class_name PitchCoordinate3D
extends RefCounted

## Canonical coordinate contract for the 3D match.
## Gameplay and rendering both use metres: X is goal-to-goal, Y is height,
## and Z is the touchline-to-touchline axis. The old Vector2 API maps to X/Z.

const WORLD_SCALE := PitchConstants.WORLD_SCALE
const PITCH_SIZE := Vector3(PitchConstants.WORLD_PITCH_SIZE.x, 0.0,
	PitchConstants.WORLD_PITCH_SIZE.y)
const HALF_PITCH := Vector3(PITCH_SIZE.x * 0.5, 0.0, PITCH_SIZE.z * 0.5)
const GROUND_MIN := Vector2.ZERO
const GROUND_MAX := Vector2(PITCH_SIZE.x, PITCH_SIZE.z)
const GOAL_HALF_WIDTH := 5.2

static func to_world(ground: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(ground.x, height, ground.y)

static func from_world(world: Vector3) -> Vector2:
	return Vector2(world.x, world.z)

static func clamp_ground(ground: Vector2, margin: float = 0.0) -> Vector2:
	var safe_margin := maxf(margin, 0.0)
	return Vector2(clampf(ground.x, safe_margin, PITCH_SIZE.x - safe_margin),
		clampf(ground.y, safe_margin, PITCH_SIZE.z - safe_margin))

static func is_inside_pitch(ground: Vector2, margin: float = 0.0) -> bool:
	var safe_margin := maxf(margin, 0.0)
	return ground.x >= safe_margin and ground.x <= PITCH_SIZE.x - safe_margin \
		and ground.y >= safe_margin and ground.y <= PITCH_SIZE.z - safe_margin

static func in_goal_mouth(ground: Vector2) -> bool:
	return absf(ground.y - PITCH_SIZE.z * 0.5) <= GOAL_HALF_WIDTH

static func camera_target(ground: Vector2, margin := Vector2(10.0, 7.0)) -> Vector2:
	return Vector2(clampf(ground.x, margin.x, PITCH_SIZE.x - margin.x),
		clampf(ground.y, margin.y, PITCH_SIZE.z - margin.y))
