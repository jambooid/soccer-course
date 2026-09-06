class_name Match3DGame
extends Node3D

const Rules := preload("res://utils/match3d_rules.gd")
const BallTrajectory3DScript := preload("res://utils/ball_trajectory_3d.gd")
const BallPhysics3D := preload("res://utils/ball_physics_3d_constants.gd")
const DribblePhysics3D := preload("res://utils/dribble_physics_3d.gd")
const Coordinate3D := preload("res://utils/pitch_coordinate_3d.gd")
const Flow := preload("res://utils/match_flow.gd")
const MatchFlowControllerScript := preload("res://utils/match_flow_controller.gd")
const MatchEventScript := preload("res://utils/match_event.gd")
const MatchSnapshotScript := preload("res://utils/match_snapshot.gd")
const ReplayBufferScript := preload("res://utils/replay_buffer.gd")
const CameraDirectorScript := preload("res://scenes/world3d/camera_director.gd")
const MatchHUDScript := preload("res://scenes/world3d/match_hud.gd")
const PlayerView := preload("res://scenes/world3d/player_3d_view.gd")
const BallView := preload("res://scenes/world3d/ball_3d_view.gd")
const PASS_SFX := preload("res://assets/sfx/pass.wav")
const SHOT_SFX := preload("res://assets/sfx/shoot.wav")
const TACKLE_SFX := preload("res://assets/sfx/tackle.wav")
const WHISTLE_SFX := preload("res://assets/sfx/whistle.wav")

const HOME_COLOR := Color("1e52b7")
const AWAY_COLOR := Color("d33932")
const KEEPERS_COLOR := Color("e1a420")
const MATCH_SECONDS := 180.0
const KICKOFF_DELAY := 1.4
const SHOOT_CHARGE_SECONDS := 0.75
const FIXED_TICK := 1.0 / 60.0
const CAMERA_BASE_FOCUS := Vector3(42.5, 0.0, 18.0)
const CAMERA_VIEW_OFFSET := Vector3(0.0, 11.5, 8.76)
const CAMERA_BASE_POSITION := CAMERA_BASE_FOCUS + CAMERA_VIEW_OFFSET
const CAMERA_FOLLOW_RESPONSE := 6.0
const CAMERA_FAST_BALL_FOLLOW_RESPONSE := 10.0
const CAMERA_SCREEN_X_OFFSET := 2.36
const CAMERA_SCREEN_Z_OFFSET := 3.20
const CAMERA_CARRIER_LOOKAHEAD_SECONDS := 0.16
const CAMERA_BALL_LOOKAHEAD_SECONDS := 0.18
const CAMERA_BALL_LOOKAHEAD_MAX_DISTANCE := 7.0
const CAMERA_FAST_BALL_SPEED := 12.0
const CAMERA_FOCUS_DEADZONE_X := 0.75
const CAMERA_FOCUS_DEADZONE_Z := 0.45
const CAMERA_FOCUS_X_MIN := 8.0
const CAMERA_FOCUS_X_MAX := Rules.PITCH_SIZE.x - CAMERA_FOCUS_X_MIN
const CAMERA_FOCUS_Z_MIN := 8.0
# The near and side edges of the broadcast frame need more run-off than the
# playable pitch itself. The old margins could leave a carrier or the ball at
# their feet outside the viewport while the camera was clamped at a near corner.
# The pitch's authored stand apron absorbs this extra tracking range.
const CAMERA_FOCUS_Z_MAX := Rules.PITCH_SIZE.z - 4.8
const JOG_DRIBBLE_TOP_SPEED := Rules.PITCH_SIZE.x * 0.5 / 10.0
const FORMATION_BALL_X_WEIGHT := 0.32
const FORMATION_BALL_Z_WEIGHT := 0.34
const PRESSER_SWITCH_MARGIN := 1.18
const PRESSER_APPROACH_DISTANCE := 3.4
const PRESSER_JOCKEY_DISTANCE := 0.92
const AI_TACKLE_DISTANCE := 1.45
const AI_TACKLE_FACING_MIN := -0.35
const TACKLE_RECOVERY_SECONDS := 0.62
const STUMBLE_RECOVERY_SECONDS := 0.95
const PRESSURE_COOLDOWN_SECONDS := 0.34
const HUD_SCALE := 0.25

enum DribblePhase { FREE_ROLL, TURN_ANCHOR, TURNAROUND_ANCHOR }

signal match_event_emitted(event: MatchEvent)

var players: Array[Dictionary] = []
var ball_position := Vector3(Rules.PITCH_SIZE.x * 0.5, 0.0, Rules.PITCH_SIZE.z * 0.5)
var ball_velocity := Vector3.ZERO
var ball_bounce_count := 0
var ball_grounded := true
var ball_flight_time := 0.0
var _simulation_accumulator := 0.0
var _simulation_tick := 0
var _previous_ball_position := ball_position
var _has_previous_ball_position := false
var _sampled_just_pressed: Dictionary = {}
var _sampled_just_released: Dictionary = {}
var carrier_id := -1
var controlled_id := -1
var score_home := 0
var score_away := 0
var match_time := MATCH_SECONDS
var kickoff_timer := KICKOFF_DELAY
var match_flow: MatchFlowController
var replay_buffer: ReplayBuffer
var replay_frames: Array = []
var replay_active := false
var replay_cursor := 0
var replay_tick_timer := 0.0
var last_match_event: RefCounted
var camera_director: RefCounted
var _match_hud: CanvasLayer
var restart_team_home := true
var last_touch_home := true
var action_cooldown := 0.0
var cpu_action_cooldown := 0.65
var cpu_tackle_cooldown := 0.0
var frame_count := 0
var camera_shake := 0.0
var camera_lateral_offset := 0.0
var camera_focus := CAMERA_BASE_FOCUS
var camera_fixed_rotation := Vector3.ZERO
var camera_rotation_initialized := false
var shot_charge := 0.0
var shot_charging := false
var dribble_touch_timer := 0.0
var dribble_loss_timer := 0.0
var dribble_mode := DribblePhysics3D.Mode.JOG
var dribble_touch_count := 0
var dribble_queued_direction := Vector3.ZERO
var dribble_turn_anchor_timer := 0.0
var dribble_turn_anchor_duration := 0.0
var dribble_turn_anchor_direction := Vector3.ZERO
var dribble_turn_anchor_start := Vector2.ZERO
var dribble_turn_anchor_offset := 0.0
var dribble_turn_release_velocity := Vector3.ZERO
var dribble_last_turn_type := DribblePhysics3D.TurnType.NONE
var dribble_phase := DribblePhase.FREE_ROLL
var dribble_45_turn_commit_timer := 0.0
var dribble_45_turn_pending_direction := Vector3.ZERO
var dribble_turn_lock_timer := 0.0
var dribble_turn_locked_direction := Vector3.ZERO
var dribble_turn_start_direction := Vector3.ZERO
var dribble_stop_roll_timer := 0.0
var dribble_stop_roll_start := Vector2.ZERO
var dribble_stop_roll_direction := Vector2.ZERO
var dribble_stop_roll_distance := 0.0
var dribble_stop_roll_carrier_start := Vector3.ZERO
var dribble_stop_roll_ball_target := Vector2.ZERO
var tactical_assignments: Dictionary = {}
var primary_presser_by_team: Dictionary = {"home": -1, "away": -1}
var _views: Dictionary = {}
var _ball_view: Ball3DView
var _score_label: Label
var _clock_label: Label
var _event_label: Label
var _event_timer := 0.0
var _sfx_players: Dictionary = {}
var _power_bar: ProgressBar

func _ready() -> void:
	match_flow = MatchFlowControllerScript.new({"half_duration": MATCH_SECONDS * 0.5,
		"stoppage_duration": 8.0, "presentation_duration": KICKOFF_DELAY,
		"halftime_duration": 2.0})
	replay_buffer = ReplayBufferScript.new(360)
	camera_director = CameraDirectorScript.new()
	_create_match()
	_create_hud()
	_create_audio()
	match_event_emitted.connect(_on_match_event)
	call_deferred("_frame_camera")

func _frame_camera() -> void:
	var camera := get_node_or_null("Camera") as Camera3D
	if camera != null:
		camera_focus = CAMERA_BASE_FOCUS
		camera.position = camera_focus + CAMERA_VIEW_OFFSET
		camera.look_at(camera_focus)
		camera_fixed_rotation = camera.rotation
		camera_rotation_initialized = true

func _update_camera(delta: float) -> void:
	var camera := get_node_or_null("Camera") as Camera3D
	if camera == null:
		return
	if not camera_rotation_initialized:
		_frame_camera()
	# Keep the attacking subject in the lower third. A small deadzone keeps close
	# control stable, while fast loose balls get a quicker response. The far-side
	# focus limit remains deliberately wider than the near-side limit so the
	# camera can follow play into the upper half of the broadcast view.
	if camera_director != null:
		camera_director.advance(delta)
		camera_director.set_replay(replay_active)
	var desired_focus := _camera_desired_focus()
	if camera_director != null:
		desired_focus = _clamp_camera_focus(camera_director.focus_override(desired_focus))
	var deadzone_focus := _camera_focus_after_deadzone(desired_focus)
	camera_focus = camera_focus.lerp(deadzone_focus,
		1.0 - exp(-_camera_follow_response() * delta))
	camera_focus = _clamp_camera_focus(camera_focus)
	camera.position = camera_focus + CAMERA_VIEW_OFFSET
	camera.rotation = camera_fixed_rotation

func _camera_desired_focus() -> Vector3:
	var subject_position := Coordinate3D.ground(ball_position)
	var subject_velocity := Coordinate3D.ground(ball_velocity)
	var attacking_right := last_touch_home
	var carrier := _player_by_id(carrier_id)
	if not carrier.is_empty():
		subject_position = Coordinate3D.ground(carrier.position)
		subject_velocity = Coordinate3D.ground(carrier.velocity)
		attacking_right = bool(carrier.home)
		subject_position += subject_velocity * CAMERA_CARRIER_LOOKAHEAD_SECONDS
	else:
		var ball_lookahead := subject_velocity * CAMERA_BALL_LOOKAHEAD_SECONDS
		if ball_lookahead.length() > CAMERA_BALL_LOOKAHEAD_MAX_DISTANCE:
			ball_lookahead = ball_lookahead.normalized() * CAMERA_BALL_LOOKAHEAD_MAX_DISTANCE
		subject_position += ball_lookahead
		if absf(subject_velocity.x) > 0.1:
			attacking_right = subject_velocity.x > 0.0
	var attack_sign := 1.0 if attacking_right else -1.0
	return _clamp_camera_focus(subject_position + Vector3(
		attack_sign * CAMERA_SCREEN_X_OFFSET, 0.0, CAMERA_SCREEN_Z_OFFSET))

