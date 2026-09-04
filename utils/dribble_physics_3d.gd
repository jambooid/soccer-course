class_name DribblePhysics3D
extends RefCounted

const Coordinate3D := preload("res://utils/pitch_coordinate_3d.gd")

## Small, deterministic helpers for WE/PES-style touch-and-run dribbling.
## The ball remains independent between touches; these functions only describe
## the next foot contact.
enum Mode { JOG, SPRINT }

const TOUCH_INTERVAL_JOG := 0.30
const TOUCH_INTERVAL_SPRINT := 0.58
const CONTROL_DISTANCE_JOG := 1.35
const CONTROL_DISTANCE_SPRINT := 2.30
const TOUCH_OFFSET_JOG := 0.62
const TOUCH_OFFSET_SPRINT := 0.82
const JOG_PUSH_MULTIPLIER := 1.08
const SPRINT_PUSH_MULTIPLIER := 1.30
const GROUND_FRICTION_PER_SECOND := 0.28

static func technique_normalized(technique: float) -> float:
	return clampf((technique - 30.0) / 68.0, 0.0, 1.0)

static func touch_interval(technique: float, mode: int) -> float:
	var quality := technique_normalized(technique)
	var base := TOUCH_INTERVAL_SPRINT if mode == Mode.SPRINT else TOUCH_INTERVAL_JOG
	# Better technique lets the player take contacts slightly earlier.
	return lerpf(base * 1.08, base * 0.86, quality)

static func control_distance(technique: float, mode: int) -> float:
	var quality := technique_normalized(technique)
	var base := CONTROL_DISTANCE_SPRINT if mode == Mode.SPRINT else CONTROL_DISTANCE_JOG
	return lerpf(base * 0.9, base, quality)

static func touch_offset(technique: float, mode: int) -> float:
	var quality := technique_normalized(technique)
	var base := TOUCH_OFFSET_SPRINT if mode == Mode.SPRINT else TOUCH_OFFSET_JOG
	return lerpf(base * 0.94, base, quality)

static func touch_velocity(current_velocity: Vector3, player_velocity: Vector3,
		facing: Vector3, technique: float, mode: int) -> Vector3:
	var movement := Coordinate3D.ground(player_velocity)
	var speed := movement.length()
	var direction := movement.normalized() if speed > 0.08 else Coordinate3D.ground(facing).normalized()
	if direction.is_zero_approx():
		direction = Vector3.RIGHT
	var quality := technique_normalized(technique)
	var multiplier := SPRINT_PUSH_MULTIPLIER if mode == Mode.SPRINT else JOG_PUSH_MULTIPLIER
	# Sprinting exposes a little more of the ball. High technique smooths the
	# correction while low technique retains more of the incoming momentum.
	var target := direction * speed * multiplier
	var blend := lerpf(0.60, 0.90, quality)
	if mode == Mode.SPRINT:
		blend -= 0.10
	return Coordinate3D.ground(current_velocity).lerp(target, clampf(blend, 0.35, 0.9))

static func apply_ground_friction(velocity: Vector3, delta: float) -> Vector3:
	return Coordinate3D.ground(velocity) * pow(GROUND_FRICTION_PER_SECOND, maxf(delta, 0.0))
