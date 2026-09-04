class_name Match3DRules
extends RefCounted

const Coordinate3D := preload("res://utils/pitch_coordinate_3d.gd")

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
const CAMERA_TARGET_X_MIN := 10.0
const CAMERA_TARGET_X_MAX := 75.0
const CAMERA_TARGET_Z_MIN := 7.0
const CAMERA_TARGET_Z_MAX := 29.0

static func advance_player(position: Vector3, velocity: Vector3, desired_direction: Vector3,
		delta: float, top_speed: float, acceleration: float = 24.0) -> Dictionary:
	var direction := Coordinate3D.ground(desired_direction).normalized()
	var desired_velocity := direction * top_speed
	var next_velocity := velocity.move_toward(desired_velocity, acceleration * maxf(delta, 0.0))
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
