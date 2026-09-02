class_name ActionPhaseTimeline
extends RefCounted

enum Phase { STARTUP, ACTIVE, RECOVERY, COMPLETE }

var startup: float
var active: float
var recovery: float
var elapsed := 0.0

func _init(startup_seconds: float, active_seconds: float, recovery_seconds: float) -> void:
	startup = maxf(startup_seconds, 0.0)
	active = maxf(active_seconds, 0.0)
	recovery = maxf(recovery_seconds, 0.0)

func advance(delta: float) -> int:
	elapsed += maxf(delta, 0.0)
	return phase()

func phase() -> int:
	if elapsed < startup:
		return Phase.STARTUP
	if elapsed < startup + active:
		return Phase.ACTIVE
	if elapsed < startup + active + recovery:
		return Phase.RECOVERY
	return Phase.COMPLETE

func can_contact() -> bool:
	return phase() == Phase.ACTIVE

static func profile(action: String) -> ActionPhaseTimeline:
	match action:
		"PASS": return ActionPhaseTimeline.new(0.08, 0.06, 0.16)
		"SHOT": return ActionPhaseTimeline.new(0.12, 0.07, 0.22)
		"TACKLE": return ActionPhaseTimeline.new(0.10, 0.16, 0.24)
		"AERIAL": return ActionPhaseTimeline.new(0.10, 0.10, 0.20)
		"GOALKEEPER": return ActionPhaseTimeline.new(0.06, 0.16, 0.28)
		_: return ActionPhaseTimeline.new(0.0, 0.0, 0.0)
