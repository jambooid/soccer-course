class_name PlayerStateTackling
extends PlayerState

const DURATION_PRIOR_RECOVERY := 200
const GROUND_FRICTION := 250.0
const ActionPhaseTimelineScript := preload("res://utils/action_phase_timeline.gd")

var is_tackle_complete := false
var tackle_timeline: ActionPhaseTimeline

func _enter_tree() -> void:
	animation_player.play("tackle")
	tackle_damage_emitter_area.monitoring = true
	tackle_timeline = ActionPhaseTimelineScript.profile("TACKLE")

func _physics_process(delta: float) -> void:
	player.velocity = player.velocity.move_toward(Vector2.ZERO, delta * GROUND_FRICTION)
	if tackle_timeline != null:
		tackle_timeline.advance(delta)
	if tackle_timeline != null and tackle_timeline.phase() == ActionPhaseTimeline.Phase.COMPLETE:
		transition_state(Player.State.RECOVERING)

func _exit_tree() -> void:
	tackle_damage_emitter_area.monitoring = false

func is_contact_active() -> bool:
	return tackle_timeline != null and tackle_timeline.can_contact()
