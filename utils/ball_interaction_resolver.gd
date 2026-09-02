class_name BallInteractionResolver
extends RefCounted

## Deterministic arbitration for same-tick ball interaction intents.

static func resolve(intents: Array[Dictionary]) -> Dictionary:
	if intents.is_empty():
		return {}
	var candidates := intents.filter(func(intent: Dictionary) -> bool:
		return bool(intent.get("eligible", false)))
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_priority := int(left.get("priority", 0))
		var right_priority := int(right.get("priority", 0))
		if left_priority != right_priority:
			return left_priority > right_priority
		var left_distance := float(left.get("distance", INF))
		var right_distance := float(right.get("distance", INF))
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		return int(left.get("player_id", -1)) < int(right.get("player_id", -1))
	)
	return candidates[0].duplicate(true)
