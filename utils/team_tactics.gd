class_name TeamTactics
extends RefCounted

## Compact team-level tactical snapshot. It deliberately uses plain data so it
## can be computed and tested without instantiating a match scene.

const MAX_PRESSERS := 1
const COVER_DISTANCE := 90.0

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
		second_last = x_positions[1] if attacking_dir_x > 0 else x_positions[x_positions.size() - 2]
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
