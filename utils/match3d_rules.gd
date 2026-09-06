class_name Match3DRules
extends RefCounted

const Coordinate3D := preload("res://utils/pitch_coordinate_3d.gd")
const Flow := preload("res://utils/match_flow.gd")

## All gameplay state is expressed in world-space Vector3 values. Players
## move on X/Z while the ball alone uses Y for height.

const PITCH_SIZE := Coordinate3D.PITCH_SIZE
const GOAL_HALF_WIDTH := Coordinate3D.GOAL_HALF_WIDTH
const GOAL_HEIGHT := 3.1
const PLAYER_RADIUS := 0.48
const CONTROL_RADIUS := 1.18
const PLAYER_CONTROL_HEIGHT_MAX := 1.25
const PASS_SPEED := 27.0
const LONG_PASS_SPEED := 35.0
const SHOT_SPEED := 48.0
const TURN_RATE_LOW_SPEED := 12.0
const TURN_RATE_HIGH_SPEED := 4.0
const CAMERA_TARGET_X_MIN := 10.0
const CAMERA_TARGET_X_MAX := 75.0
const CAMERA_TARGET_Z_MIN := 7.0
const CAMERA_TARGET_Z_MAX := 29.0

static func advance_player(position: Vector3, velocity: Vector3, desired_direction: Vector3,
		delta: float, top_speed: float, acceleration: float = 24.0) -> Dictionary:
	var direction := Coordinate3D.ground(desired_direction).normalized()
	var current_velocity := Coordinate3D.ground(velocity)
	var current_speed := current_velocity.length()
	var desired_speed := top_speed if not direction.is_zero_approx() else 0.0
	var next_speed := move_toward(current_speed, desired_speed, acceleration * maxf(delta, 0.0))
	var current_direction := current_velocity.normalized()
	if current_direction.is_zero_approx():
		current_direction = direction
	var next_direction := current_direction
	if not direction.is_zero_approx() and not current_direction.is_zero_approx():
		# WE-style steering: low-speed players can turn sharply, while a sprint
		# bends through an arc instead of instantly swapping velocity vectors.
		var speed_ratio := clampf(current_speed / maxf(top_speed, 0.001), 0.0, 1.0)
		var turn_rate := lerpf(TURN_RATE_LOW_SPEED, TURN_RATE_HIGH_SPEED, speed_ratio)
		var signed_angle := atan2(current_direction.cross(direction).y,
			current_direction.dot(direction))
		var turn_step := clampf(signed_angle, -turn_rate * delta, turn_rate * delta)
		next_direction = current_direction.rotated(Vector3.UP, turn_step).normalized()
	if current_speed < 0.08 and not direction.is_zero_approx():
		next_direction = direction
	var next_velocity := next_direction * next_speed
	next_velocity.y = 0.0
	var next_position := Coordinate3D.clamp_pitch(position + next_velocity * maxf(delta, 0.0), PLAYER_RADIUS)
	next_position.y = 0.0
	return {"position": next_position, "velocity": next_velocity}

static func select_pass_target(players: Array, passer_id: int, home: bool,
		direction: Vector3, ball_position: Vector3) -> Dictionary:
	var aim := Coordinate3D.ground(direction).normalized()
	if aim.is_zero_approx():
		aim = Vector3.RIGHT if home else Vector3.LEFT
	var best: Dictionary = {}
	var best_score := -INF
	for candidate: Dictionary in players:
		if bool(candidate.get("home", false)) != home or int(candidate.get("id", -1)) == passer_id:
			continue
		var offset: Vector3 = Coordinate3D.ground(candidate.get("position", Vector3.ZERO) - ball_position)
		var distance := offset.length()
		if distance < 1.0 or distance > 34.0:
			continue
		var alignment := aim.dot(offset / distance)
		var forward_progress := offset.x * (1.0 if home else -1.0)
		var score := alignment * 3.0 + forward_progress * 0.025 - distance * 0.018
		if score > best_score:
			best_score = score
			best = candidate
	return best.duplicate(true)

