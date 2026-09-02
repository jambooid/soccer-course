class_name MatchSimulation
extends RefCounted

const MatchSnapshotScript := preload("res://utils/match_snapshot.gd")
const SeededRngScript := preload("res://utils/seeded_rng.gd")

const TICKS_PER_SECOND := 60
const TICK_SECONDS := 1.0 / TICKS_PER_SECOND
const GRAVITY := 600.0

var snapshot
var rng
var _accumulator := 0.0

func _init(initial_seed: int = 0, initial_snapshot: RefCounted = null) -> void:
	snapshot = initial_snapshot.clone() if initial_snapshot != null else MatchSnapshotScript.new()
	snapshot.match_seed = initial_seed
	rng = SeededRngScript.new(initial_seed)
	snapshot.rng_state = rng.get_state()

func advance(input_frames: Array = []) -> RefCounted:
	for frame in input_frames:
		if frame.tick == snapshot.tick:
			snapshot.events.append({"tick": snapshot.tick, "type": "input", "player_id": frame.player_id})
	_step_ball()
	snapshot.tick += 1
	snapshot.rng_state = rng.get_state()
	return snapshot.clone()

func advance_render(render_delta: float, input_frames: Array = []) -> Array:
	_accumulator += maxf(render_delta, 0.0)
	var snapshots: Array = []
	while _accumulator + 0.000001 >= TICK_SECONDS:
		_accumulator -= TICK_SECONDS
		snapshots.append(advance(input_frames))
	return snapshots

func resolve_seeded_event(event_type: String, probability: float) -> bool:
	var roll: float = rng.randf()
	var resolved: bool = roll < clampf(probability, 0.0, 1.0)
	snapshot.events.append({
		"tick": snapshot.tick,
		"type": event_type,
		"roll": roll,
		"resolved": resolved,
	})
	snapshot.rng_state = rng.get_state()
	return resolved

func _step_ball() -> void:
	var position: Vector2 = snapshot.ball.position
	var velocity: Vector2 = snapshot.ball.velocity
	position += velocity * TICK_SECONDS
	snapshot.ball.position = position
	if snapshot.ball.height > 0.0 or snapshot.ball.height_velocity > 0.0:
		snapshot.ball.height_velocity -= GRAVITY * TICK_SECONDS
		snapshot.ball.height += snapshot.ball.height_velocity * TICK_SECONDS
		if snapshot.ball.height <= 0.0:
			snapshot.ball.height = 0.0
			snapshot.ball.height_velocity = 0.0