func _camera_focus_after_deadzone(desired_focus: Vector3) -> Vector3:
	var deadzone_focus := camera_focus
	var focus_delta := desired_focus - camera_focus
	# A clamped edge target has no remaining forward tracking room. Do not leave
	# the normal deadzone gap there, or a ball at the near corner can still sit
	# just outside the frame after the camera has otherwise settled.
	var target_at_x_edge := is_equal_approx(desired_focus.x, CAMERA_FOCUS_X_MIN) or \
		is_equal_approx(desired_focus.x, CAMERA_FOCUS_X_MAX)
	var target_at_z_edge := is_equal_approx(desired_focus.z, CAMERA_FOCUS_Z_MIN) or \
		is_equal_approx(desired_focus.z, CAMERA_FOCUS_Z_MAX)
	if target_at_x_edge:
		deadzone_focus.x = desired_focus.x
	elif absf(focus_delta.x) > CAMERA_FOCUS_DEADZONE_X:
		deadzone_focus.x = desired_focus.x - sign(focus_delta.x) * CAMERA_FOCUS_DEADZONE_X
	if target_at_z_edge:
		deadzone_focus.z = desired_focus.z
	elif absf(focus_delta.z) > CAMERA_FOCUS_DEADZONE_Z:
		deadzone_focus.z = desired_focus.z - sign(focus_delta.z) * CAMERA_FOCUS_DEADZONE_Z
	return _clamp_camera_focus(deadzone_focus)

func _camera_follow_response() -> float:
	if carrier_id < 0 and Coordinate3D.ground(ball_velocity).length() >= CAMERA_FAST_BALL_SPEED:
		return CAMERA_FAST_BALL_FOLLOW_RESPONSE
	return CAMERA_FOLLOW_RESPONSE

func _clamp_camera_focus(focus: Vector3) -> Vector3:
	return Vector3(clampf(focus.x, CAMERA_FOCUS_X_MIN, CAMERA_FOCUS_X_MAX), 0.0,
		clampf(focus.z, CAMERA_FOCUS_Z_MIN, CAMERA_FOCUS_Z_MAX))

func _process(delta: float) -> void:
	# Input is sampled once per render frame, while gameplay advances in a
	# deterministic 60 Hz loop. This keeps ball flight independent of V-sync.
	for action in ["p1_pass", "p1_long_pass", "p1_shoot", "p1_through_pass", "p1_special", "p1_pressure", "p1_co_defense", "p1_switch"]:
		_sampled_just_pressed[action] = Input.is_action_just_pressed(action)
		_sampled_just_released[action] = Input.is_action_just_released(action)
	_simulation_accumulator = minf(_simulation_accumulator + delta, 0.25)
	while _simulation_accumulator >= FIXED_TICK:
		_simulation_accumulator -= FIXED_TICK
		_previous_ball_position = ball_position
		_has_previous_ball_position = true
		_simulate_tick(FIXED_TICK)
	_advance_replay(delta)
	_sync_views(true)
	_update_camera(delta)
	_update_hud()

func _simulate_tick(step: float) -> void:
	if match_flow == null:
		return
	if kickoff_timer <= 0.0 and match_flow.phase == Flow.Phase.KICKOFF:
		match_flow.force_live()
	if match_flow.phase == Flow.Phase.KICKOFF:
		_handle_kickoff_input()
		match_flow.advance(step)
		_sync_match_flow_state()
		_event_timer = maxf(_event_timer - step, 0.0)
		_record_presentation_snapshot()
		return
	if not Flow.is_live_phase(match_flow.phase):
		match_flow.advance(step)
		_sync_match_flow_state()
		_event_timer = maxf(_event_timer - step, 0.0)
		_record_presentation_snapshot()
		return
	match_flow.advance(step)
	_sync_match_flow_state()
	if not Flow.is_live_phase(match_flow.phase):
		_record_presentation_snapshot()
		return
	frame_count += 1
	action_cooldown = maxf(action_cooldown - step, 0.0)
	cpu_action_cooldown = maxf(cpu_action_cooldown - step, 0.0)
	cpu_tackle_cooldown = maxf(cpu_tackle_cooldown - step, 0.0)
	_event_timer = maxf(_event_timer - step, 0.0)
	_handle_player_switch()
	_update_controlled_player()
	_update_tactical_roles()
	_step_players(step)
	_handle_defensive_inputs(step)
	if action_cooldown <= 0.0 and _action_just_pressed("p1_special"):
		_attempt_tackle(_player_by_id(controlled_id))
	_step_ball(step)
	_resolve_player_separation()
	_simulation_tick += 1
	_record_presentation_snapshot()

func _action_just_pressed(action: String) -> bool:
	var value := bool(_sampled_just_pressed.get(action, false))
	_sampled_just_pressed[action] = false
	return value

func _action_just_released(action: String) -> bool:
	var value := bool(_sampled_just_released.get(action, false))
	_sampled_just_released[action] = false
	return value

func _handle_kickoff_input() -> void:
	if carrier_id < 0:
		return
	var carrier := _player_by_id(carrier_id)
	if carrier.is_empty() or not bool(carrier.home):
		return
	controlled_id = carrier_id
	var aim := _input_direction()
	if aim.is_zero_approx():
		aim = carrier.facing
	if _action_just_pressed("p1_pass"):
		_accept_kickoff()
		_kick_to_target(carrier, false, aim)
	elif _action_just_pressed("p1_through_pass"):
		_accept_kickoff()
		_kick_to_target(carrier, false, aim, true)
	elif _action_just_pressed("p1_long_pass"):
		_accept_kickoff()
		_kick_to_target(carrier, true, aim)
	elif _action_just_pressed("p1_shoot"):
		_accept_kickoff()
		_shoot(carrier, aim.z)

func _accept_kickoff() -> void:
	kickoff_timer = 0.0
	if match_flow != null:
		match_flow.phase_timer = 0.0

func _create_match() -> void:
	var formation := [
		Vector3(4.0, 0.0, 18.0), Vector3(15.0, 0.0, 7.0), Vector3(15.0, 0.0, 14.0), Vector3(15.0, 0.0, 22.0), Vector3(15.0, 0.0, 29.0),
		Vector3(29.0, 0.0, 9.0), Vector3(30.0, 0.0, 18.0), Vector3(29.0, 0.0, 27.0), Vector3(43.0, 0.0, 8.0), Vector3(46.0, 0.0, 18.0), Vector3(43.0, 0.0, 28.0),
	]
	for home in [true, false]:
		for index in formation.size():
			var spawn: Vector3 = formation[index]
			if not home:
				spawn.x = Rules.PITCH_SIZE.x - spawn.x
			var id := index if home else index + formation.size()
			# Technique is deliberately visible in the simulation state: WE2000's
			# difference between a nimble midfielder and a loose-touch runner should
			# be felt through contact timing and correction strength.
			var technique := 58.0 + float((index * 7) % 31)
			if index == 0:
				technique = 42.0
			var entry := {"id": id, "home": home, "position": spawn, "spawn": spawn,
				"velocity": Vector3.ZERO, "facing": Vector3.RIGHT if home else Vector3.LEFT,
				"input_direction": Vector3.RIGHT if home else Vector3.LEFT,
				"goalkeeper": index == 0, "technique": technique, "dribble_mode": DribblePhysics3D.Mode.JOG,
				"cutback_cooldown": 0.0, "formation_index": index,
				"formation_line": _formation_line(index), "ai_state": "formation",
				"tackle_recovery": 0.0, "stumble_recovery": 0.0,
				"defense": 58.0 + float((index * 11) % 38), "pressure_cooldown": 0.0,
				"pressure_exposure": 0.0}
			players.append(entry)
			var view := PlayerView.new() as Player3DView
			view.name = "Home_%02d" % index if home else "Away_%02d" % index
			view.set_team_color(KEEPERS_COLOR if index == 0 else (HOME_COLOR if home else AWAY_COLOR))
			add_child(view)
			_views[id] = view
	_ball_view = BallView.new() as Ball3DView
	_ball_view.name = "Ball"
	add_child(_ball_view)
	_reset_kickoff(true)

