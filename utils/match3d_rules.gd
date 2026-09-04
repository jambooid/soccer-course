class_name Match3DRules
extends RefCounted

const Coordinate3D := preload("res://utils/pitch_coordinate_3d.gd")
## Pure gameplay helpers for the playable 3D match. Coordinates are meters on
## the X/Z pitch plane; Vector2.y maps to world Z in the presentation layer.

const PITCH_SIZE := Vector2(Coordinate3D.PITCH_SIZE.x, Coordinate3D.PITCH_SIZE.z)
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
const CAMERA_TARGET_Y_MIN := 7.0
const CAMERA_TARGET_Y_MAX := 29.0

static func advance_player(position: Vector2, velocity: Vector2, desired_direction: Vector2,
		delta: float, top_speed: float, acceleration: float = 24.0) -> Dictionary:
	var direction := desired_direction.normalized()
	var desired_velocity := direction * top_speed
	var next_velocity := velocity.move_toward(desired_velocity, acceleration * maxf(delta, 0.0))
	var next_position := position + next_velocity * maxf(delta, 0.0)
	next_position.x = clampf(next_position.x, PLAYER_RADIUS, PITCH_SIZE.x - PLAYER_RADIUS)
	next_position.y = clampf(next_position.y, PLAYER_RADIUS, PITCH_SIZE.y - PLAYER_RADIUS)
	return {"position": next_position, "velocity": next_velocity}

static func select_pass_target(players: Array, passer_id: int, home: bool,
		direction: Vector2, ball_position: Vector2) -> Dictionary:
	var aim := direction.normalized()
	if aim.is_zero_approx():
		aim = Vector2.RIGHT if home else Vector2.LEFT
	var best: Dictionary = {}
	var best_score := -INF
	for candidate: Dictionary in players:
		if bool(candidate.get("home", false)) != home or int(candidate.get("id", -1)) == passer_id:
			continue
		var offset: Vector2 = candidate.get("position", Vector2.ZERO) - ball_position
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

static func pass_velocity(origin: Vector2, target: Vector2, long_pass := false) -> Vector2:
	var speed := LONG_PASS_SPEED if long_pass else PASS_SPEED
	return origin.direction_to(target) * speed

static func shot_velocity(origin: Vector2, home: bool, vertical_aim: float = 0.0) -> Vector2:
	var goal := Vector2(PITCH_SIZE.x if home else 0.0,
		PITCH_SIZE.y * 0.5 + clampf(vertical_aim, -GOAL_HALF_WIDTH * 0.72, GOAL_HALF_WIDTH * 0.72))
	return origin.direction_to(goal) * SHOT_SPEED

static func goal_scoring_team(ball_position: Vector2) -> int:
	if absf(ball_position.y - PITCH_SIZE.y * 0.5) > GOAL_HALF_WIDTH:
		return 0
	if ball_position.x < 0.0:
		return -1
	if ball_position.x > PITCH_SIZE.x:
		return 1
	return 0

static func goal_scoring_team_3d(ball_world_position: Vector3) -> int:
	if ball_world_position.y < -0.001 or ball_world_position.y > GOAL_HEIGHT:
		return 0
	return goal_scoring_team(Coordinate3D.from_world(ball_world_position))

static func can_ground_player_control_ball(player_position: Vector2,
		ball_world_position: Vector3, radius: float = CONTROL_RADIUS,
		max_height: float = PLAYER_CONTROL_HEIGHT_MAX) -> bool:
	## Ground players only control a ball inside their footprint and below the
	## configured foot-control height. Aerial control can be added separately.
	if ball_world_position.y < -0.001 or ball_world_position.y > max_height:
		return false
	return player_position.distance_to(Vector2(ball_world_position.x,
		ball_world_position.z)) <= maxf(radius, 0.0)

static func camera_target(ball_position: Vector2) -> Vector2:
	return Coordinate3D.camera_target(ball_position,
		Vector2(CAMERA_TARGET_X_MIN, CAMERA_TARGET_Y_MIN))

static func nearest_player_id(players: Array, ball_position: Vector2, home_filter: int = 0) -> int:
	var closest_id := -1
	var closest_distance := INF
	for player: Dictionary in players:
		var home := bool(player.get("home", false))
		if home_filter != 0 and home != (home_filter > 0):
			continue
		var distance := (player.get("position", Vector2.ZERO) as Vector2).distance_squared_to(ball_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_id = int(player.get("id", -1))
	return closest_id

static func select_switch_target(players: Array, current_id: int, direction: Vector2,
		ball_position: Vector2) -> int:
	var current: Dictionary = {}
	for player: Dictionary in players:
		if int(player.get("id", -1)) == current_id:
			current = player
			break
	if current.is_empty():
		return nearest_player_id(players, ball_position, 1)
	var aim := direction.normalized()
	var best_id := -1
	var best_score := -INF
	for player: Dictionary in players:
		if int(player.get("id", -1)) == current_id or bool(player.get("home", false)) != bool(current.get("home", true)):
			continue
		var offset: Vector2 = player.get("position", Vector2.ZERO) - ball_position
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

static func resolve_pair_separation(first: Vector2, second: Vector2,
		radius: float = PLAYER_RADIUS) -> Dictionary:
	var offset := second - first
	var minimum := radius * 2.0
	if offset.length_squared() >= minimum * minimum:
		return {"first": first, "second": second}
	var normal := offset.normalized()
	if normal.is_zero_approx():
		normal = Vector2.RIGHT
	var correction := (minimum - offset.length()) * 0.5
	return {"first": first - normal * correction, "second": second + normal * correction}
