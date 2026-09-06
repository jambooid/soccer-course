class_name MatchFeelRules
extends RefCounted

const Coordinate3D := preload("res://utils/pitch_coordinate_3d.gd")

## Fixed-tick primitives shared by the match runtime and calibration scenarios.
## They only return value dictionaries so a scenario can serialize and compare
## an interaction without consulting scene or presentation state.

const DEFAULT_TICK_RATE := 60.0
const DEFAULT_CONTROL_RADIUS := 1.18
const DEFAULT_RECEIVER_ASSIST_TICKS := 2
const DEFAULT_INTERCEPTION_MARGIN_TICKS := 2
const GOALKEEPER_COLLECT_RADIUS := 1.35
const GOALKEEPER_DIVE_RADIUS := 3.25
const GOALKEEPER_COVERAGE_GAP := 3.55
const GOALKEEPER_MIN_DIVE_TICKS := 3

static func goalkeeper_outcome(goalkeeper: Dictionary, ball_position: Vector3,
		ball_velocity: Vector3, goal_x: float, tick_rate: float = DEFAULT_TICK_RATE) -> Dictionary:
	var horizontal := Coordinate3D.ground(ball_velocity)
	var distance_to_goal := absf(goal_x - ball_position.x)
	var approach_speed := absf(horizontal.x)
	var arrival_ticks := int(ceil(distance_to_goal / maxf(approach_speed, 0.1) * tick_rate))
	var target_z := ball_position.z
	if approach_speed > 0.001:
		target_z += ball_velocity.z / approach_speed * distance_to_goal
	var lateral_distance := absf(target_z - float((goalkeeper.get("position", Vector3.ZERO) as Vector3).z))
	var recovery_ticks := maxi(int(goalkeeper.get("keeper_recovery_ticks", 0)), 0)
	var low_ball := ball_position.y <= 1.10 and ball_velocity.y <= 1.5
	var gap_hit := lateral_distance > GOALKEEPER_COVERAGE_GAP
	var late := arrival_ticks < GOALKEEPER_MIN_DIVE_TICKS or recovery_ticks > 0
	var outcome := "hold"
	if gap_hit:
		outcome = "gap"
	elif late:
		outcome = "hold"
	elif low_ball and lateral_distance <= GOALKEEPER_COLLECT_RADIUS:
		outcome = "collect"
	elif lateral_distance <= GOALKEEPER_DIVE_RADIUS:
		outcome = "parry" if low_ball else "dive"
	return {"outcome": outcome, "arrival_ticks": arrival_ticks,
		"lateral_distance": lateral_distance, "target_z": target_z, "low_ball": low_ball,
		"gap_hit": gap_hit, "late": late}

static func make_action_intent(action: String, direction: Vector3, source_tick: int,
		buffer_ticks: int) -> Dictionary:
	return {"action": action, "direction": _vector_record(Coordinate3D.ground(direction)),
		"source_tick": source_tick, "expiry_tick": source_tick + maxi(buffer_ticks, 0)}

static func intent_direction(intent: Dictionary) -> Vector3:
	var value: Array = intent.get("direction", [0.0, 0.0, 0.0])
	if value.size() != 3:
		return Vector3.ZERO
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func queue_action_intent(current: Dictionary, incoming: Dictionary) -> Dictionary:
	## A single slot deliberately replaces the prior command. This prevents a
	## buffered pass followed by a buffered tackle from firing as a macro.
	if incoming.is_empty():
		return current.duplicate(true)
	return incoming.duplicate(true)

static func intent_is_expired(intent: Dictionary, tick: int) -> bool:
	return intent.is_empty() or tick > int(intent.get("expiry_tick", -1))

static func contact_window(action: String, first_tick: int, last_tick: int) -> Dictionary:
	return {"action": action, "first_tick": mini(first_tick, last_tick),
		"last_tick": maxi(first_tick, last_tick)}

static func can_consume_intent(intent: Dictionary, tick: int, window: Dictionary) -> bool:
	return not intent_is_expired(intent, tick) and str(intent.get("action", "")) == \
		str(window.get("action", "")) and tick >= int(window.get("first_tick", 0)) and \
		tick <= int(window.get("last_tick", -1))

static func consume_intent_at_window(intent: Dictionary, tick: int, window: Dictionary) -> Dictionary:
	if intent_is_expired(intent, tick):
		return {"intent": {}, "consumed": false, "expired": not intent.is_empty()}
	if can_consume_intent(intent, tick, window):
		return {"intent": intent.duplicate(true), "consumed": true, "expired": false}
	return {"intent": intent.duplicate(true), "consumed": false, "expired": false}

static func predict_receive_area(receiver_position: Vector3, receiver_velocity: Vector3,
		ball_position: Vector3, ball_velocity: Vector3, maximum_lead_seconds: float = 0.72) -> Vector3:
	var ball_speed := Coordinate3D.ground(ball_velocity).length()
	var distance := Coordinate3D.ground(ball_position - receiver_position).length()
	var lead_seconds := clampf(distance / maxf(ball_speed, 0.001), 0.0,
		maxf(maximum_lead_seconds, 0.0))
	return Coordinate3D.ground(receiver_position + Coordinate3D.ground(receiver_velocity) * lead_seconds)

