class_name GoalkeeperInteractionPolicy
extends RefCounted

const BallInteractionResolverScript := preload("res://utils/ball_interaction_resolver.gd")
const ControlProfileScript := preload("res://utils/control_profile.gd")

const CATCH_SPEED_MAX := 180.0

## Returns one eligible goalkeeper interaction intent, or an empty dictionary.
## The caller supplies scene-derived area and release-lock data so this policy
## remains deterministic and independent from Godot nodes/callback ordering.
static func resolve(player_id: int, data: Dictionary) -> Dictionary:
	var in_penalty_area := bool(data.get("in_penalty_area", false))
	var release_locked := bool(data.get("release_locked", false))
	var teammate_carrier := bool(data.get("teammate_carrier", false))
	var height := float(data.get("height", 0.0))
	var speed := float(data.get("speed", 0.0))
	var distance := float(data.get("distance", INF))
	var catch_range := ControlProfileScript.range_for(ControlProfileScript.Kind.GOALKEEPER_HANDS)
	var height_eligible := ControlProfileScript.can_connect(
		ControlProfileScript.Kind.GOALKEEPER_HANDS, height)
	var can_reach := distance <= catch_range
	var base_eligible := in_penalty_area and not release_locked and not teammate_carrier and can_reach
	if base_eligible and height_eligible and speed <= CATCH_SPEED_MAX:
		return BallInteractionResolverScript.create_intent(
			BallInteractionResolverScript.Kind.COLLECT, player_id,
			{"distance": distance})
	if base_eligible and bool(data.get("allow_deflect", true)) and height <= 58.0:
		return BallInteractionResolverScript.create_intent(
			BallInteractionResolverScript.Kind.DEFLECT, player_id,
			{"distance": distance})
	return {}
