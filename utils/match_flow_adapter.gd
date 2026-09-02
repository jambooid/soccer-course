class_name MatchFlowAdapter
extends RefCounted

const BallInteractionResolverScript := preload("res://utils/ball_interaction_resolver.gd")

## State-machine adapter used by live actions and headless scenarios. Every
## action is reduced to one resolver commit, so a contact cannot emit duplicate
## possession changes while old/new state nodes overlap.
static func commit(snapshot, kind: int, player_id: int, data: Dictionary = {}) -> Dictionary:
	var intent := BallInteractionResolverScript.create_intent(kind, player_id, data)
	return BallInteractionResolverScript.resolve_and_commit(snapshot, [intent])

static func playable_flow(snapshot) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	events.append(commit(snapshot, BallInteractionResolverScript.Kind.CONTROL, 1, {"source": "kickoff"}))
	events.append(commit(snapshot, BallInteractionResolverScript.Kind.KICK, 1, {"source": "pass"}))
	events.append(commit(snapshot, BallInteractionResolverScript.Kind.CONTROL, 2, {"source": "receipt"}))
	events.append(commit(snapshot, BallInteractionResolverScript.Kind.KICK, 2, {"source": "shot"}))
	events.append(commit(snapshot, BallInteractionResolverScript.Kind.COLLECT, 12, {"source": "save"}))
	events.append(commit(snapshot, BallInteractionResolverScript.Kind.TACKLE, 4, {"source": "tackle"}))
	return events
