class_name BallTrajectory
extends RefCounted

## Shared deterministic trajectory math for simulation and AI prediction.

const EPSILON := 0.0001

static func ground_velocity_after(initial_velocity: Vector2, friction: float, delta: float) -> Vector2:
	return initial_velocity.move_toward(Vector2.ZERO, maxf(friction, 0.0) * maxf(delta, 0.0))

static func ground_position_after(initial_position: Vector2, initial_velocity: Vector2, friction: float, delta: float) -> Vector2:
	var time := maxf(delta, 0.0)
	var speed := initial_velocity.length()
	if speed <= EPSILON:
		return initial_position
	var deceleration := maxf(friction, EPSILON)
	var travel_time := minf(time, speed / deceleration)
	var distance := speed * travel_time - 0.5 * deceleration * travel_time * travel_time
	return initial_position + initial_velocity.normalized() * distance

## Returns the first time a decelerating trajectory reaches an x or y coordinate.
## INF means the ball is travelling away from, or stops before, that coordinate.
static func time_to_axis_position(origin_axis: float, velocity_axis: float, target_axis: float, friction: float) -> float:
	var offset := target_axis - origin_axis
	if absf(offset) <= EPSILON:
		return 0.0
	if absf(velocity_axis) <= EPSILON or offset * velocity_axis < 0.0:
		return INF
	var distance := absf(offset)
	var speed := absf(velocity_axis)
	var deceleration := maxf(friction, 0.0)
	if deceleration <= EPSILON:
		return distance / speed
	var discriminant := speed * speed - 2.0 * deceleration * distance
	if discriminant < 0.0:
		return INF
	return (speed - sqrt(discriminant)) / deceleration

static func landing_time(height: float, vertical_velocity: float, gravity: float) -> float:
	var safe_gravity := maxf(gravity, EPSILON)
	var discriminant := vertical_velocity * vertical_velocity + 2.0 * safe_gravity * maxf(height, 0.0)
	return maxf((vertical_velocity + sqrt(maxf(discriminant, 0.0))) / safe_gravity, 0.0)

static func landing_position(position: Vector2, velocity: Vector2, height: float, vertical_velocity: float, gravity: float, friction: float) -> Vector2:
	return ground_position_after(position, velocity, friction, landing_time(height, vertical_velocity, gravity))

static func velocity_for_ground_target(origin: Vector2, target: Vector2, friction: float) -> Vector2:
	var offset := target - origin
	var distance := offset.length()
	if distance <= EPSILON:
		return Vector2.ZERO
	var speed := sqrt(2.0 * maxf(friction, EPSILON) * distance)
	return offset.normalized() * speed

## Solves an initial velocity that first reaches target at arrival_time while
## decelerating with the same constant friction used by the live ball state.
static func velocity_for_ground_target_at_time(
	origin: Vector2,
	target: Vector2,
	friction: float,
	arrival_time: float
) -> Vector2:
	var offset := target - origin
	var distance := offset.length()
	if distance <= EPSILON:
		return Vector2.ZERO
	var deceleration := maxf(friction, EPSILON)
	# A ball that stops at the target is the latest valid arrival. Clamp to that
	# bound so the analytical equation never asks a stopped ball to travel again.
	var latest_arrival := sqrt(2.0 * distance / deceleration)
	var time := clampf(arrival_time, EPSILON, latest_arrival)
	var speed := distance / time + 0.5 * deceleration * time
	return offset.normalized() * speed

static func bounce_velocity(velocity: Vector2, normal: Vector2, bounciness: float) -> Vector2:
	if normal.length_squared() <= EPSILON:
		return velocity
	return velocity.bounce(normal.normalized()) * clampf(bounciness, 0.0, 1.0)
