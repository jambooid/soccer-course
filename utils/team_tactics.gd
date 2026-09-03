class_name TeamTactics
extends RefCounted

## Compact team-level tactical snapshot. It deliberately uses plain data so it
## can be computed and tested without instantiating a match scene.

const MAX_PRESSERS := 1
const COVER_DISTANCE := 90.0
const SUPPORT_WIDTH_SCALE := 1.08
const SUPPORT_BALL_SIDE_SHIFT := 0.18
const SUPPORT_MAX_BALL_SIDE_SHIFT := 18.0

## Build executable defensive roles. Only the presser targets the ball; cover
## protects the goal-side lane and the rest retain shifted formation anchors.
static func build_defensive_assignments(
	team_players: Array[Dictionary],
	ball_position: Vector2,
	defensive_goal: Vector2
) -> Dictionary:
	var ordered := team_players.duplicate(true)
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _distance_sq(left, ball_position) < _distance_sq(right, ball_position)
	)
	var assignments := {}
	for index in ordered.size():
		var player: Dictionary = ordered[index]
		var player_id := int(player.get("id", -1))
		var anchor: Vector2 = player.get("spawn_position", player.get("position", Vector2.ZERO))
		var assignment := {"role": "HOLD", "target": _hold_target(anchor, ball_position, defensive_goal)}
		if index < MAX_PRESSERS:
			assignment = {"role": "PRESS", "target": ball_position}
		elif index == MAX_PRESSERS:
			assignment = {"role": "COVER", "target": ball_position.lerp(defensive_goal, 0.35)}
		assignments[player_id] = assignment
	return assignments

## Generate a central option, ball-side/wide option, and a conservative safety
## option from formation anchors while a team has possession.
static func build_attacking_assignments(
	team_players: Array[Dictionary],
	ball_position: Vector2,
	attacking_dir_x: int,
	carrier_id: int
) -> Dictionary:
	var assignments := {}
	var non_carriers: Array[Dictionary] = []
	for player in team_players:
		if int(player.get("id", -1)) != carrier_id:
			non_carriers.append(player)
	if non_carriers.is_empty():
		return assignments

	var formation_center_y := 0.0
	var min_forward_anchor := INF
	var max_forward_anchor := -INF
	for player in team_players:
		var anchor: Vector2 = player.get("spawn_position", player.get("position", Vector2.ZERO))
		var forward_anchor := anchor.x * attacking_dir_x
		formation_center_y += anchor.y
		min_forward_anchor = minf(min_forward_anchor, forward_anchor)
		max_forward_anchor = maxf(max_forward_anchor, forward_anchor)
	formation_center_y /= team_players.size()

	var max_lane_offset := 0.0
	for player in team_players:
		var anchor: Vector2 = player.get("spawn_position", player.get("position", Vector2.ZERO))
		max_lane_offset = maxf(max_lane_offset, absf(anchor.y - formation_center_y))
	var wide_lane_threshold := maxf(30.0, max_lane_offset * 0.55)
	var ball_forward := ball_position.x * attacking_dir_x
	var ball_side_shift := clampf(
		(ball_position.y - formation_center_y) * SUPPORT_BALL_SIDE_SHIFT,
		-SUPPORT_MAX_BALL_SIDE_SHIFT,
		SUPPORT_MAX_BALL_SIDE_SHIFT)

	var safety := non_carriers[0]
	for candidate in non_carriers:
		var candidate_anchor: Vector2 = candidate.get("spawn_position", candidate.get("position", Vector2.ZERO))
		var safety_anchor: Vector2 = safety.get("spawn_position", safety.get("position", Vector2.ZERO))
		var candidate_score := candidate_anchor.x * attacking_dir_x \
			+ absf(candidate_anchor.y - formation_center_y) * 0.6
		var safety_score := safety_anchor.x * attacking_dir_x \
			+ absf(safety_anchor.y - formation_center_y) * 0.6
		if candidate_score < safety_score:
			safety = candidate

	for player in non_carriers:
		var player_id := int(player.get("id", -1))
		var anchor: Vector2 = player.get("spawn_position", player.get("position", Vector2.ZERO))
		var anchor_forward := anchor.x * attacking_dir_x
		var depth_ratio := inverse_lerp(min_forward_anchor, max_forward_anchor, anchor_forward) \
			if not is_equal_approx(min_forward_anchor, max_forward_anchor) else 0.5
		var advance_factor := lerpf(0.28, 0.68, depth_ratio)
		var max_advance := lerpf(85.0, 150.0, depth_ratio)
		var forward_shift := clampf(
			(ball_forward - anchor_forward) * advance_factor, -45.0, max_advance)
		var line_lead := lerpf(-15.0, 42.0, depth_ratio)
		var target_forward := anchor_forward + forward_shift + line_lead
		var lane_offset := anchor.y - formation_center_y
		var role := "CENTRAL"
		var target := Vector2(target_forward * attacking_dir_x,
			formation_center_y + lane_offset * SUPPORT_WIDTH_SCALE + ball_side_shift)
		if player == safety:
			role = "SAFETY"
			var safety_shift := clampf((ball_forward - anchor_forward) * 0.18, -25.0, 70.0)
			target.x = (anchor_forward + safety_shift) * attacking_dir_x
		elif absf(lane_offset) >= wide_lane_threshold:
			role = "WIDE"
		assignments[player_id] = {"role": role, "target": target}
	return assignments

