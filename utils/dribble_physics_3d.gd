class_name DribblePhysics3D
extends RefCounted

const Coordinate3D := preload("res://utils/pitch_coordinate_3d.gd")

## Small, deterministic helpers for WE/PES-style touch-and-run dribbling.
## The ball remains independent between touches; these functions only describe
## the next foot contact.
enum Mode { JOG, SPRINT }
enum TurnType { NONE, DEGREE_45, DEGREE_90, DEGREE_180 }

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
const TURN_45_MIN_DEGREES := 25.0
const TURN_90_MIN_DEGREES := 65.0
const TURN_180_MIN_DEGREES := 135.0
const TURN_90_BALL_ANCHOR_SECONDS := 0.07
const TURNAROUND_BALL_ANCHOR_SECONDS := 0.10
const TURNAROUND_INPUT_LOCK_SECONDS := 0.20
const TURN_45_PLAYER_ALIGN_SECONDS := 0.15

## Dribbling lives on the pitch plane. Keep the simulation in Vector2 (x/z)
## and only convert back to Vector3 when publishing the ball's world position.
static func to_pitch_plane(value: Vector3) -> Vector2:
	return Vector2(value.x, value.z)

static func from_pitch_plane(value: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(value.x, height, value.y)

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

## WE2000's directional input is read as one of eight lanes at a foot contact.
## Keeping this conversion here makes keyboard, stick, and future animation
## event callers agree on the exact direction of a cut.
static func quantize_direction(direction: Vector3) -> Vector3:
	var ground_direction := Coordinate3D.ground(direction)
	if ground_direction.length_squared() < 0.0001:
		return Vector3.ZERO
	var angle := atan2(ground_direction.z, ground_direction.x)
	var lane_angle := roundf(angle / (PI * 0.25)) * (PI * 0.25)
	return Vector3(cos(lane_angle), 0.0, sin(lane_angle))

static func classify_turn(current_direction: Vector3, requested_direction: Vector3) -> int:
	var current := quantize_direction(current_direction)
	var requested := quantize_direction(requested_direction)
	if current.is_zero_approx() or requested.is_zero_approx():
		return TurnType.NONE
	var angle_degrees := rad_to_deg(acos(clampf(current.dot(requested), -1.0, 1.0)))
	# Quantized diagonal lanes can evaluate as 134.999... after acos(), so keep
	# the authored 135 degree threshold while accepting normal float error.
	if angle_degrees >= TURN_180_MIN_DEGREES - 0.01:
		return TurnType.DEGREE_180
	if angle_degrees >= TURN_90_MIN_DEGREES:
		return TurnType.DEGREE_90
	if angle_degrees >= TURN_45_MIN_DEGREES:
		return TurnType.DEGREE_45
	return TurnType.NONE

static func turn_speed_multiplier(turn_type: int) -> float:
	match turn_type:
		TurnType.DEGREE_45:
			return 0.95
		TurnType.DEGREE_90:
			return 0.60
		TurnType.DEGREE_180:
			return 0.15
	return 1.0

static func turn_touch_multiplier(turn_type: int) -> float:
	match turn_type:
		TurnType.DEGREE_45:
			return 0.95
		TurnType.DEGREE_90:
			return 0.80
		TurnType.DEGREE_180:
			return 0.62
	return 1.0

static func turn_anchor_duration(turn_type: int) -> float:
	match turn_type:
		TurnType.DEGREE_90:
			return TURN_90_BALL_ANCHOR_SECONDS
		TurnType.DEGREE_180:
			return TURNAROUND_BALL_ANCHOR_SECONDS
	return 0.0

## The front defender is projected forward briefly, then the three nearby
## eight-way lanes are scored. This is intentionally a small correction: it
## protects a slight evasive input without selecting an unrelated direction.
static func steer_away_from_defender(intent: Vector3, carrier_position: Vector3,
		defender_position: Vector3, defender_velocity: Vector3) -> Vector3:
	var requested := quantize_direction(intent)
	var to_defender := Coordinate3D.ground(defender_position - carrier_position)
	if requested.is_zero_approx() or to_defender.length_squared() < 0.0001:
		return requested
	var defender_direction := to_defender.normalized()
	if requested.dot(defender_direction) < 0.2:
		return requested
	var future_defender := Coordinate3D.ground(defender_position + defender_velocity * 0.22)
	var best_direction := requested
	var best_score := -INF
	for lane_offset in [-1, 0, 1]:
		var candidate := requested.rotated(Vector3.UP, float(lane_offset) * PI * 0.25)
		var future_clearance := Coordinate3D.ground(
			carrier_position + candidate * 1.25 - future_defender).length()
		var progress := candidate.dot(requested)
		var away_from_defender := -candidate.dot(defender_direction)
		var score := progress * 2.0 + away_from_defender * 1.40 + future_clearance * 0.32
		if score > best_score:
			best_score = score
			best_direction = candidate
	return best_direction

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

static func touch_target_speed(player_velocity: Vector3, mode: int) -> float:
	var speed := Coordinate3D.ground(player_velocity).length()
	var multiplier := SPRINT_PUSH_MULTIPLIER if mode == Mode.SPRINT else JOG_PUSH_MULTIPLIER
	var idle_speed := IDLE_PUSH_SPEED_SPRINT if mode == Mode.SPRINT else IDLE_PUSH_SPEED_JOG
	return maxf(speed * multiplier, idle_speed)

## Every classified cut clears the old ball heading at its foot-contact event.
## The 45 degree cut immediately releases a near-full diagonal touch, while
## 90 and 180 degree cuts use their stronger deceleration and anchor states.
static func turn_touch_velocity(current_velocity: Vector3, player_velocity: Vector3,
		facing: Vector3, technique: float, mode: int, requested_direction: Vector3,
		turn_type: int) -> Vector3:
	if turn_type == TurnType.DEGREE_45 or turn_type == TurnType.DEGREE_90 or turn_type == TurnType.DEGREE_180:
		var requested := quantize_direction(requested_direction)
		if requested.is_zero_approx():
			requested = quantize_direction(facing)
		if turn_type == TurnType.DEGREE_45:
			return requested * touch_target_speed(player_velocity, mode) * turn_touch_multiplier(turn_type)
		var ordinary := touch_velocity(Vector3.ZERO, player_velocity, facing,
			technique, mode, requested)
		return requested * ordinary.length() * turn_touch_multiplier(turn_type)
	return touch_velocity(current_velocity, player_velocity, facing, technique, mode,
		requested_direction)

static func apply_ground_friction(velocity: Vector3, delta: float) -> Vector3:
	return Coordinate3D.ground(velocity) * pow(GROUND_FRICTION_PER_SECOND, maxf(delta, 0.0))

static func apply_ground_friction_2d(velocity: Vector2, delta: float) -> Vector2:
	return velocity * pow(GROUND_FRICTION_PER_SECOND, maxf(delta, 0.0))
