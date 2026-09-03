class_name PlayerFootprintResolver
extends RefCounted

## Deterministic ground-plane separation for player volume.
## Input dictionaries require `id` and `position`; `radius` is optional.

static func separate(players: Array[Dictionary], default_radius: float = 14.0,
	iterations: int = 2) -> Array[Dictionary]:
	var result := players.duplicate(true)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("id", 0)) < int(right.get("id", 0)))
	var pass_count := maxi(iterations, 1)
	for _pass in range(pass_count):
		for i in range(result.size()):
			for j in range(i + 1, result.size()):
				var a: Dictionary = result[i]
				var b: Dictionary = result[j]
				var a_pos: Vector2 = a.get("position", Vector2.ZERO)
				var b_pos: Vector2 = b.get("position", Vector2.ZERO)
				var delta := b_pos - a_pos
				var distance := delta.length()
				var min_distance := float(a.get("radius", default_radius)) \
					+ float(b.get("radius", default_radius))
				if distance >= min_distance:
					continue
				var normal := delta / distance if distance > 0.001 \
					else (Vector2.RIGHT if int(a.get("id", 0)) < int(b.get("id", 0)) else Vector2.LEFT)
				var correction := (min_distance - distance) * 0.5
				a["position"] = a_pos - normal * correction
				b["position"] = b_pos + normal * correction
				result[i] = a
				result[j] = b
	return result
