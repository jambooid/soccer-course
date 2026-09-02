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

static func bounce_velocity(velocity: Vector2, normal: Vector2, bounciness: float) -> Vector2:
	if normal.length_squared() <= EPSILON:
		return velocity
	return velocity.bounce(normal.normalized()) * clampf(bounciness, 0.0, 1.0)