## CPU pass selection favours forward receivers only when the ground passing
## lane has usable clearance from an opponent. This is intentionally a cheap
## point-to-segment test so it can be evaluated frequently like WE2000's
## ray-style pass checks.
static func select_safe_pass_target(players: Array, passer_id: int, home: bool,
		ball_position: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -INF
	var attack_sign := 1.0 if home else -1.0
	for candidate: Dictionary in players:
		if bool(candidate.get("home", false)) != home or int(candidate.get("id", -1)) == passer_id:
			continue
		var target: Vector3 = Coordinate3D.ground(candidate.get("position", Vector3.ZERO))
		var offset := target - Coordinate3D.ground(ball_position)
		var distance := offset.length()
		if distance < 3.0 or distance > 32.0:
			continue
		var progress := offset.x * attack_sign
		if progress < -4.0:
			continue
		var clearance := _pass_lane_clearance(players, home, ball_position, target)
		if clearance < 0.95:
			continue
		var score := progress * 0.16 + clearance * 0.82 - distance * 0.025
		if score > best_score:
			best_score = score
			best = candidate
	return best.duplicate(true)

static func _pass_lane_clearance(players: Array, home: bool, origin: Vector3,
		target: Vector3) -> float:
	var closest := INF
	var lane := Coordinate3D.ground(target - origin)
	var lane_length_squared := lane.length_squared()
	if lane_length_squared <= 0.001:
		return 0.0
	for player: Dictionary in players:
		if bool(player.get("home", false)) == home:
			continue
		var relative := Coordinate3D.ground(player.get("position", Vector3.ZERO) - origin)
		var progress := clampf(relative.dot(lane) / lane_length_squared, 0.12, 0.92)
		var closest_point := lane * progress
		closest = minf(closest, relative.distance_to(closest_point))
	# An empty opponent list is a valid test/training setup. Cap the value so
	# forward progress and pass distance still decide between equally open lanes.
	return minf(closest, 12.0)

static func pass_velocity(origin: Vector3, target: Vector3, long_pass := false) -> Vector3:
	var speed := LONG_PASS_SPEED if long_pass else PASS_SPEED
	return Coordinate3D.ground(target - origin).normalized() * speed

static func shot_velocity(origin: Vector3, home: bool, lateral_aim: float = 0.0) -> Vector3:
	var goal := Vector3(PITCH_SIZE.x if home else 0.0, 0.0,
		PITCH_SIZE.z * 0.5 + clampf(lateral_aim, -GOAL_HALF_WIDTH * 0.72, GOAL_HALF_WIDTH * 0.72))
	return Coordinate3D.ground(goal - origin).normalized() * SHOT_SPEED

static func goal_scoring_team(ball_position: Vector3) -> int:
	if ball_position.y < -0.001 or ball_position.y > GOAL_HEIGHT or not Coordinate3D.in_goal_mouth(ball_position):
		return 0
	if ball_position.x < 0.0:
		return -1
	if ball_position.x > PITCH_SIZE.x:
		return 1
	return 0

static func boundary_restart(ball_position: Vector3, boundary_axis: String,
		last_touch_home: bool) -> Dictionary:
	var position := Coordinate3D.clamp_pitch(Coordinate3D.ground(ball_position))
	if boundary_axis == "z":
		return {"type": Flow.RestartType.THROW_IN, "team_home": not last_touch_home,
			"position": position, "reason": "TOUCHLINE"}
	var left_goal_line := ball_position.x <= PITCH_SIZE.x * 0.5
	var defending_home := left_goal_line
	if last_touch_home == defending_home:
		position.x = 0.0 if left_goal_line else PITCH_SIZE.x
		position.z = 0.0 if position.z < PITCH_SIZE.z * 0.5 else PITCH_SIZE.z
		return {"type": Flow.RestartType.CORNER, "team_home": not defending_home,
			"position": position, "reason": "DEFENDER_LAST_TOUCH"}
	position.x = 5.5 if left_goal_line else PITCH_SIZE.x - 5.5
	position.z = PITCH_SIZE.z * 0.5
	return {"type": Flow.RestartType.GOAL_KICK, "team_home": defending_home,
		"position": position, "reason": "ATTACKER_LAST_TOUCH"}

static func can_ground_player_control_ball(player_position: Vector3,
		ball_position: Vector3, radius: float = CONTROL_RADIUS,
		max_height: float = PLAYER_CONTROL_HEIGHT_MAX) -> bool:
	if ball_position.y < -0.001 or ball_position.y > max_height:
		return false
	return Coordinate3D.ground(player_position - ball_position).length() <= maxf(radius, 0.0)

static func camera_target(ball_position: Vector3) -> Vector3:
	return Coordinate3D.camera_target(ball_position,
		Vector3(CAMERA_TARGET_X_MIN, 0.0, CAMERA_TARGET_Z_MIN))

static func nearest_player_id(players: Array, ball_position: Vector3, home_filter: int = 0) -> int:
	var closest_id := -1
	var closest_distance := INF
	for player: Dictionary in players:
		var home := bool(player.get("home", false))
		if home_filter != 0 and home != (home_filter > 0):
			continue
		var distance := Coordinate3D.ground(player.get("position", Vector3.ZERO) - ball_position).length_squared()
		if distance < closest_distance:
			closest_distance = distance
			closest_id = int(player.get("id", -1))
	return closest_id

static func select_switch_target(players: Array, current_id: int, direction: Vector3,
		ball_position: Vector3) -> int:
	var current: Dictionary = {}
	for player: Dictionary in players:
		if int(player.get("id", -1)) == current_id:
			current = player
			break
	if current.is_empty():
		return nearest_player_id(players, ball_position, 1)
	var aim := Coordinate3D.ground(direction).normalized()
	var best_id := -1
	var best_score := -INF
	for player: Dictionary in players:
		if int(player.get("id", -1)) == current_id or bool(player.get("home", false)) != bool(current.get("home", true)):
			continue
		var offset: Vector3 = Coordinate3D.ground(player.get("position", Vector3.ZERO) - ball_position)
		var distance := offset.length()
		if aim.is_zero_approx():
			var neutral_score := -distance
			if neutral_score > best_score:
				best_score = neutral_score
				best_id = int(player.get("id", -1))
			continue
		var alignment := aim.dot(offset.normalized()) if distance > 0.001 else -1.0
		var score := alignment * 2.5 - distance * 0.045
		if score > best_score:
			best_score = score
			best_id = int(player.get("id", -1))
	return best_id

static func resolve_pair_separation(first: Vector3, second: Vector3,
		radius: float = PLAYER_RADIUS) -> Dictionary:
	var offset := Coordinate3D.ground(second - first)
	var minimum := radius * 2.0
	if offset.length_squared() >= minimum * minimum:
		return {"first": first, "second": second}
	var normal := offset.normalized()
	if normal.is_zero_approx():
		normal = Vector3.RIGHT
	var correction := (minimum - offset.length()) * 0.5
	return {"first": Coordinate3D.ground(first - normal * correction),
		"second": Coordinate3D.ground(second + normal * correction)}