func _step_players(delta: float) -> void:
	dribble_turn_lock_timer = maxf(dribble_turn_lock_timer - delta, 0.0)
	var turn_45_ball_lead_active := dribble_45_turn_commit_timer > 0.0
	dribble_45_turn_commit_timer = maxf(dribble_45_turn_commit_timer - delta, 0.0)
	if dribble_45_turn_commit_timer < 0.0001:
		dribble_45_turn_commit_timer = 0.0
	for index in players.size():
		var player := players[index]
		var player_id := int(player.id)
		var tackle_recovery := maxf(float(player.get("tackle_recovery", 0.0)) - delta, 0.0)
		player.tackle_recovery = tackle_recovery
		var stumble_recovery := maxf(float(player.get("stumble_recovery", 0.0)) - delta, 0.0)
		player.stumble_recovery = stumble_recovery
		if stumble_recovery <= 0.0 and float(player.get("pressure_exposure", 0.0)) > 0.0:
			player.pressure_exposure = maxf(float(player.pressure_exposure) - delta * 0.55, 0.0)
		if tackle_recovery > 0.0 or stumble_recovery > 0.0:
			# The tackle asset is a sliding/falling action. Hold the gameplay body
			# and ball owner through its recovery instead of letting locomotion resume.
			player.velocity = Vector3.ZERO
			player.movement_intent = false
			players[index] = player
			continue
		var turnaround_locked := player_id == carrier_id and dribble_turn_lock_timer > 0.0
		if turnaround_locked:
			# The turnaround clip plants the supporting foot before launch. Freeze
			# translation and face the committed lane, rather than accepting a new
			# stick direction while the cut is still being performed.
			player.velocity = Vector3.ZERO
			player.movement_intent = false
			if not dribble_turn_locked_direction.is_zero_approx():
				var turn_progress := 1.0 - dribble_turn_lock_timer / \
					DribblePhysics3D.TURNAROUND_INPUT_LOCK_SECONDS
				player.facing = _turnaround_facing(turn_progress)
			players[index] = player
			continue
		var requested_direction := _player_intent(player)
		var has_input_intent := not requested_direction.is_zero_approx()
		player.movement_intent = has_input_intent
		var stopping_controlled_dribble := player_id == controlled_id and player_id == carrier_id and \
			not has_input_intent and dribble_phase == DribblePhase.FREE_ROLL
		if stopping_controlled_dribble:
			# A stationary receiver traps on the spot. A moving carrier gets WE2000's
			# short forward settling roll, which is resolved in _step_dribbling_ball.
			if dribble_stop_roll_timer <= 0.0:
				_begin_dribble_stop_roll(player)
			player.velocity = Vector3.ZERO
			player.dribble_mode = DribblePhysics3D.Mode.JOG
			players[index] = player
			continue
		if player_id == controlled_id and player_id == carrier_id and has_input_intent:
			_clear_dribble_stop_roll()
		var desired := requested_direction
		var waiting_for_45_turn := player_id == carrier_id and dribble_45_turn_commit_timer > 0.0 and \
			not dribble_45_turn_pending_direction.is_zero_approx()
		var start_45_turn := player_id == carrier_id and turn_45_ball_lead_active and \
			dribble_45_turn_commit_timer <= 0.0 and not dribble_45_turn_pending_direction.is_zero_approx()
		if start_45_turn:
			var turn_direction := Coordinate3D.ground(dribble_45_turn_pending_direction).normalized()
			player.velocity = turn_direction * Coordinate3D.ground(player.velocity).length()
			player.facing = turn_direction
			desired = turn_direction
			dribble_45_turn_pending_direction = Vector3.ZERO
		# A 45-degree touch is the handoff between the old and new running lanes.
		# Hold the body on its existing lane until that foot contact, then let the
		# ball roll briefly before the body follows the same touched lane.
		if waiting_for_45_turn or _hold_45_turn_until_touch(player, requested_direction):
			desired = _player_carry_direction(player)
		var speed := 7.5 if bool(player.goalkeeper) else 8.8
		var sprint_input := player_id == controlled_id and Input.is_action_pressed("p1_sprint")
		var sprinting := player_id == carrier_id and sprint_input
		if player_id == carrier_id and not sprinting:
			speed = JOG_DRIBBLE_TOP_SPEED
		if sprint_input:
			speed = 11.0
		var acceleration := 24.0
		if sprinting:
			acceleration = 17.0
		player.cutback_cooldown = maxf(float(player.get("cutback_cooldown", 0.0)) - delta, 0.0)
		var motion := Rules.advance_player(player.position, player.velocity, desired, delta, speed, acceleration)
		player.position = motion.position
		player.velocity = motion.velocity
		player.dribble_mode = DribblePhysics3D.Mode.SPRINT if sprinting else DribblePhysics3D.Mode.JOG
		if not requested_direction.is_zero_approx():
			player.input_direction = Coordinate3D.ground(requested_direction).normalized()
			# Facing follows the actual velocity, with input only as a fallback.
			var actual_direction := Coordinate3D.ground(player.velocity).normalized()
			player.facing = actual_direction if not actual_direction.is_zero_approx() else desired.normalized()
		players[index] = player

func _player_carry_direction(player: Dictionary) -> Vector3:
	var carry_direction := Coordinate3D.ground(player.velocity).normalized()
	if carry_direction.is_zero_approx():
		carry_direction = Coordinate3D.ground(player.facing).normalized()
	return carry_direction

func _begin_dribble_stop_roll(player: Dictionary) -> void:
	var velocity := Coordinate3D.ground(player.velocity)
	var distance := DribblePhysics3D.stop_roll_distance(velocity.length(), int(player.get("dribble_mode", DribblePhysics3D.Mode.JOG)))
	if distance <= 0.0:
		_clear_dribble_stop_roll()
		return
	var direction := velocity.normalized()
	if direction.is_zero_approx():
		_clear_dribble_stop_roll()
		return
	dribble_stop_roll_timer = DribblePhysics3D.STOP_ROLL_DURATION
	dribble_stop_roll_start = DribblePhysics3D.to_pitch_plane(ball_position)
	dribble_stop_roll_direction = DribblePhysics3D.to_pitch_plane(direction)
	dribble_stop_roll_distance = distance
	dribble_stop_roll_carrier_start = player.position
	var carrier_stop_distance := distance * DribblePhysics3D.STOP_ROLL_CARRIER_FOLLOW
	var carrier_stop_plane := DribblePhysics3D.to_pitch_plane(player.position) + dribble_stop_roll_direction * carrier_stop_distance
	dribble_stop_roll_ball_target = carrier_stop_plane + dribble_stop_roll_direction * \
		DribblePhysics3D.stop_trap_foot_distance(int(player.get("dribble_mode", DribblePhysics3D.Mode.JOG)))

func _clear_dribble_stop_roll() -> void:
	dribble_stop_roll_timer = 0.0
	dribble_stop_roll_start = Vector2.ZERO
	dribble_stop_roll_direction = Vector2.ZERO
	dribble_stop_roll_distance = 0.0
	dribble_stop_roll_carrier_start = Vector3.ZERO
	dribble_stop_roll_ball_target = Vector2.ZERO

func _advance_dribble_stop_roll_carrier(player_id: int, ball_distance: float) -> void:
	var player_distance := ball_distance * DribblePhysics3D.STOP_ROLL_CARRIER_FOLLOW
	var offset := DribblePhysics3D.from_pitch_plane(dribble_stop_roll_direction * player_distance)
	for index in players.size():
		var player := players[index]
		if int(player.id) != player_id:
			continue
		player.position = Coordinate3D.clamp_pitch(dribble_stop_roll_carrier_start + offset, Rules.PLAYER_RADIUS)
		player.position.y = 0.0
		player.velocity = Vector3.ZERO
		player.movement_intent = false
		players[index] = player
		return

func _hold_45_turn_until_touch(player: Dictionary, requested_direction: Vector3) -> bool:
	if int(player.id) != carrier_id or dribble_phase != DribblePhase.FREE_ROLL or \
		dribble_45_turn_commit_timer > 0.0 or dribble_touch_timer <= 0.0:
		return false
	if Coordinate3D.ground(player.velocity).length() <= 0.12:
		return false
	return DribblePhysics3D.classify_turn(_player_carry_direction(player), requested_direction) == DribblePhysics3D.TurnType.DEGREE_45

func _formation_line(index: int) -> int:
	if index == 0:
		return 0
	if index <= 4:
		return 1
	if index <= 7:
		return 2
	return 3

func _update_tactical_roles() -> void:
	tactical_assignments.clear()
	var carrier := _player_by_id(carrier_id)
	if carrier.is_empty():
		_assign_loose_ball_tactics(true)
		_assign_loose_ball_tactics(false)
		return
	var possession_home := bool(carrier.home)
	_assign_team_tactics(possession_home, carrier, true)
	_assign_team_tactics(not possession_home, carrier, false)

func _assign_loose_ball_tactics(team_home: bool) -> void:
	var closest_id := Rules.nearest_player_id(players, ball_position, 1 if team_home else -1)
	for player: Dictionary in players:
		if bool(player.home) != team_home:
			continue
		var target := _formation_target(player, Coordinate3D.ground(ball_position), false)
		var state := "defensive_shape"
		if int(player.id) == closest_id and not bool(player.goalkeeper):
			target = Coordinate3D.ground(ball_position)
			state = "contest_ball"
		_set_tactical_assignment(player, state, target)

func _assign_team_tactics(team_home: bool, carrier: Dictionary, in_possession: bool) -> void:
	var focus: Vector3 = Coordinate3D.ground(carrier.position)
	if in_possession:
		for player: Dictionary in players:
			if bool(player.home) != team_home:
				continue
			if int(player.id) == int(carrier.id):
				_set_tactical_assignment(player, "ball_control", _cpu_attack_goal_target(player))
				continue
			var target := _formation_target(player, focus, true)
			var state := "offensive_support"
			if _can_make_forward_run(player, carrier):
				target = _forward_run_target(player, target)
				state = "forward_run"
			_set_tactical_assignment(player, state, target)
		return

	var primary := _select_primary_presser(team_home, carrier)
	var secondary := _select_secondary_defender(team_home, carrier, primary)
	var threat := _most_dangerous_receiver(not team_home, carrier)
	for player: Dictionary in players:
		if bool(player.home) != team_home:
			continue
		var target := _formation_target(player, focus, false)
		var state := "defensive_shape"
		if int(player.id) == int(primary.get("id", -1)):
			target = _presser_target(player, carrier)
			state = "primary_press"
		elif int(player.id) == int(secondary.get("id", -1)) and not threat.is_empty():
			target = focus.lerp(Coordinate3D.ground(threat.position), 0.58)
			state = "lane_cover"
		_set_tactical_assignment(player, state, target)

func _set_tactical_assignment(player: Dictionary, state: String, target: Vector3) -> void:
	var player_id := int(player.id)
	tactical_assignments[player_id] = {"state": state,
		"target": Coordinate3D.clamp_pitch(Coordinate3D.ground(target), Rules.PLAYER_RADIUS)}
	for index in players.size():
		if int(players[index].id) == player_id:
			var updated_player := players[index]
			updated_player.ai_state = state
			players[index] = updated_player
			return

func _formation_target(player: Dictionary, focus: Vector3, attacking: bool) -> Vector3:
	var base: Vector3 = player.spawn
	var attack_sign := 1.0 if bool(player.home) else -1.0
	var ball_progress := (focus.x - Rules.PITCH_SIZE.x * 0.5) * attack_sign
	var forward_shift := clampf(ball_progress * FORMATION_BALL_X_WEIGHT, -11.0, 11.0)
	if attacking:
		forward_shift += 2.0
	var line := int(player.get("formation_line", 1))
	var lateral_weight := FORMATION_BALL_Z_WEIGHT
	if line == 1:
		lateral_weight = 0.24
	elif line == 3:
		lateral_weight = 0.42
	var target := base + Vector3(attack_sign * forward_shift, 0.0,
		(focus.z - Rules.PITCH_SIZE.z * 0.5) * lateral_weight)
	# The far side contracts toward the ball but never collapses into its lane.
	var compactness := 0.11 if line <= 1 else 0.06
	target.z = lerpf(target.z, Rules.PITCH_SIZE.z * 0.5, compactness)
	return Coordinate3D.clamp_pitch(target, Rules.PLAYER_RADIUS)

