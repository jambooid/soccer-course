class_name MatchInputFrame
extends RefCounted

var tick := 0
var player_id := -1
var movement := Vector2.ZERO
var pressed_actions: Array[String] = []

func to_dictionary() -> Dictionary:
	return {
		"tick": tick,
		"player_id": player_id,
		"movement": {"x": movement.x, "y": movement.y},
		"pressed_actions": pressed_actions.duplicate(),
	}
