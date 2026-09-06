class_name MatchEvent
extends RefCounted

## Immutable-at-the-boundary event. Consumers receive copies of the payload.

var name := ""
var tick := 0
var payload: Dictionary = {}

func _init(event_name: String = "", event_tick: int = 0, event_payload: Dictionary = {}) -> void:
	name = event_name
	tick = event_tick
	payload = event_payload.duplicate(true)

func copy() -> MatchEvent:
	return MatchEvent.new(name, tick, payload)

func as_dict() -> Dictionary:
	return {"name": name, "tick": tick, "payload": payload.duplicate(true)}