func _can_make_forward_run(player: Dictionary, carrier: Dictionary) -> bool:
	if bool(player.goalkeeper) or int(player.get("formation_line", 0)) < 2:
		return false
	var attack_sign := 1.0 if bool(player.home) else -1.0
	if (carrier.position.x - Rules.PITCH_SIZE.x * 0.5) * attack_sign < -5.0:
		return false
	var forward := Vector3(attack_sign, 0.0, 0.0)
	for opponent: Dictionary in players:
		if bool(opponent.home) == bool(player.home):
			continue
		var offset := Coordinate3D.ground(opponent.position - player.position)
		if offset.length() < 7.0 and not offset.is_zero_approx() and forward.dot(offset.normalized()) > 0.72:
			return false
	return true

func _forward_run_target(player: Dictionary, formation_target: Vector3) -> Vector3:
	var attack_sign := 1.0 if bool(player.home) else -1.0
	var line := int(player.get("formation_line", 2))
	var run_distance := 6.0 if line >= 3 else 3.6
	return Coordinate3D.clamp_pitch(formation_target + Vector3(attack_sign * run_distance, 0.0, 0.0),
		Rules.PLAYER_RADIUS)

func _select_primary_presser(team_home: bool, carrier: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	var candidate_scores: Dictionary = {}
	for player: Dictionary in players:
		if bool(player.home) != team_home or bool(player.goalkeeper) or int(player.id) == controlled_id or \
			_is_tackle_recovering(player):
			continue
		var to_ball := Coordinate3D.ground(carrier.position - player.position)
		var distance := to_ball.length()
		if distance <= 0.01:
			continue
		var approach_alignment := Coordinate3D.ground(player.facing).normalized().dot(to_ball.normalized())
		var role_penalty := 0.42 if int(player.get("formation_line", 1)) == 1 else 0.0
		var score := distance / 8.8 + (1.0 - approach_alignment) * 0.24 + role_penalty
		candidate_scores[int(player.id)] = score
		if score < best_score:
			best_score = score
			best = player
	var key := "home" if team_home else "away"
	var current_id := int(primary_presser_by_team.get(key, -1))
	if candidate_scores.has(current_id) and float(candidate_scores[current_id]) <= best_score * PRESSER_SWITCH_MARGIN:
		best = _player_by_id(current_id)
	primary_presser_by_team[key] = int(best.get("id", -1))
	return best

func _select_secondary_defender(team_home: bool, carrier: Dictionary, primary: Dictionary) -> Dictionary:
	if primary.is_empty():
		return {}
	var best: Dictionary = {}
	var best_score := INF
	var primary_offset := Coordinate3D.ground(primary.position - carrier.position).normalized()
	for player: Dictionary in players:
		if bool(player.home) != team_home or bool(player.goalkeeper) or int(player.id) == int(primary.id) or \
			int(player.id) == controlled_id or _is_last_defender(player, team_home):
			continue
		var offset := Coordinate3D.ground(player.position - carrier.position)
		var distance := offset.length()
		if distance < 0.01 or distance > 17.0:
			continue
		var angle_penalty := absf(primary_offset.dot(offset.normalized())) * 1.1
		var score := distance / 8.8 + angle_penalty
		if score < best_score:
			best_score = score
			best = player
	return best

func _is_last_defender(player: Dictionary, team_home: bool) -> bool:
	var player_depth := float(player.position.x) if team_home else Rules.PITCH_SIZE.x - float(player.position.x)
	for teammate: Dictionary in players:
		if bool(teammate.home) != team_home or bool(teammate.goalkeeper) or int(teammate.id) == int(player.id):
			continue
		var depth := float(teammate.position.x) if team_home else Rules.PITCH_SIZE.x - float(teammate.position.x)
		if depth < player_depth - 0.35:
			return false
	return true

func _most_dangerous_receiver(attacking_home: bool, carrier: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -INF
	var attack_sign := 1.0 if attacking_home else -1.0
	for player: Dictionary in players:
		if bool(player.home) != attacking_home or int(player.id) == int(carrier.id) or bool(player.goalkeeper):
			continue
		var player_position: Vector3 = player.position
		var goal_progress: float = (player_position.x - Rules.PITCH_SIZE.x * 0.5) * attack_sign
		var distance: float = Coordinate3D.ground(player_position - carrier.position).length()
		var score: float = goal_progress * 0.18 - distance * 0.025
		if score > best_score:
			best_score = score
			best = player
	return best

func _presser_target(presser: Dictionary, carrier: Dictionary) -> Vector3:
	var predicted_ball := Coordinate3D.ground(carrier.position + carrier.velocity * 0.18)
	var own_goal := Vector3(0.0 if bool(presser.home) else Rules.PITCH_SIZE.x, 0.0,
		Rules.PITCH_SIZE.z * 0.5)
	var distance := Coordinate3D.ground(presser.position - predicted_ball).length()
	if distance <= AI_TACKLE_DISTANCE:
		# At tackling range, own the ball rather than orbiting to a jockey point.
		return Coordinate3D.clamp_pitch(predicted_ball, Rules.PLAYER_RADIUS)
	var goal_side := (own_goal - predicted_ball).normalized()
	if distance <= PRESSER_APPROACH_DISTANCE:
		# The jockey point sits inside tackling distance, so a close defender keeps
		# closing down instead of stopping just outside the ball-winning threshold.
		return Coordinate3D.clamp_pitch(predicted_ball + goal_side * PRESSER_JOCKEY_DISTANCE,
			Rules.PLAYER_RADIUS)
	# From range, lead a moving carrier but retain a modest goal-side angle.
	return Coordinate3D.clamp_pitch(predicted_ball + goal_side * 0.72, Rules.PLAYER_RADIUS)

func _cpu_attack_goal_target(player: Dictionary) -> Vector3:
	return Vector3(Rules.PITCH_SIZE.x if bool(player.home) else 0.0, 0.0, Rules.PITCH_SIZE.z * 0.5)

func _cpu_carrier_intent(player: Dictionary) -> Vector3:
	var goal_target := _cpu_attack_goal_target(player)
	var desired := Coordinate3D.ground(goal_target - player.position).normalized()
	var nearest: Dictionary = {}
	var nearest_distance := INF
	for opponent: Dictionary in players:
		if bool(opponent.home) == bool(player.home):
			continue
		var offset := Coordinate3D.ground(opponent.position - player.position)
		if offset.length() < nearest_distance and not offset.is_zero_approx() and desired.dot(offset.normalized()) > 0.15:
			nearest_distance = offset.length()
			nearest = opponent
	if not nearest.is_empty() and nearest_distance < 5.0:
		var evade := Coordinate3D.ground(player.position - nearest.position).normalized()
		desired = (desired + evade * (1.0 - nearest_distance / 5.0) * 0.9).normalized()
	return desired

func _player_intent(player: Dictionary) -> Vector3:
	var id := int(player.id)
	if id == controlled_id:
		var input := _input_direction()
		if not input.is_zero_approx():
			return input
		var carrier := _player_by_id(carrier_id)
		if Input.is_action_pressed("p1_pressure") and not carrier.is_empty() and \
			bool(carrier.home) != bool(player.home):
			return Coordinate3D.ground(carrier.position - player.position).normalized()
		# A controlled player is fully manual. Do not fall through to the
		# carrier/formation AI when the stick is released.
		return Vector3.ZERO
	if id == carrier_id:
		return _cpu_carrier_intent(player)
	var assignment: Dictionary = tactical_assignments.get(id, {})
	if Input.is_action_pressed("p1_co_defense") and assignment.get("state", "") == "lane_cover":
		var carrier := _player_by_id(carrier_id)
		if not carrier.is_empty() and bool(carrier.home) != bool(player.home):
			return Coordinate3D.ground(carrier.position - player.position).normalized()
	var target: Vector3 = assignment.get("target", player.spawn)
	return Coordinate3D.ground(target - player.position).normalized()

func _handle_defensive_inputs(delta: float) -> void:
	for index in players.size():
		var player := players[index]
		player.pressure_cooldown = maxf(float(player.get("pressure_cooldown", 0.0)) - delta, 0.0)
		players[index] = player
	var carrier := _player_by_id(carrier_id)
	if carrier.is_empty():
		return
	var controlled := _player_by_id(controlled_id)
	if controlled.is_empty() or bool(controlled.home) == bool(carrier.home):
		return
	var pressure_held := Input.is_action_pressed("p1_pressure")
	if pressure_held:
		_try_pressure(controlled, carrier)
	if Input.is_action_pressed("p1_co_defense"):
		var secondary_id := _secondary_pressure_id(bool(controlled.home), carrier)
		if secondary_id >= 0:
			_try_pressure(_player_by_id(secondary_id), carrier)

func _secondary_pressure_id(team_home: bool, carrier: Dictionary) -> int:
	var assignment := _select_secondary_defender(team_home, carrier, _select_primary_presser(team_home, carrier))
	return int(assignment.get("id", -1))

func _try_pressure(defender: Dictionary, carrier: Dictionary) -> bool:
	if defender.is_empty() or _is_tackle_recovering(defender) or _is_stumbling(defender):
		return false
	if float(defender.get("pressure_cooldown", 0.0)) > 0.0:
		return false
	var distance := Coordinate3D.ground(defender.position - carrier.position).length()
	if distance > 1.65:
		return false
	var to_carrier := Coordinate3D.ground(carrier.position - defender.position).normalized()
	var facing := Coordinate3D.ground(defender.facing).normalized()
	var carrier_facing := Coordinate3D.ground(carrier.facing).normalized()
	var front_factor := facing.dot(to_carrier)
	var carrier_back_turn := carrier_facing.dot(to_carrier) > 0.35
	var defender_behind := carrier_back_turn
	var defender_value := float(defender.get("defense", 60.0))
	# A carrier facing away from the defender protects the ball. Only a strong
	# defender or a very poor touch should let pressure win from behind.
	var success_threshold := 0.92 if carrier_back_turn else 0.68
	if front_factor < -0.35:
		# Chasing from behind is mostly pressure, not an instant steal. High
		# defensive value can still win a mistimed touch.
		success_threshold += 0.18 - defender_value * 0.0024
	var pressure_score := defender_value * 0.01 + front_factor * 0.24
	if pressure_score < success_threshold:
		_set_pressure_cooldown(int(defender.id), PRESSURE_COOLDOWN_SECONDS)
		if defender_behind:
			var exposure := float(defender.get("pressure_exposure", 0.0)) + FIXED_TICK
			_set_pressure_exposure(int(defender.id), exposure)
			if exposure >= 0.78:
				_add_stumble(int(defender.id), STUMBLE_RECOVERY_SECONDS)
				_set_pressure_exposure(int(defender.id), 0.0)
		return false
	_win_pressure(defender, carrier)
	return true

func _win_pressure(defender: Dictionary, carrier: Dictionary) -> void:
	_win_tackle(defender, false)

func _set_pressure_cooldown(player_id: int, duration: float) -> void:
	for index in players.size():
		var player := players[index]
		if int(player.id) == player_id:
			player.pressure_cooldown = maxf(float(player.get("pressure_cooldown", 0.0)), duration)
			players[index] = player
			return

func _set_pressure_exposure(player_id: int, exposure: float) -> void:
	for index in players.size():
		var player := players[index]
		if int(player.id) == player_id:
			player.pressure_exposure = maxf(exposure, 0.0)
			players[index] = player
			return

func _add_stumble(player_id: int, duration: float) -> void:
	for index in players.size():
		var player := players[index]
		if int(player.id) == player_id:
			player.stumble_recovery = maxf(float(player.get("stumble_recovery", 0.0)), duration)
			player.velocity = Vector3.ZERO
			player.movement_intent = false
			players[index] = player
			return

func _is_stumbling(player: Dictionary) -> bool:
	return float(player.get("stumble_recovery", 0.0)) > 0.0

func _handle_player_switch() -> void:
	if not _action_just_pressed("p1_switch"):
		return
	var carrier := _player_by_id(carrier_id)
	# U is a defensive switch. When our side has possession it remains inert so
	# the same physical key cannot interrupt attacking play.
	if not carrier.is_empty() and bool(carrier.home):
		return
	var next_id := _nearest_home_switch_target()
	if next_id < 0:
		return
	controlled_id = next_id
	_event_label.text = "SWITCH"
	_event_timer = 0.3

func _nearest_home_switch_target() -> int:
	var nearest_id := -1
	var nearest_distance := INF
	for player: Dictionary in players:
		if not bool(player.home) or int(player.id) == controlled_id:
			continue
		var distance := Coordinate3D.ground(player.position - ball_position).length_squared()
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = int(player.id)
	return nearest_id

func _step_ball(delta: float) -> void:
	if carrier_id >= 0:
		var carrier := _player_by_id(carrier_id)
		if carrier.is_empty():
			carrier_id = -1
			dribble_touch_timer = 0.0
			dribble_loss_timer = 0.0
			_reset_dribble_turn_state()
			_clear_shot_charge()
			return
		if _is_tackle_recovering(carrier) or _is_stumbling(carrier):
			_hold_tackle_recovery_ball(carrier)
			return
		_handle_carrier_actions(carrier, delta)
		if carrier_id >= 0:
			_step_dribbling_ball(carrier, delta)
		return
	var trajectory := BallTrajectory3DScript.step_on_pitch(ball_position, ball_velocity,
		delta, BallPhysics3D.GRAVITY, BallPhysics3D.GROUND_FRICTION,
		BallPhysics3D.AIR_FRICTION, BallPhysics3D.BOUNCINESS, Rules.PITCH_SIZE,
		Rules.GOAL_HALF_WIDTH, Rules.GOAL_HEIGHT, BallPhysics3D.BOUNDARY_RESTITUTION)
	ball_position = trajectory.position
	ball_velocity = trajectory.velocity
	ball_flight_time += delta
	ball_grounded = bool(trajectory.get("grounded", false))
	if bool(trajectory.get("bounced", false)):
		ball_bounce_count += 1
	var scorer := Rules.goal_scoring_team(ball_position)
	if scorer != 0:
		_score_goal(scorer > 0)
		return
	if bool(trajectory.get("boundary_hit", false)):
		_begin_boundary_restart(str(trajectory.get("boundary_axis", "")))
		return
	_capture_free_ball()

func _step_dribbling_ball(carrier: Dictionary, delta: float) -> void:
	var mode := int(carrier.get("dribble_mode", DribblePhysics3D.Mode.JOG))
	dribble_mode = mode
	var technique := float(carrier.get("technique", 64.0))
	var carrier_position: Vector3 = carrier.position
	var ball_plane := DribblePhysics3D.to_pitch_plane(ball_position)
	var carrier_plane := DribblePhysics3D.to_pitch_plane(carrier_position)
	var carrier_velocity_plane := DribblePhysics3D.to_pitch_plane(carrier.velocity)
	var ball_velocity_plane := DribblePhysics3D.to_pitch_plane(ball_velocity)
	var control_distance := DribblePhysics3D.control_distance(technique, mode)

	var distance := ball_plane.distance_to(carrier_plane)
	var carrier_speed := carrier_velocity_plane.length()
	var has_movement_intent := bool(carrier.get("movement_intent", carrier_speed > 0.12))
	var opponent_interference := _opponent_interfering(carrier, DribblePhysics3D.from_pitch_plane(ball_plane))
	var touched_this_tick := false
	var requested_direction: Vector3 = carrier.get("input_direction", carrier.facing)
	var quantized_request := DribblePhysics3D.quantize_direction(requested_direction)
	if quantized_request.is_zero_approx():
		quantized_request = DribblePhysics3D.quantize_direction(carrier.facing)
	if quantized_request.is_zero_approx():
		quantized_request = Vector3.RIGHT
	# Input may change between contacts, but the queued lane is consumed only by
	# the next foot-contact event. This is the gameplay-side equivalent of an
	# animation event and keeps large cuts from steering the ball every frame.
	dribble_queued_direction = quantized_request
	if has_movement_intent:
		_clear_dribble_stop_roll()
	var contact_direction := dribble_queued_direction
	var intent_plane := DribblePhysics3D.to_pitch_plane(contact_direction)
	var carry_direction_plane := carrier_velocity_plane.normalized()
	if carry_direction_plane.is_zero_approx():
		carry_direction_plane = DribblePhysics3D.to_pitch_plane(carrier.facing).normalized()
	if carry_direction_plane.is_zero_approx():
		carry_direction_plane = intent_plane

	# 90 and 180 degree cuts use a short foot-contact anchor before their new
	# touch velocity is released. A 45 degree cut stays in the running loop and
	# releases its diagonal touch immediately; only 180 degrees locks movement.
	var turn_anchor_active := dribble_phase != DribblePhase.FREE_ROLL
	var external_force := false
	if turn_anchor_active:
		dribble_turn_anchor_timer = maxf(dribble_turn_anchor_timer - delta, 0.0)
		var anchor_target := carrier_plane + DribblePhysics3D.to_pitch_plane(dribble_turn_anchor_direction) * dribble_turn_anchor_offset
		var anchor_progress := 1.0 - dribble_turn_anchor_timer / maxf(dribble_turn_anchor_duration, 0.001)
		ball_plane = dribble_turn_anchor_start.lerp(anchor_target, smoothstep(0.0, 1.0, anchor_progress))
		ball_velocity_plane = Vector2.ZERO
		if dribble_turn_anchor_timer <= 0.0:
			ball_velocity_plane = DribblePhysics3D.to_pitch_plane(dribble_turn_release_velocity)
			dribble_turn_release_velocity = Vector3.ZERO
			dribble_phase = DribblePhase.FREE_ROLL
	else:
		# The ball is free between contacts. A contact is the sole point where a
		# new lane, a velocity reset, or a turn penalty is allowed to take effect.
		ball_velocity_plane = DribblePhysics3D.apply_ground_friction_2d(ball_velocity_plane, delta)
		external_force = (ball_velocity_plane - carrier_velocity_plane).length() > 14.0
		# Releasing direction traps a stationary receiver at once. A moving carrier
		# rolls the ball just ahead before the trap settles, instead of coasting.
		var released_controlled_carrier := int(carrier.id) == controlled_id and not has_movement_intent
		var applying_stop_roll := false
		if released_controlled_carrier:
			if dribble_stop_roll_timer > 0.0:
				applying_stop_roll = true
				var prior_progress := 1.0 - dribble_stop_roll_timer / DribblePhysics3D.STOP_ROLL_DURATION
				dribble_stop_roll_timer = maxf(dribble_stop_roll_timer - delta, 0.0)
				var next_progress := 1.0 - dribble_stop_roll_timer / DribblePhysics3D.STOP_ROLL_DURATION
				var prior_eased_progress := smoothstep(0.0, 1.0, prior_progress)
				var next_eased_progress := smoothstep(0.0, 1.0, next_progress)
				var prior_ball_plane := dribble_stop_roll_start.lerp(dribble_stop_roll_ball_target, prior_eased_progress)
				ball_plane = dribble_stop_roll_start.lerp(dribble_stop_roll_ball_target, next_eased_progress)
				ball_velocity_plane = (ball_plane - prior_ball_plane) / maxf(delta, 0.001)
				var ball_roll_distance := next_eased_progress * dribble_stop_roll_distance
				_advance_dribble_stop_roll_carrier(int(carrier.id), ball_roll_distance)
				if dribble_stop_roll_timer <= 0.0:
					ball_velocity_plane = Vector2.ZERO
			else:
				ball_velocity_plane = Vector2.ZERO
			carrier_velocity_plane = Vector2.ZERO
			carrier_speed = 0.0
			dribble_touch_timer = 0.0
			dribble_last_turn_type = DribblePhysics3D.TurnType.NONE
			dribble_45_turn_commit_timer = 0.0
			dribble_45_turn_pending_direction = Vector3.ZERO
			_stop_player_motion(int(carrier.id))
		dribble_touch_timer = maxf(dribble_touch_timer - delta, 0.0)
		var contact_zone := DribblePhysics3D.touch_offset(technique, mode) + 0.82
		var in_contact_range := distance <= control_distance and distance <= contact_zone + 0.72
		# A parked carrier owns a fully static ball. The old idle push was applied
		# every touch interval, so it continuously defeated ground friction and
		# made the ball creep away before the player had moved.
		var can_make_touch := has_movement_intent and carrier_speed > 0.12
		if dribble_touch_timer <= 0.0 and in_contact_range and can_make_touch:
			contact_direction = _safe_dribble_contact_direction(carrier, contact_direction)
			intent_plane = DribblePhysics3D.to_pitch_plane(contact_direction)
			dribble_last_turn_type = DribblePhysics3D.classify_turn(
				DribblePhysics3D.from_pitch_plane(carry_direction_plane), contact_direction)
			_apply_dribble_turn_penalty(int(carrier.id), dribble_last_turn_type)
			touched_this_tick = true
			dribble_touch_timer = DribblePhysics3D.touch_interval(technique, mode)
			dribble_touch_count += 1
			dribble_loss_timer = 0.0
			var turn_anchor_duration := DribblePhysics3D.turn_anchor_duration(dribble_last_turn_type)
			if dribble_last_turn_type == DribblePhysics3D.TurnType.DEGREE_45:
				dribble_45_turn_commit_timer = DribblePhysics3D.TURN_45_BALL_LEAD_SECONDS
				dribble_45_turn_pending_direction = contact_direction
			if turn_anchor_duration > 0.0:
				dribble_turn_anchor_timer = turn_anchor_duration
				dribble_turn_anchor_duration = turn_anchor_duration
				dribble_turn_anchor_direction = contact_direction
				dribble_turn_anchor_offset = DribblePhysics3D.touch_offset(technique, mode)
				if dribble_last_turn_type == DribblePhysics3D.TurnType.DEGREE_180:
					dribble_turn_anchor_direction = DribblePhysics3D.from_pitch_plane(-carry_direction_plane)
					dribble_turn_anchor_offset = 0.24
					dribble_turn_lock_timer = DribblePhysics3D.TURNAROUND_INPUT_LOCK_SECONDS
					dribble_turn_locked_direction = contact_direction
					dribble_turn_start_direction = DribblePhysics3D.from_pitch_plane(carry_direction_plane)
					var carrier_view := _views.get(int(carrier.id)) as Player3DView
					if carrier_view != null:
						carrier_view.play_action("turnaround")
				dribble_phase = DribblePhase.TURNAROUND_ANCHOR if dribble_last_turn_type == DribblePhysics3D.TurnType.DEGREE_180 else DribblePhase.TURN_ANCHOR
				dribble_turn_anchor_start = ball_plane
				dribble_turn_release_velocity = DribblePhysics3D.turn_touch_velocity(
					DribblePhysics3D.from_pitch_plane(ball_velocity_plane), carrier.velocity,
					carrier.facing, technique, mode, contact_direction, dribble_last_turn_type)
				ball_velocity_plane = Vector2.ZERO
				turn_anchor_active = true
			else:
				ball_velocity_plane = DribblePhysics3D.to_pitch_plane(DribblePhysics3D.turn_touch_velocity(
					DribblePhysics3D.from_pitch_plane(ball_velocity_plane), carrier.velocity,
					carrier.facing, technique, mode, contact_direction, dribble_last_turn_type))

		if not turn_anchor_active:
			# Keep a small, readable lead during ordinary running. Touches remain
			# independent impulses, but a slow ball must not collapse into the
			# player's centre between two contacts (the 2D implementation uses the
			# same moving-ideal-position constraint).
			# A diagonal touch owns the ball's entire free-roll window. Re-aiming it
			# toward a moving ideal point during that window looks like the carrier is
			# dragging the ball sideways at the end of an ordinary running stride.
			var direct_45_roll := dribble_last_turn_type == DribblePhysics3D.TurnType.DEGREE_45 and \
				dribble_touch_timer > 0.0
			if not direct_45_roll and has_movement_intent and carrier_speed > 0.25:
				var desired_lead := DribblePhysics3D.touch_offset(technique, mode) + \
					(0.08 if mode == DribblePhysics3D.Mode.JOG else 0.18)
				var current_lead := (ball_plane - carrier_plane).dot(intent_plane)
				if current_lead < desired_lead:
					var running_target := carrier_plane + intent_plane * desired_lead
					var running_error := running_target - ball_plane
					if not running_error.is_zero_approx():
						var running_speed := maxf(carrier_speed * 1.35, 4.0)
						ball_velocity_plane = ball_velocity_plane.move_toward(
							running_error.normalized() * running_speed, 50.0 * delta)

			# Integrate only after touch and forward lead forces. A stop roll already
			# authored its exact position above, so it must not be integrated twice.
			if not applying_stop_roll:
				ball_plane += ball_velocity_plane * delta
			if mode == DribblePhysics3D.Mode.JOG and has_movement_intent and \
				int(carrier.id) == controlled_id and not opponent_interference and not external_force:
				var jog_relative := ball_plane - carrier_plane
				if jog_relative.length() > DribblePhysics3D.JOG_MAX_BALL_DISTANCE:
					ball_plane = carrier_plane + jog_relative.normalized() * DribblePhysics3D.JOG_MAX_BALL_DISTANCE
	ball_plane.x = clampf(ball_plane.x, 0.12, Rules.PITCH_SIZE.x - 0.12)
	ball_plane.y = clampf(ball_plane.y, 0.12, Rules.PITCH_SIZE.z - 0.12)
	ball_position = DribblePhysics3D.from_pitch_plane(ball_plane)
	ball_velocity = DribblePhysics3D.from_pitch_plane(ball_velocity_plane)
	ball_grounded = true
	ball_flight_time = 0.0
	var post_distance := ball_plane.distance_to(carrier_plane)
	var away_from_carrier := ball_velocity_plane.dot(ball_plane - carrier_plane) > 0.0
	var carrier_pulling_away := carrier_velocity_plane.dot(carrier_plane - ball_plane) > 0.0
	# A ball is never pulled back to the carrier and a player cannot lose
	# possession merely by releasing input. Only interference or external force
	# can turn an overlong touch into a loose ball.
	if not turn_anchor_active and post_distance > control_distance + 0.65 and (opponent_interference or external_force) and (away_from_carrier or carrier_pulling_away):
		dribble_loss_timer += delta
	else:
		dribble_loss_timer = maxf(dribble_loss_timer - delta * 2.0, 0.0)
	if dribble_loss_timer >= 0.16:
		carrier_id = -1
		last_touch_home = bool(carrier.home)
		dribble_touch_timer = 0.0
		_event_label.text = "LOOSE TOUCH"
		_event_timer = 0.28
		_clear_shot_charge()
		_reset_dribble_turn_state()

func _reset_dribble_turn_state() -> void:
	dribble_queued_direction = Vector3.ZERO
	dribble_turn_anchor_timer = 0.0
	dribble_turn_anchor_duration = 0.0
	dribble_turn_anchor_direction = Vector3.ZERO
	dribble_turn_anchor_start = Vector2.ZERO
	dribble_turn_anchor_offset = 0.0
	dribble_turn_release_velocity = Vector3.ZERO
	dribble_last_turn_type = DribblePhysics3D.TurnType.NONE
	dribble_phase = DribblePhase.FREE_ROLL
	dribble_45_turn_commit_timer = 0.0
	dribble_45_turn_pending_direction = Vector3.ZERO
	dribble_turn_lock_timer = 0.0
	dribble_turn_locked_direction = Vector3.ZERO
	dribble_turn_start_direction = Vector3.ZERO
	_clear_dribble_stop_roll()

func _turnaround_facing(progress: float) -> Vector3:
	var start := Coordinate3D.ground(dribble_turn_start_direction).normalized()
	var target := Coordinate3D.ground(dribble_turn_locked_direction).normalized()
	if start.is_zero_approx():
		return target
	if target.is_zero_approx():
		return start
	var signed_angle := atan2(start.cross(target).y, start.dot(target))
	# Exact opposites have no cross-product sign. Always turn through the same
	# side so this input remains visibly deterministic instead of snapping.
	if absf(signed_angle) < 0.001 and start.dot(target) < 0.0:
		signed_angle = PI
	return start.rotated(Vector3.UP, signed_angle * clampf(progress, 0.0, 1.0)).normalized()

func _safe_dribble_contact_direction(carrier: Dictionary, requested_direction: Vector3) -> Vector3:
	var requested := DribblePhysics3D.quantize_direction(requested_direction)
	var carrier_position: Vector3 = carrier.position
	var nearest: Dictionary = {}
	var nearest_distance := INF
	for opponent: Dictionary in players:
		if bool(opponent.home) == bool(carrier.home):
			continue
		var offset := Coordinate3D.ground(opponent.position - carrier_position)
		var distance := offset.length()
		if distance < 0.45 or distance > 4.2 or requested.dot(offset.normalized()) < 0.2:
			continue
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = opponent
	if nearest.is_empty():
		return requested
	return DribblePhysics3D.steer_away_from_defender(requested, carrier_position,
		nearest.position, nearest.velocity)

func _apply_dribble_turn_penalty(player_id: int, turn_type: int) -> void:
	var multiplier := DribblePhysics3D.turn_speed_multiplier(turn_type)
	if multiplier >= 1.0:
		return
	for index in players.size():
		var player := players[index]
		if int(player.id) != player_id:
			continue
		player.velocity = Coordinate3D.ground(player.velocity) * multiplier
		player.cutback_cooldown = 0.24
		players[index] = player
		return

func _stop_player_motion(player_id: int) -> void:
	for index in players.size():
		var player := players[index]
		if int(player.id) != player_id:
			continue
		player.velocity = Vector3.ZERO
		player.movement_intent = false
		players[index] = player
		return

func _opponent_interfering(carrier: Dictionary, ball: Vector3) -> bool:
	var carrier_home := bool(carrier.home)
	for player: Dictionary in players:
		if bool(player.home) == carrier_home:
			continue
		var distance := Coordinate3D.ground((player.position as Vector3) - ball).length()
		if distance <= 1.65:
			return true
	return false

func _resolve_ai_tackle(carrier: Dictionary) -> bool:
	if cpu_tackle_cooldown > 0.0:
		return false
	var best: Dictionary = {}
	var best_distance := INF
	for player: Dictionary in players:
		if bool(player.home) == bool(carrier.home) or bool(player.goalkeeper) or int(player.id) == controlled_id or \
			_is_tackle_recovering(player):
			continue
		var distance := (player.position as Vector3).distance_to(Coordinate3D.ground(ball_position))
		if distance < best_distance:
			best_distance = distance
			best = player
	if best.is_empty() or best_distance > AI_TACKLE_DISTANCE:
		return false
	var approach: Vector3 = Coordinate3D.ground(carrier.position - best.position).normalized()
	var facing: Vector3 = best.facing
	if facing.dot(approach) < AI_TACKLE_FACING_MIN:
		return false
	_win_tackle(best)
	return true

func _resolve_cpu_tackle(carrier: Dictionary) -> void:
	# Compatibility entry point for focused CPU and goalkeeper tests.
	_resolve_ai_tackle(carrier)

func _win_tackle(defender: Dictionary, is_tackle: bool = true) -> void:
	var previous_carrier_id := carrier_id
	var facing := Coordinate3D.ground(defender.facing).normalized()
	if facing.is_zero_approx():
		facing = Vector3.RIGHT if bool(defender.home) else Vector3.LEFT
	carrier_id = int(defender.id)
	dribble_touch_timer = 0.0
	dribble_loss_timer = 0.0
	_reset_dribble_turn_state()
	_set_ball_state(Coordinate3D.ground(defender.position) + facing * 0.42, Vector3.ZERO, true)
	last_touch_home = bool(defender.home)
	if previous_carrier_id >= 0 and previous_carrier_id != int(defender.id):
		_add_stumble(previous_carrier_id, STUMBLE_RECOVERY_SECONDS)
	_clear_shot_charge()
	cpu_tackle_cooldown = 0.5
	if is_tackle:
		_set_tackle_recovery(int(defender.id))
	else:
		_set_pressure_cooldown(int(defender.id), PRESSURE_COOLDOWN_SECONDS)
	_event_label.text = "TACKLE" if is_tackle else "PRESSURE"
	_event_timer = 0.32
	_emit_action_event("tackle" if is_tackle else "pressure", {"player_id": int(defender.id)})
	var defender_view := _views.get(int(defender.id)) as Player3DView
	if defender_view != null:
		defender_view.play_action("tackle" if is_tackle else "pressure")

func _is_tackle_recovering(player: Dictionary) -> bool:
	return float(player.get("tackle_recovery", 0.0)) > 0.0

func _set_tackle_recovery(player_id: int) -> void:
	for index in players.size():
		var player := players[index]
		if int(player.id) != player_id:
			continue
		player.tackle_recovery = TACKLE_RECOVERY_SECONDS
		player.velocity = Vector3.ZERO
		player.movement_intent = false
		players[index] = player
		return

func _hold_tackle_recovery_ball(carrier: Dictionary) -> void:
	var facing := Coordinate3D.ground(carrier.facing).normalized()
	if facing.is_zero_approx():
		facing = Vector3.RIGHT if bool(carrier.home) else Vector3.LEFT
	_set_ball_state(Coordinate3D.ground(carrier.position) + facing * 0.42, Vector3.ZERO, true)

func _handle_carrier_actions(carrier: Dictionary, delta: float) -> void:
	var carrier_home := bool(carrier.home)
	if int(carrier.id) == controlled_id:
		var aim := _input_direction()
		if aim.is_zero_approx():
			aim = carrier.facing
		if action_cooldown <= 0.0 and _action_just_pressed("p1_pass"):
			_kick_to_target(carrier, false, aim)
		elif action_cooldown <= 0.0 and _action_just_pressed("p1_through_pass"):
			_kick_to_target(carrier, false, aim, true)
		elif action_cooldown <= 0.0 and _action_just_pressed("p1_long_pass"):
			_kick_to_target(carrier, true, aim)
		elif action_cooldown <= 0.0 and Input.is_action_pressed("p1_shoot"):
			shot_charging = true
			shot_charge = minf(shot_charge + maxf(delta, 0.0), SHOOT_CHARGE_SECONDS)
		elif shot_charging and _action_just_released("p1_shoot"):
			_shoot(carrier, aim.y, shot_charge / SHOOT_CHARGE_SECONDS)
			shot_charge = 0.0
			shot_charging = false
		return
	if shot_charging:
		_clear_shot_charge()
	if not carrier_home and cpu_action_cooldown <= 0.0:
		var goal_distance := absf(carrier.position.x - (0.0 if not carrier_home else Rules.PITCH_SIZE.x))
		if goal_distance < 21.0:
			_shoot(carrier, (Rules.PITCH_SIZE.z * 0.5 - carrier.position.z) * 0.35)
		elif frame_count % 3 == 0:
			var target := Rules.select_safe_pass_target(players, int(carrier.id), carrier_home, ball_position)
			if not target.is_empty():
				_kick_to_cpu_target(carrier, target)
		cpu_action_cooldown = 0.85

func _kick_to_cpu_target(carrier: Dictionary, target: Dictionary) -> void:
	var lead: Vector3 = target.velocity * 0.16
	var launch_velocity := Rules.pass_velocity(ball_position, target.position + lead)
	launch_velocity.y = 1.4
	var launch_position := ball_position
	launch_position.y = 0.12
	_set_ball_state(launch_position, launch_velocity, false)
	ball_bounce_count = 0
	ball_grounded = false
	ball_flight_time = 0.0
	carrier_id = -1
	dribble_touch_timer = 0.0
	dribble_loss_timer = 0.0
	_reset_dribble_turn_state()
	last_touch_home = bool(carrier.home)
	action_cooldown = 0.22
	_event_label.text = "PASS"
	_event_timer = 0.35
	_emit_action_event("pass", {"player_id": int(carrier.id)})
	var passer_view := _views.get(int(carrier.id)) as Player3DView
	if passer_view != null:
		passer_view.play_action("pass")

func _kick_to_target(carrier: Dictionary, long_pass: bool, aim: Vector3, through_pass: bool = false) -> void:
	var target := Rules.select_pass_target(players, int(carrier.id), bool(carrier.home), aim, ball_position)
	if target.is_empty():
		return
	var target_velocity: Vector3 = target.velocity
	var lead := target_velocity * (0.28 if long_pass else (0.55 if through_pass else 0.16))
	var launch_velocity: Vector3 = Rules.pass_velocity(ball_position, target.position + lead, long_pass)
	launch_velocity.y = 7.8 if long_pass else (2.6 if through_pass else 1.4)
	var launch_position := ball_position
	launch_position.y = 0.12
	_set_ball_state(launch_position, launch_velocity, false)
	ball_bounce_count = 0
	ball_grounded = false
	ball_flight_time = 0.0
	carrier_id = -1
	dribble_touch_timer = 0.0
	dribble_loss_timer = 0.0
	_reset_dribble_turn_state()
	_clear_shot_charge()
	last_touch_home = bool(carrier.home)
	action_cooldown = 0.22
	_event_label.text = "LONG PASS" if long_pass else ("THROUGH" if through_pass else "PASS")
	_event_timer = 0.35
	_emit_action_event("pass", {"player_id": int(carrier.id), "long": long_pass, "through": through_pass})
	var passer_view := _views.get(int(carrier.id)) as Player3DView
	if passer_view != null:
		passer_view.play_action("pass")

func _shoot(carrier: Dictionary, vertical_aim: float, power_ratio: float = 1.0) -> void:
	var launch := Rules.shot_velocity(ball_position, bool(carrier.home), vertical_aim)
	var power := lerpf(0.72, 1.0, clampf(power_ratio, 0.0, 1.0))
	var launch_velocity: Vector3 = launch * power
	launch_velocity.y = 5.0
	var launch_position := ball_position
	launch_position.y = 0.14
	_set_ball_state(launch_position, launch_velocity, false)
	ball_bounce_count = 0
	ball_grounded = false
	ball_flight_time = 0.0
	carrier_id = -1
	dribble_touch_timer = 0.0
	dribble_loss_timer = 0.0
	_reset_dribble_turn_state()
	_clear_shot_charge()
	last_touch_home = bool(carrier.home)
	action_cooldown = 0.28
	_event_label.text = "SHOT"
	_event_timer = 0.42
	_emit_action_event("shot", {"player_id": int(carrier.id), "power": power})
	camera_shake = maxf(camera_shake, 0.08)
	var shooter_view := _views.get(int(carrier.id)) as Player3DView
	if shooter_view != null:
		shooter_view.play_action("shot")

func _attempt_tackle(defender: Dictionary) -> void:
	var carrier := _player_by_id(carrier_id)
	if defender.is_empty() or carrier.is_empty():
		return
	if _is_tackle_recovering(defender):
		return
	if bool(defender.home) != bool(carrier.home) and \
		defender.position.distance_to(Coordinate3D.ground(ball_position)) < 1.55:
		_win_tackle(defender)
	action_cooldown = 0.35

func _capture_free_ball() -> void:
	var candidate_id := Rules.nearest_player_id(players, ball_position)
	var candidate := _player_by_id(candidate_id)
	if candidate.is_empty() or not Rules.can_ground_player_control_ball(
		candidate.position, ball_position):
		return
	if bool(candidate.home) == last_touch_home and Coordinate3D.ground(ball_velocity).length() > 21.0:
		return
	carrier_id = candidate_id
	dribble_touch_timer = 0.0
	dribble_loss_timer = 0.0
	_reset_dribble_turn_state()
	last_touch_home = bool(candidate.home)

func _resolve_player_separation() -> void:
	for first_index in players.size():
		for second_index in range(first_index + 1, players.size()):
			var first := players[first_index]
			var second := players[second_index]
			var resolved := Rules.resolve_pair_separation(first.position, second.position)
			first.position = resolved.first
			second.position = resolved.second
			players[first_index] = first
			players[second_index] = second

func _update_controlled_player() -> void:
	if carrier_id >= 0:
		var carrier := _player_by_id(carrier_id)
		if not carrier.is_empty() and bool(carrier.home):
			controlled_id = carrier_id
			return
	if not _player_by_id(controlled_id).is_empty():
		return
	controlled_id = Rules.nearest_player_id(players, ball_position, 1)

func _score_goal(home_scored: bool) -> void:
	var scorer_id := carrier_id
	var assist_id := -1
	if match_flow == null or not match_flow.record_goal(home_scored, scorer_id, assist_id):
		return
	_sync_match_flow_state()
	# Freeze the scored state on a deterministic kickoff tableau while the goal
	# result/replay is shown. This keeps the next restart and all presentation
	# consumers on the same positions without advancing live play.
	_reset_kickoff(not home_scored, false)
	_event_label.text = "GOAL!"
	_event_timer = 1.6
	camera_shake = maxf(camera_shake, 0.3)

func _begin_boundary_restart(boundary_axis: String) -> void:
	if match_flow == null or not Flow.is_live_phase(match_flow.phase):
		return
	var restart := Rules.boundary_restart(ball_position, boundary_axis, last_touch_home)
	match_flow.begin_restart(int(restart.type), bool(restart.team_home), restart.position, str(restart.reason))
	_sync_match_flow_state()

func _sync_match_flow_state() -> void:
	if match_flow == null:
		return
	score_home = match_flow.score_home
	score_away = match_flow.score_away
	match_time = match_flow.clock
	kickoff_timer = maxf(match_flow.phase_timer, 0.0) if match_flow.phase == Flow.Phase.KICKOFF or \
		match_flow.phase == Flow.Phase.GOAL_RESULT else 0.0
	for event in match_flow.consume_events():
		last_match_event = event.copy()
		match_event_emitted.emit(last_match_event)
		if camera_director != null:
			camera_director.consume_event(last_match_event)
		match event.name:
			"goal":
				if _event_label != null:
					_event_label.text = "GOAL!"
				_event_timer = maxf(_event_timer, match_flow.presentation_duration)
				_begin_replay()
			"restart_ready":
				var restart: Dictionary = event.payload
				_reset_kickoff(bool(restart.get("team_home", restart_team_home)), false)
			"restart":
				_prepare_set_piece(event.payload)
			"halftime":
				_swap_attacking_sides()
				if _event_label != null:
					_event_label.text = "HALF TIME"
				_event_timer = match_flow.halftime_duration
			"stoppage_time":
				if _event_label != null:
					_event_label.text = "LOSS TIME"
				_event_timer = match_flow.stoppage_duration
			"full_time":
				if _event_label != null:
					_event_label.text = "FULL TIME"
				_event_timer = 999.0

func _prepare_set_piece(restart: Dictionary) -> void:
	var position := restart.get("position", ball_position) as Vector3
	_set_ball_state(position, Vector3.ZERO, true)
	carrier_id = Rules.nearest_player_id(players, position, 1 if bool(restart.get("team_home", true)) else -1)
	controlled_id = carrier_id if bool(restart.get("team_home", true)) else controlled_id
	if _event_label != null:
		_event_label.text = Flow.restart_name(int(restart.get("type", Flow.RestartType.INDIRECT)))
	_event_timer = match_flow.presentation_duration

func _swap_attacking_sides() -> void:
	for index in players.size():
		var player := players[index]
		var spawn := player.spawn as Vector3
		player.spawn = Vector3(Rules.PITCH_SIZE.x - spawn.x, 0.0, spawn.z)
		player.position = player.spawn
		player.facing = Vector3.LEFT if bool(player.home) else Vector3.RIGHT
		players[index] = player

func _record_presentation_snapshot() -> void:
	if replay_buffer != null:
		replay_buffer.append(MatchSnapshotScript.new(build_presentation_snapshot()))

func _begin_replay() -> void:
	if replay_buffer == null:
		return
	replay_frames = replay_buffer.snapshot_frames(180)
	replay_active = replay_frames.size() >= 12
	replay_cursor = 0
	replay_tick_timer = 0.0

func _reset_kickoff(home_kicks_off: bool, update_flow := true) -> void:
	for index in players.size():
		var player := players[index]
		player.position = player.spawn
		player.velocity = Vector3.ZERO
		player.tackle_recovery = 0.0
		player.stumble_recovery = 0.0
		player.pressure_cooldown = 0.0
		players[index] = player
	var kickoff_position := Vector3(Rules.PITCH_SIZE.x * 0.5, 0.0, Rules.PITCH_SIZE.z * 0.5)
	_set_ball_state(kickoff_position, Vector3.ZERO, true)
	if _ball_view != null:
		_ball_view.reset_roll_baseline()
	ball_bounce_count = 0
	ball_grounded = true
	ball_flight_time = 0.0
	carrier_id = 9 if home_kicks_off else 20
	dribble_touch_timer = 0.0
	dribble_loss_timer = 0.0
	dribble_touch_count = 0
	_reset_dribble_turn_state()
	# Put the kickoff taker on the spot. The old carried-ball code hid this
	# formation mismatch by teleporting the ball to the player every frame.
	for index in players.size():
		if int(players[index].id) == carrier_id:
			var kickoff_player := players[index]
			kickoff_player.position = Coordinate3D.ground(kickoff_position)
			kickoff_player.velocity = Vector3.ZERO
			kickoff_player.facing = Vector3.RIGHT if home_kicks_off else Vector3.LEFT
			players[index] = kickoff_player
			break
	_clear_shot_charge()
	last_touch_home = home_kicks_off
	restart_team_home = home_kicks_off
	kickoff_timer = KICKOFF_DELAY
	if update_flow and match_flow != null:
		match_flow.begin_restart(Flow.RestartType.KICKOFF, home_kicks_off,
			Vector3(Rules.PITCH_SIZE.x * 0.5, 0.0, Rules.PITCH_SIZE.z * 0.5), "KICKOFF")
		_sync_match_flow_state()

func _player_by_id(id: int) -> Dictionary:
	for player: Dictionary in players:
		if int(player.id) == id:
			return player
	return {}

func _clear_shot_charge() -> void:
	shot_charge = 0.0
	shot_charging = false

func _set_ball_state(position: Vector3, velocity: Vector3, grounded: bool = false) -> void:
	ball_position = position
	ball_velocity = velocity
	ball_grounded = grounded

func _sync_views(interpolate_ball := false) -> void:
	if replay_active and replay_cursor < replay_frames.size():
		_sync_replay_views(replay_frames[replay_cursor])
		return
	for player: Dictionary in players:
		var view := _views.get(int(player.id)) as Player3DView
		if view == null:
			continue
		view.sync_world_position(player.position)
		view.set_facing(player.facing)
		view.set_motion(player.velocity, bool(player.get("goalkeeper", false)), int(player.id) == carrier_id)
		view.set_selected(int(player.id) == controlled_id)
		view.set_ball_carrier(int(player.id) == carrier_id)
	if _ball_view != null:
		var presented_ball_position := ball_position
		# Carried balls are already constrained by foot contacts, so keep them
		# aligned with the directly rendered player. Interpolation is for free
		# balls, whose pass and clearance speeds make fixed-tick stepping visible.
		if interpolate_ball and carrier_id < 0 and _has_previous_ball_position:
			var interpolation_weight := clampf(_simulation_accumulator / FIXED_TICK, 0.0, 1.0)
			presented_ball_position = _previous_ball_position.lerp(ball_position, interpolation_weight)
		_ball_view.sync_world_position(presented_ball_position, ball_velocity)

func _sync_replay_views(snapshot) -> void:
	var data: Dictionary = snapshot.to_dict()
	for player_data: Dictionary in data.players:
		var view := _views.get(int(player_data.get("id", -1))) as Player3DView
		if view == null:
			continue
		view.sync_world_position(player_data.get("position", Vector3.ZERO) as Vector3)
		view.set_facing(player_data.get("facing", Vector3.RIGHT) as Vector3)
		view.set_motion(player_data.get("velocity", Vector3.ZERO) as Vector3,
			bool(player_data.get("goalkeeper", false)), int(player_data.get("id", -1)) == snapshot.carrier_id)
		view.set_selected(int(player_data.get("id", -1)) == snapshot.selected_player_id)
		view.set_ball_carrier(int(player_data.get("id", -1)) == snapshot.carrier_id)
	if _ball_view != null:
		var replay_ball: Dictionary = data.ball
		_ball_view.sync_world_position(replay_ball.get("position", Vector3.ZERO) as Vector3,
			replay_ball.get("velocity", Vector3.ZERO) as Vector3)

func _create_hud() -> void:
	_match_hud = MatchHUDScript.new()
	add_child(_match_hud)
	_score_label = _match_hud.score_label
	_clock_label = _match_hud.clock_label
	_event_label = _match_hud.event_label
	_power_bar = _match_hud.power_bar

func _create_audio() -> void:
	for entry in [["pass", PASS_SFX], ["shot", SHOT_SFX], ["tackle", TACKLE_SFX], ["whistle", WHISTLE_SFX]]:
		var player := AudioStreamPlayer.new()
		player.stream = entry[1]
		player.volume_db = -8.0
		add_child(player)
		_sfx_players[entry[0]] = player

func _play_sfx(name: String) -> void:
	var player := _sfx_players.get(name) as AudioStreamPlayer
	if player != null:
		player.play()

func _emit_action_event(name: String, payload: Dictionary) -> void:
	var event := MatchEventScript.new(name, _simulation_tick, payload)
	last_match_event = event
	if camera_director != null:
		camera_director.consume_event(event)
	match_event_emitted.emit(event)

func _on_match_event(event) -> void:
	match event.name:
		"goal", "halftime", "full_time":
			_play_sfx("whistle")
		"pass":
			_play_sfx("pass")
		"shot":
			_play_sfx("shot")
		"tackle", "pressure":
			_play_sfx("tackle")

func _hud_label(font_size: int, alignment: HorizontalAlignment, scale: float = HUD_SCALE) -> Label:
	var label := Label.new()
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", maxi(1, roundi(font_size * scale)))
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0.02, 0.04, 0.08, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label

func _update_hud() -> void:
	if _match_hud == null:
		return
	if replay_active and _event_timer <= 0.0:
		_event_label.text = "REPLAY"
	elif match_flow != null and match_flow.phase == Flow.Phase.STOPPAGE_TIME:
		_event_label.text = "LOSS TIME"
	elif kickoff_timer > 0.0 and _event_timer <= 0.0:
		_event_label.text = "KICK OFF"
	elif _event_timer <= 0.0 and match_time > 0.0:
		_event_label.text = ""
	_match_hud.update_from_snapshot(build_presentation_snapshot(), shot_charging, shot_charge, SHOOT_CHARGE_SECONDS)

func _input_direction() -> Vector3:
	var input := Input.get_vector("p1_left", "p1_right", "p1_up", "p1_down")
	return Vector3(input.x, 0.0, input.y)

func build_presentation_snapshot() -> Dictionary:
	## Copy-only boundary for interpolation/debug renderers.
	var player_snapshot: Array[Dictionary] = []
	var radar_snapshot: Array[Dictionary] = []
	for player: Dictionary in players:
		player_snapshot.append({"id": int(player.id), "home": bool(player.home),
			"position": player.position, "facing": player.facing,
			"velocity": player.velocity, "goalkeeper": bool(player.get("goalkeeper", false))})
		radar_snapshot.append({"id": int(player.id), "home": bool(player.home),
			"position": player.position})
	return {"tick": _simulation_tick, "phase": match_flow.phase if match_flow != null else Flow.Phase.KICKOFF,
		"half": match_flow.half if match_flow != null else 1, "clock": match_time,
		"score_home": score_home, "score_away": score_away, "selected_player_id": controlled_id,
		"carrier_id": carrier_id, "event_label": _event_label.text if _event_label != null else "",
		"players": player_snapshot, "radar": radar_snapshot,
		"ball": {"position": ball_position, "velocity": ball_velocity,
			"bounce_count": ball_bounce_count,
			"grounded": ball_grounded, "flight_time": ball_flight_time}}

func _advance_replay(delta: float) -> void:
	if not replay_active:
		return
	replay_tick_timer += maxf(delta, 0.0) * 2.0
	while replay_tick_timer >= FIXED_TICK:
		replay_tick_timer -= FIXED_TICK
		replay_cursor += 1
		if replay_cursor >= replay_frames.size():
			replay_active = false
			replay_frames.clear()
			return
