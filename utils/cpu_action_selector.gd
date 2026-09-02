class_name CpuActionSelector
extends RefCounted

## Deterministic CPU action arbitration. Callers supply already-evaluated
## reachability/rule facts, keeping scene queries outside this pure selector.
static func select(actions: Array[Dictionary]) -> Dictionary:
	var eligible := actions.filter(func(action: Dictionary) -> bool:
		return bool(action.get("eligible", false)) \
			and bool(action.get("reachable", false)) \
			and bool(action.get("rule_legal", false))
	)
	if eligible.is_empty():
		return {"kind": "RETAIN"}
	eligible.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_utility := float(left.get("utility", -INF))
		var right_utility := float(right.get("utility", -INF))
		if not is_equal_approx(left_utility, right_utility):
			return left_utility > right_utility
		var left_eta := float(left.get("eta", INF))
		var right_eta := float(right.get("eta", INF))
		if not is_equal_approx(left_eta, right_eta):
			return left_eta < right_eta
		return str(left.get("kind", "")) < str(right.get("kind", ""))
	)
	return eligible[0].duplicate(true)

static func pass_utility(quality: float, eta: float, interception_risk: float, technique: float) -> float:
	return clampf(quality * 0.65 + technique / 100.0 * 0.2 \
		- clampf(eta / 2.0, 0.0, 0.25) - clampf(interception_risk, 0.0, 1.0) * 0.5,
		0.0, 1.0)

static func shot_utility(distance_to_goal: float, shot_range: float, shooting: float, pressure: float) -> float:
	return clampf((1.0 - clampf(distance_to_goal / shot_range, 0.0, 1.0)) * 0.5 \
		+ shooting / 100.0 * 0.4 - clampf(pressure, 0.0, 1.0) * 0.35,
		0.0, 1.0)