static func estimate_arrival_ticks(player: Dictionary, target_position: Vector3,
		tick_rate: float = DEFAULT_TICK_RATE, control_radius: float = DEFAULT_CONTROL_RADIUS) -> int:
	var position: Vector3 = Coordinate3D.ground(player.get("position", Vector3.ZERO))
	var distance := maxf(position.distance_to(Coordinate3D.ground(target_position)) - \
		maxf(control_radius, 0.0), 0.0)
	var speed := maxf(float(player.get("arrival_speed", player.get("top_speed", 8.8))), 0.1)
	var action_lock_ticks := maxi(int(player.get("action_lock_ticks", 0)), 0)
	return action_lock_ticks + int(ceil(distance / speed * maxf(tick_rate, 0.001)))

static func resolve_arrival_race(receiver: Dictionary, interceptors: Array,
		target_position: Vector3, receiver_assist_ticks: int = DEFAULT_RECEIVER_ASSIST_TICKS,
		interception_margin_ticks: int = DEFAULT_INTERCEPTION_MARGIN_TICKS) -> Dictionary:
	var receiver_id := int(receiver.get("id", -1))
	var receiver_arrival := estimate_arrival_ticks(receiver, target_position)
	var candidates: Array = [{"id": receiver_id, "team_home": bool(receiver.get("home", false)),
		"arrival_ticks": receiver_arrival, "role": "receiver"}]
	for interceptor: Dictionary in interceptors:
		candidates.append({"id": int(interceptor.get("id", -1)),
			"team_home": bool(interceptor.get("home", false)),
			"arrival_ticks": estimate_arrival_ticks(interceptor, target_position), "role": "interceptor"})
	candidates.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		if int(first.arrival_ticks) == int(second.arrival_ticks):
			return int(first.id) < int(second.id)
		return int(first.arrival_ticks) < int(second.arrival_ticks)
	)
	var earliest_interceptor: Dictionary = {}
	for candidate: Dictionary in candidates:
		if str(candidate.role) == "interceptor":
			earliest_interceptor = candidate
			break
	var interceptor_arrival := int(earliest_interceptor.get("arrival_ticks", -1))
	var adjusted_receiver_arrival := receiver_arrival - maxi(receiver_assist_ticks, 0)
	var interception_wins := not earliest_interceptor.is_empty() and \
		interceptor_arrival + maxi(interception_margin_ticks, 0) < adjusted_receiver_arrival
	var tie := false
	for index in range(1, candidates.size()):
		if int(candidates[index - 1].arrival_ticks) == int(candidates[index].arrival_ticks):
			tie = true
			break
	var winner: Dictionary = earliest_interceptor if interception_wins else candidates.filter(
		func(candidate: Dictionary) -> bool: return str(candidate.role) == "receiver")[0]
	return {"winner_id": int(winner.id), "outcome": "interception" if interception_wins else "receive",
		"receiver_arrival_ticks": receiver_arrival, "interceptor_arrival_ticks": interceptor_arrival,
		"arrival_delta_ticks": interceptor_arrival - receiver_arrival if interceptor_arrival >= 0 else -1,
		"tie": tie, "candidates": candidates}

static func first_touch_state(receiver: Dictionary, ball_position: Vector3, incoming_velocity: Vector3,
		pressure: float, start_tick: int) -> Dictionary:
	var incoming := Coordinate3D.ground(incoming_velocity)
	var incoming_speed := incoming.length()
	var direction := incoming.normalized()
	if direction.is_zero_approx():
		direction = Coordinate3D.ground(receiver.get("facing", Vector3.RIGHT)).normalized()
	if direction.is_zero_approx():
		direction = Vector3.RIGHT
	var technique := clampf(float(receiver.get("technique", 60.0)), 30.0, 98.0)
	var quality := (technique - 30.0) / 68.0
	var normalized_pressure := clampf(pressure, 0.0, 1.0)
	var settle_distance := clampf(0.16 + incoming_speed * 0.026 - quality * 0.08 +
		normalized_pressure * 0.22, 0.12, 0.94)
	var duration_ticks := int(round(clampf(4.0 + incoming_speed * 0.28 +
		normalized_pressure * 5.0 - quality * 1.8, 3.0, 18.0)))
	var outcome := "trap" if incoming_speed <= 4.0 else "settle"
	if normalized_pressure >= 0.70:
		outcome = "contested_loose"
	elif normalized_pressure >= 0.35:
		outcome = "pressured_settle"
	return {"state": "first_touch", "start_tick": start_tick,
		"end_tick": start_tick + duration_ticks, "duration_ticks": duration_ticks,
		"settle_position": _vector_record(Coordinate3D.ground(ball_position) + direction * settle_distance),
		"incoming_speed": incoming_speed, "pressure": normalized_pressure, "outcome": outcome}

static func calibration_metric(tick: int, action: String, source_id: int, target_id: int,
		direction: Vector3, contact_window_record: Dictionary, expected_arrival: int,
		actual_arrival: int, outcome: String, extra: Dictionary = {}) -> Dictionary:
	var record := {"tick": tick, "action": action, "source_id": source_id, "target_id": target_id,
		"direction": _vector_record(Coordinate3D.ground(direction)),
		"contact_window": contact_window_record.duplicate(true), "expected_arrival": expected_arrival,
		"actual_arrival": actual_arrival, "arrival_delta": actual_arrival - expected_arrival,
		"outcome": outcome}
	for key in extra:
		record[key] = extra[key]
	return record

static func _vector_record(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
