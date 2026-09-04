class_name MatchSnapshot
extends RefCounted

var tick := 0
var match_seed := 0
var rng_state := 0
var ball := {
		"position": Vector2.ZERO,
		"velocity": Vector2.ZERO,
		"world_position": Vector3.ZERO,
		"world_velocity": Vector3.ZERO,
		"height": 0.0,
		"height_velocity": 0.0,
		"grounded": true,
		"bounce_count": 0,
		"carrier_id": -1,
}
var players: Array[Dictionary] = []
var events: Array[Dictionary] = []

func clone() -> RefCounted:
	var result: RefCounted = get_script().new()
	result.tick = tick
	result.match_seed = match_seed
	result.rng_state = rng_state
	result.ball = ball.duplicate(true)
	result.players = players.duplicate(true)
	result.events = events.duplicate(true)
	return result

func tick_hash() -> int:
	return _serialize().hash()

func to_dictionary() -> Dictionary:
	return {
		"tick": tick,
		"match_seed": match_seed,
		"rng_state": rng_state,
		"ball": _vector_dictionary(ball),
		"players": _sort_player_snapshots(players),
		"events": events.duplicate(true),
	}

func _serialize() -> String:
	return JSON.stringify(to_dictionary(), "", true)

func _vector_dictionary(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	for key in ["position", "velocity", "world_position", "world_velocity"]:
		if result.get(key) is Vector2:
			var vector: Vector2 = result[key]
			result[key] = {"x": vector.x, "y": vector.y}
		elif result.get(key) is Vector3:
			var vector_3d: Vector3 = result[key]
			result[key] = {"x": vector_3d.x, "y": vector_3d.y, "z": vector_3d.z}
	return result

func _sort_player_snapshots(value: Array[Dictionary]) -> Array[Dictionary]:
	var sorted := value.duplicate(true)
	sorted.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("id", -1)) < int(right.get("id", -1))
	)
	return sorted
