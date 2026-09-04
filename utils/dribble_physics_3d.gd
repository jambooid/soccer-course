class_name DribblePhysics3D
extends RefCounted

const Coordinate3D := preload("res://utils/pitch_coordinate_3d.gd")

## Small, deterministic helpers for WE/PES-style touch-and-run dribbling.
## The ball remains independent between touches; these functions only describe
## the next foot contact.
enum Mode { JOG, SPRINT }

const TOUCH_INTERVAL_JOG := 0.22
const TOUCH_INTERVAL_SPRINT := 0.42
const CONTROL_DISTANCE_JOG := 1.35
const CONTROL_DISTANCE_SPRINT := 2.30
const TOUCH_OFFSET_JOG := 0.62
const TOUCH_OFFSET_SPRINT := 0.82
const JOG_PUSH_MULTIPLIER := 1.45
const SPRINT_PUSH_MULTIPLIER := 1.25
const IDLE_PUSH_SPEED_JOG := 0.9
const IDLE_PUSH_SPEED_SPRINT := 1.2
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
		facing: Vector3, technique: float, mode: int,
		requested_direction: Vector3 = Vector3.ZERO) -> Vector3:
	var movement := Coordinate3D.ground(player_velocity)
	var speed := movement.length()
	var carry_direction := movement.normalized() if speed > 0.08 else Coordinate3D.ground(facing).normalized()
	if carry_direction.is_zero_approx():
		carry_direction = Vector3.RIGHT
	var intent := Coordinate3D.ground(requested_direction).normalized()
	if intent.is_zero_approx():
		intent = carry_direction
	var quality := technique_normalized(technique)
	var multiplier := SPRINT_PUSH_MULTIPLIER if mode == Mode.SPRINT else JOG_PUSH_MULTIPLIER
	var idle_speed := IDLE_PUSH_SPEED_SPRINT if mode == Mode.SPRINT else IDLE_PUSH_SPEED_JOG
	var target_speed := maxf(speed * multiplier, idle_speed)
	# The stick direction is applied at the next foot contact, not by teleporting
	# the ball. Blend it with the body's inertial heading to create the readable
	# WE2000 turn arc and let technique determine how quickly it straightens.
	var steering := lerpf(0.32, 0.72, quality)
	var heading_alignment := carry_direction.dot(intent)
	if heading_alignment < 0.35:
		# A cut to the opposite side is a deliberate sole/inside-foot touch;
		# allowing the old heading to dominate here leaves the ball hanging at
		# the outside hip instead of crossing to the new leading foot.
		steering = maxf(steering, lerpf(0.72, 0.88, quality))
	var push_direction := carry_direction.lerp(intent, steering).normalized()
	var target := push_direction * target_speed
	var blend := lerpf(0.58, 0.86, quality)
	if mode == Mode.SPRINT:
		blend -= 0.06
	return Coordinate3D.ground(current_velocity).lerp(target, clampf(blend, 0.42, 0.88))

static func apply_ground_friction(velocity: Vector3, delta: float) -> Vector3:
	return Coordinate3D.ground(velocity) * pow(GROUND_FRICTION_PER_SECOND, maxf(delta, 0.0))
