class_name BallInteractionResolver
extends RefCounted

## Deterministic arbitration for same-tick ball interaction intents.

enum Kind { CONTROL, INTERCEPT, TACKLE, DEFLECT, COLLECT, KICK }

const PRIORITY := {
	Kind.CONTROL: 10,
	Kind.INTERCEPT: 20,
	Kind.TACKLE: 30,
	Kind.DEFLECT: 40,
	Kind.COLLECT: 50,
	Kind.KICK: 60,
}

static func create_intent(kind: Kind, player_id: int, data: Dictionary = {}) -> Dictionary:
	var intent := data.duplicate(true)
	intent.kind = kind
	intent.player_id = player_id
	intent.priority = int(intent.get("priority", PRIORITY[kind]))
	intent.eligible = bool(intent.get("eligible", true)) \
		and bool(intent.get("active_window", true)) \
		and bool(intent.get("height_eligible", true))
	intent.distance = float(intent.get("distance", INF))
	return intent

static func resolve(intents: Array[Dictionary]) -> Dictionary:
	if intents.is_empty():
		return {}
	var candidates := intents.filter(func(intent: Dictionary) -> bool:
		return bool(intent.get("eligible", false)) \
			and bool(intent.get("active_window", true)) \
			and bool(intent.get("height_eligible", true)) \
			and int(intent.get("player_id", -1)) >= 0)
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

## The only authority that writes a resolved interaction into a simulation
## snapshot. Capture actions gain one carrier; ball-striking actions release it.
static func resolve_and_commit(snapshot, intents: Array[Dictionary]) -> Dictionary:
	var resolved := resolve(intents)
	if resolved.is_empty():
		return {}
	var kind := int(resolved.kind)
	if kind == Kind.CONTROL or kind == Kind.INTERCEPT \
			or kind == Kind.TACKLE or kind == Kind.COLLECT:
		snapshot.ball.carrier_id = int(resolved.player_id)
	else:
		snapshot.ball.carrier_id = -1
	var event := {
		"tick": snapshot.tick,
		"type": "ball_interaction",
		"kind": kind,
		"player_id": int(resolved.player_id),
		"carrier_id": int(snapshot.ball.carrier_id),
	}
	snapshot.events.append(event)
	return event
