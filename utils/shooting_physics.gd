class_name ShootingPhysics
extends RefCounted

## Deterministic aiming and power helpers for the WE2000-style shot flow.
## The state classes own input/animation; this class only turns game context
## into values that can be tested headlessly.

const MAX_CHARGE_SECONDS := PitchConstants.PLAYER.SHOOT_MAX_CHARGE_SECONDS
const MIN_CHARGE_RATIO := PitchConstants.PLAYER.SHOOT_MIN_CHARGE_RATIO
const AIM_VERTICAL_RANGE := PitchConstants.PLAYER.SHOOT_AIM_VERTICAL_RANGE
const MIN_SHOT_SPEED := PitchConstants.PLAYER.SHOOT_MIN_SPEED
const MAX_SHOT_SPEED := PitchConstants.PLAYER.SHOOT_MAX_SPEED
const DISTANCE_REFERENCE := PitchConstants.PLAYER.SHOOT_DISTANCE_REFERENCE

static func charge_ratio(elapsed_seconds: float) -> float:
	return clampf(elapsed_seconds / MAX_CHARGE_SECONDS, 0.0, 1.0)

static func compute_aim_direction(
	origin: Vector2,
	heading: Vector2,
	goal_center: Vector2,
	input_direction: Vector2,
	shooting: float
) -> Vector2:
	var safe_heading := heading.normalized()
	if safe_heading.length_squared() < 0.01:
		safe_heading = Vector2.RIGHT
	var aim_strength := lerpf(0.65, 1.0, clampf(shooting / 100.0, 0.0, 1.0))
	var aim_offset := Vector2(0.0, clampf(input_direction.y, -1.0, 1.0) * AIM_VERTICAL_RANGE * aim_strength)
	var goal_direction := origin.direction_to(goal_center + aim_offset)
	if goal_direction.length_squared() < 0.01:
		goal_direction = safe_heading
	# The target is always the goal line; input only selects its vertical lane.
	# This prevents a directional key from accidentally firing away from goal.
	return goal_direction.normalized()

static func compute_shot_speed(
	player_power: float,
	shooting: float,
	charge: float,
	distance_to_goal: float
) -> float:
	var ratio := clampf(charge, MIN_CHARGE_RATIO, 1.0)
	var eased_charge := ease(ratio, 1.35)
	var attribute_factor := lerpf(0.78, 1.18, clampf(shooting / 100.0, 0.0, 1.0))
	var distance_factor := clampf(distance_to_goal / DISTANCE_REFERENCE, 0.75, 1.35)
	var speed := player_power * lerpf(0.55, 1.0, eased_charge) * attribute_factor * distance_factor
	return clampf(speed, MIN_SHOT_SPEED, MAX_SHOT_SPEED)

static func build_shot(
	origin: Vector2,
	heading: Vector2,
	goal_center: Vector2,
	input_direction: Vector2,
	player_power: float,
	shooting: float,
	charge: float
) -> Dictionary:
	var direction := compute_aim_direction(origin, heading, goal_center, input_direction, shooting)
	var speed := compute_shot_speed(player_power, shooting, charge, origin.distance_to(goal_center))
	return {"direction": direction, "power": speed, "charge": clampf(charge, 0.0, 1.0)}