## Produces a movement intent that reaches a target and settles there instead
## of repeatedly overshooting it. The intent magnitude is the desired speed
## ratio, while its direction remains suitable for the player's turn controller.
static func arrival_intent(
	position: Vector2,
	target: Vector2,
	stop_radius: float,
	slow_radius: float
) -> Vector2:
	var offset := target - position
	var distance := offset.length()
	if distance <= stop_radius or distance <= 0.001:
		return Vector2.ZERO
	var usable_slow_radius := maxf(slow_radius, stop_radius + 0.001)
	var speed_ratio := clampf(
		(distance - stop_radius) / (usable_slow_radius - stop_radius), 0.0, 1.0)
	return offset / distance * speed_ratio

static func build_snapshot(team_players: Array[Dictionary], opponents: Array[Dictionary], ball_position: Vector2, attacking_dir_x: int, pitch_center_x: float = 0.0) -> Dictionary:
	var ordered := team_players.duplicate(true)
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _distance_sq(left, ball_position) < _distance_sq(right, ball_position)
	)
	var presser_ids: Array[int] = []
	var cover_ids: Array[int] = []
	if not ordered.is_empty():
		presser_ids.append(int(ordered[0].get("id", -1)))
		for candidate in ordered.slice(1):
			if cover_ids.size() >= 2:
				break
			if _distance_sq(candidate, ball_position) <= COVER_DISTANCE * COVER_DISTANCE:
				cover_ids.append(int(candidate.get("id", -1)))
	var offside_line_x := compute_offside_line(opponents, ball_position, attacking_dir_x)
	return {
		"ball_position": ball_position,
		"attacking_dir_x": attacking_dir_x,
		"offside_line_x": offside_line_x,
		"presser_ids": presser_ids,
		"cover_ids": cover_ids,
		"anchors": _build_anchors(team_players),
	}

static func compute_offside_line(defenders: Array[Dictionary], ball_position: Vector2, attacking_dir_x: int) -> float:
	if defenders.is_empty():
		return ball_position.x
	var x_positions: Array[float] = []
	for defender in defenders:
		x_positions.append(float((defender.get("position", Vector2.ZERO) as Vector2).x))
	x_positions.sort()
	var second_last := x_positions[0]
	if x_positions.size() >= 2:
		second_last = x_positions[x_positions.size() - 2] if attacking_dir_x > 0 else x_positions[1]
	return minf(second_last, ball_position.x) if attacking_dir_x > 0 else maxf(second_last, ball_position.x)

static func clamp_support_target(target: Vector2, offside_line_x: float, attacking_dir_x: int, pitch_center_x: float) -> Vector2:
	var result := target
	if attacking_dir_x > 0 and result.x > pitch_center_x:
		result.x = minf(result.x, offside_line_x - 1.0)
	elif attacking_dir_x < 0 and result.x < pitch_center_x:
		result.x = maxf(result.x, offside_line_x + 1.0)
	return result

static func _distance_sq(player: Dictionary, point: Vector2) -> float:
	return (player.get("position", Vector2.ZERO) as Vector2).distance_squared_to(point)

static func _build_anchors(players: Array[Dictionary]) -> Dictionary:
	var anchors := {}
	for player in players:
		anchors[int(player.get("id", -1))] = player.get("spawn_position", player.get("position", Vector2.ZERO))
	return anchors

static func _hold_target(anchor: Vector2, ball_position: Vector2, defensive_goal: Vector2) -> Vector2:
	var ball_side_shift := clampf((ball_position.y - defensive_goal.y) * 0.2, -35.0, 35.0)
	return Vector2(anchor.x, anchor.y + ball_side_shift)
