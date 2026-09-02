class_name SeededRng
extends RefCounted

## Match-scoped random source. Keep gameplay randomness replayable by passing
## an instance through simulation code instead of calling global randf().

var _generator := RandomNumberGenerator.new()
var seed_value: int

func _init(initial_seed: int = 0) -> void:
	seed_value = initial_seed
	_generator.seed = initial_seed

func randf() -> float:
	return _generator.randf()

func randf_range(from: float, to: float) -> float:
	return _generator.randf_range(from, to)

func randi_range(from: int, to: int) -> int:
	return _generator.randi_range(from, to)

func get_state() -> int:
	return _generator.state

func set_state(value: int) -> void:
	_generator.state = value
