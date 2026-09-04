class_name BallTrajectory3D
extends RefCounted

## Deterministic 3D ball kinematics. X/Z are the pitch plane and Y is height.

const EPSILON := 0.00001

static func step(position: Vector3, velocity: Vector3, delta: float,
		gravity: float, ground_friction: float, air_friction: float,
		bounciness: float = 0.0) -> Dictionary:
	var dt := maxf(delta, 0.0)
	var next_velocity := velocity
	var horizontal := Vector2(next_velocity.x, next_velocity.z)
	var friction := air_friction if position.y > EPSILON or next_velocity.y > 0.0 else ground_friction
	horizontal = horizontal.move_toward(Vector2.ZERO, maxf(friction, 0.0) * dt)
	next_velocity.x = horizontal.x
	next_velocity.z = horizontal.y
	next_velocity.y -= maxf(gravity, 0.0) * dt
	var next_position := position + next_velocity * dt
	var bounced := false
	var ground_contact := false
	var impact_speed := 0.0
	if next_position.y <= 0.0:
		ground_contact = position.y > EPSILON or next_velocity.y < 0.0
		next_position.y = 0.0
		if next_velocity.y < 0.0 and bounciness > 0.0 and absf(next_velocity.y) > 0.4:
			impact_speed = absf(next_velocity.y)
			next_velocity.y = -next_velocity.y * clampf(bounciness, 0.0, 1.0)
			bounced = true
		else:
			impact_speed = absf(next_velocity.y)
			next_velocity.y = 0.0
	return {"position": next_position, "velocity": next_velocity, "bounced": bounced,
		"grounded": is_zero_approx(next_position.y) and is_zero_approx(next_velocity.y),
		"ground_contact": ground_contact, "impact_speed": impact_speed,
		"airborne": next_position.y > EPSILON or absf(next_velocity.y) > EPSILON}

static func step_on_pitch(position: Vector3, velocity: Vector3, delta: float,
		gravity: float, ground_friction: float, air_friction: float,
		bounciness: float, pitch_size: Vector2, goal_half_width: float,
		goal_height: float, boundary_restitution: float) -> Dictionary:
	## Advances the ball and resolves touchline/goal-line boundaries. The goal
	## opening is only traversable inside the horizontal mouth and below the
	## crossbar; all other boundary crossings reflect deterministically.
	var result := step(position, velocity, delta, gravity, ground_friction,
		air_friction, bounciness)
	var next_position: Vector3 = result.position
	var next_velocity: Vector3 = result.velocity
	var goal_open := (next_position.x < 0.0 or next_position.x > pitch_size.x) \
		and absf(next_position.z - pitch_size.y * 0.5) <= goal_half_width \
		and next_position.y <= goal_height
	var boundary_hit := false
	var boundary_axis := ""
	if next_position.z < 0.0 or next_position.z > pitch_size.y:
		next_position.z = clampf(next_position.z, 0.0, pitch_size.y)
		next_velocity.z = -next_velocity.z * clampf(boundary_restitution, 0.0, 1.0)
		boundary_hit = true
		boundary_axis = "z"
	if not goal_open and (next_position.x < 0.0 or next_position.x > pitch_size.x):
		next_position.x = clampf(next_position.x, 0.0, pitch_size.x)
		next_velocity.x = -next_velocity.x * clampf(boundary_restitution, 0.0, 1.0)
		boundary_hit = true
		boundary_axis = "x"
	result.position = next_position
	result.velocity = next_velocity
	result.boundary_hit = boundary_hit
	result.boundary_axis = boundary_axis
	result.goal_crossed = goal_open
	return result

static func launch_velocity(origin: Vector3, target: Vector3, flight_time: float,
		gravity: float) -> Vector3:
	var time := maxf(flight_time, EPSILON)
	var velocity := (target - origin) / time
	velocity.y += 0.5 * maxf(gravity, 0.0) * time
	return velocity

static func position_at(origin: Vector3, velocity: Vector3, time: float,
		gravity: float) -> Vector3:
	var t := maxf(time, 0.0)
	return origin + velocity * t + Vector3.DOWN * (0.5 * maxf(gravity, 0.0) * t * t)

static func sample_path(origin: Vector3, velocity: Vector3, duration: float,
		sample_interval: float, gravity: float, ground_friction: float,
		air_friction: float, bounciness: float = 0.0,
		max_samples: int = 256) -> PackedVector3Array:
	## Samples the same stepped solver used by live gameplay. This is intended
	## for goalkeeper prediction, debug overlays, and future ball-camera work;
	## it never mutates the live state.
	var points := PackedVector3Array()
	var remaining := maxf(duration, 0.0)
	var interval := maxf(sample_interval, 0.0001)
	var position := origin
	var current_velocity := velocity
	points.append(position)
	var samples := 0
	while remaining > EPSILON and samples < maxi(max_samples - 1, 0):
		var dt := minf(interval, remaining)
		var result := step(position, current_velocity, dt, gravity, ground_friction, air_friction, bounciness)
		position = result.position
		current_velocity = result.velocity
		points.append(position)
		remaining -= dt
		samples += 1
	return points

static func sample_pitch_path(origin: Vector3, velocity: Vector3, duration: float,
		sample_interval: float, gravity: float, ground_friction: float,
		air_friction: float, bounciness: float, pitch_size: Vector2,
		goal_half_width: float, goal_height: float, boundary_restitution: float,
		max_samples: int = 256) -> PackedVector3Array:
	var points := PackedVector3Array()
	var remaining := maxf(duration, 0.0)
	var interval := maxf(sample_interval, 0.0001)
	var position := origin
	var current_velocity := velocity
	points.append(position)
	var samples := 0
	while remaining > EPSILON and samples < maxi(max_samples - 1, 0):
		var dt := minf(interval, remaining)
		var result := step_on_pitch(position, current_velocity, dt, gravity,
			ground_friction, air_friction, bounciness, pitch_size, goal_half_width,
			goal_height, boundary_restitution)
		position = result.position
		current_velocity = result.velocity
		points.append(position)
		remaining -= dt
		samples += 1
	return points
