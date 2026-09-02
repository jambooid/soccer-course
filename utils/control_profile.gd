class_name ControlProfile
extends RefCounted

enum Kind { FOOT, CHEST, HEAD, VOLLEY, TACKLE, GOALKEEPER_HANDS }

static func can_connect(kind: Kind, height: float, vertical_speed: float = 0.0) -> bool:
	var h := maxf(height, 0.0)
	match kind:
		Kind.FOOT:
			return h <= 10.0
		Kind.CHEST:
			return h >= 8.0 and h <= 34.0
		Kind.HEAD, Kind.VOLLEY:
			return h >= 18.0 and h <= 58.0
		Kind.TACKLE:
			return h <= 8.0 and absf(vertical_speed) < 160.0
		Kind.GOALKEEPER_HANDS:
			return h <= 28.0
	return false

static func range_for(kind: Kind) -> float:
	match kind:
		Kind.FOOT: return 14.0
		Kind.CHEST: return 18.0
		Kind.HEAD, Kind.VOLLEY: return 16.0
		Kind.TACKLE: return 20.0
		Kind.GOALKEEPER_HANDS: return 24.0
	return 0.0
