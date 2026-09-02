class_name GoalkeeperDecisionPolicy
extends RefCounted

const BallTrajectoryScript := preload("res://utils/ball_trajectory.gd")

enum Kind { LINE, SET, RUSH, CLAIM, DIVE, HOLD, DISTRIBUTE_THROW, DISTRIBUTE_KICK }

## Pure goalkeeper decision policy. Scene code supplies only current match facts;
## trajectory predictions and deterministic choice ordering live here.
static func decide(data: Dictionary) -> Dictionary:
	if bool(data.get("holding_ball", false)):
		if float(data.get("held_seconds", 0.0)) >= float(data.get("distribution_delay", 1.5)):
			return {"kind": Kind.DISTRIBUTE_KICK if bool(data.get("distribution_long", false)) else Kind.DISTRIBUTE_THROW}
		return {"kind": Kind.HOLD}

	var prediction := predict(data)
	if bool(data.get("can_collect_now", false)):
		return {"kind": Kind.CLAIM, "target": data.get("ball_position", Vector2.ZERO), "prediction": prediction}
	if bool(prediction.get("goal_bound", false)):
		var keeper_eta := float(prediction.get("keeper_eta", INF))
		var ball_eta := float(prediction.get("goal_eta", INF))
		var dive_range := float(data.get("dive_range", 0.0))
		var keeper_position: Vector2 = data.get("keeper_position", Vector2.ZERO)
		var target: Vector2 = prediction.get("goal_position", Vector2.ZERO)
		if keeper_position.distance_to(target) <= dive_range and keeper_eta > ball_eta:
			return {"kind": Kind.DIVE, "target": target, "prediction": prediction}
		return {"kind": Kind.SET, "target": target, "prediction": prediction}
	if bool(data.get("opponent_carrier", false)) and bool(data.get("inside_rush_zone", false)):
		return {"kind": Kind.RUSH, "target": prediction.get("intercept_position", Vector2.ZERO), "prediction": prediction}
	if bool(data.get("inside_rush_zone", false)) \
			and float(prediction.get("keeper_eta", INF)) <= float(prediction.get("intercept_eta", INF)):
		return {"kind": Kind.RUSH, "target": prediction.get("intercept_position", Vector2.ZERO), "prediction": prediction}
	return {"kind": Kind.LINE, "target": prediction.get("line_position", Vector2.ZERO), "prediction": prediction}

static func predict(data: Dictionary) -> Dictionary:
	var ball_position: Vector2 = data.get("ball_position", Vector2.ZERO)
	var ball_velocity: Vector2 = data.get("ball_velocity", Vector2.ZERO)
	var keeper_position: Vector2 = data.get("keeper_position", Vector2.ZERO)
	var goal_position: Vector2 = data.get("goal_position", Vector2.ZERO)
	var goal_top := float(data.get("goal_top", goal_position.y))
	var goal_bottom := float(data.get("goal_bottom", goal_position.y))
	var friction := float(data.get("friction", 0.0))
	var goal_eta := BallTrajectoryScript.time_to_axis_position(
		ball_position.x, ball_velocity.x, goal_position.x, friction)
	var goal_target := ball_position if is_inf(goal_eta) else BallTrajectoryScript.ground_position_after(
		ball_position, ball_velocity, friction, goal_eta)
	var goal_height := _height_at(data, goal_eta) if not is_inf(goal_eta) else INF
	var goal_bound := not is_inf(goal_eta) and goal_target.y >= goal_top and goal_target.y <= goal_bottom \
		and goal_height <= float(data.get("save_height_max", 58.0))
	var landing_eta := BallTrajectoryScript.landing_time(float(data.get("ball_height", 0.0)),
		float(data.get("height_velocity", 0.0)), float(data.get("gravity", 600.0)))
	var intercept_eta := goal_eta if not is_inf(goal_eta) else landing_eta
	var intercept_position := goal_target if not is_inf(goal_eta) else BallTrajectoryScript.ground_position_after(
		ball_position, ball_velocity, friction, landing_eta)
	var keeper_speed := maxf(float(data.get("keeper_speed", 0.0)), 1.0)
	return {
		"goal_eta": goal_eta,
		"goal_position": goal_target,
		"goal_bound": goal_bound,
		"intercept_eta": intercept_eta,
		"intercept_position": intercept_position,
		"keeper_eta": keeper_position.distance_to(intercept_position) / keeper_speed,
		"line_position": Vector2(goal_position.x, clampf(intercept_position.y, goal_top, goal_bottom)),
	}

static func select_distribution(options: Array[Dictionary]) -> Dictionary:
	var eligible := options.filter(func(option: Dictionary) -> bool:
		return bool(option.get("rule_legal", false)) \
			and float(option.get("receiver_eta", INF)) <= float(option.get("ball_eta", INF)) \
			and float(option.get("opponent_eta", INF)) > float(option.get("ball_eta", INF)))
	eligible.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_utility := float(left.get("utility", -INF))
		var right_utility := float(right.get("utility", -INF))
		if not is_equal_approx(left_utility, right_utility):
			return left_utility > right_utility
		return int(left.get("player_id", 0)) < int(right.get("player_id", 0))
	)
	return eligible[0].duplicate(true) if not eligible.is_empty() else {}

static func _height_at(data: Dictionary, time: float) -> float:
	return maxf(float(data.get("ball_height", 0.0)) + float(data.get("height_velocity", 0.0)) * time \
		- 0.5 * float(data.get("gravity", 600.0)) * time * time, 0.0)
