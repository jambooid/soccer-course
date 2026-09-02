class_name PlayerSwitchSelector
extends RefCounted

## Deterministic human-control target selection. Candidates are plain snapshot
## records so the same loose-ball situation always picks the same player.
static func select(candidates: Array[Dictionary], ball_position: Vector2, input_direction: Vector2 = Vector2.ZERO) -> Dictionary:
	var eligible := candidates.filter(func(candidate: Dictionary) -> bool:
		return bool(candidate.get("eligible", true)) and not bool(candidate.get("goalkeeper", false)))
	eligible.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_score := _score(left, ball_position, input_direction)
		var right_score := _score(right, ball_position, input_direction)
		if not is_equal_approx(left_score, right_score):
			return left_score > right_score
		return int(left.get("id", 0)) < int(right.get("id", 0))
	)
	return eligible[0].duplicate(true) if not eligible.is_empty() else {}

static func _score(candidate: Dictionary, ball_position: Vector2, input_direction: Vector2) -> float:
	var position: Vector2 = candidate.get("position", Vector2.ZERO)
	var speed := maxf(float(candidate.get("speed", 1.0)), 1.0)
	var eta := position.distance_to(ball_position) / speed
	var reachability := 1.0 / (1.0 + eta)
	var direction_score := 0.0
	if input_direction.length_squared() > 0.001:
		direction_score = maxf(position.direction_to(ball_position).dot(input_direction.normalized()), 0.0)
	var possession_bonus := 3.0 if bool(candidate.get("has_ball", false)) else 0.0
	var defensive_bonus := 0.35 if str(candidate.get("tactical_role", "")) == "PRESS" else 0.0
	return possession_bonus + reachability + direction_score * 0.3 + defensive_bonus
