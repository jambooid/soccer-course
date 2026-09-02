class_name TackleEligibilityPolicy
extends RefCounted

enum Outcome { MISS, INTERCEPT, TACKLE_WIN }

static func resolve(data: Dictionary) -> Dictionary:
	var distance := float(data.get("distance", INF))
	var ball_first := bool(data.get("ball_first", false))
	var direction_dot := float(data.get("direction_dot", -1.0))
	var approach_speed := float(data.get("approach_speed", 0.0))
	var defense := float(data.get("defense", 0.0))
	var technique := float(data.get("technique", 0.0))
	if not ball_first:
		return {"outcome": Outcome.MISS, "reason": "ball_not_first"}
	if bool(data.get("sliding", false)):
		if distance > 20.0 or approach_speed < 45.0:
			return {"outcome": Outcome.MISS, "reason": "slide_range_or_speed"}
		if direction_dot < 0.25:
			return {"outcome": Outcome.MISS, "reason": "slide_bad_direction"}
		if defense + approach_speed * 0.25 < technique:
			return {"outcome": Outcome.MISS, "reason": "slide_lost_attributes"}
		return {"outcome": Outcome.TACKLE_WIN, "reason": "slide_ball_first"}
	if distance > 14.0 or approach_speed < 5.0:
		return {"outcome": Outcome.MISS, "reason": "intercept_range_or_speed"}
	if direction_dot < 0.5:
		return {"outcome": Outcome.MISS, "reason": "intercept_bad_direction"}
	if defense < technique * 0.55:
		return {"outcome": Outcome.MISS, "reason": "intercept_lost_attributes"}
	return {"outcome": Outcome.INTERCEPT, "reason": "standing_ball_first"}
