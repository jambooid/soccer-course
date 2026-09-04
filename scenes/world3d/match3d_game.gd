class_name Match3DGame
extends Node3D

const Rules := preload("res://utils/match3d_rules.gd")
const BallTrajectory3DScript := preload("res://utils/ball_trajectory_3d.gd")
const BallPhysics3D := preload("res://utils/ball_physics_3d_constants.gd")
const DribblePhysics3D := preload("res://utils/dribble_physics_3d.gd")
const Coordinate3D := preload("res://utils/pitch_coordinate_3d.gd")
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
const CAMERA_BASE_POSITION := Vector3(42.5, 42.0, 50.0)
const CAMERA_BASE_FOCUS := Vector3(42.5, 0.0, 18.0)
const CAMERA_LATERAL_FOLLOW := 0.30
const CAMERA_LATERAL_LIMIT := 14.0
const CAMERA_LATERAL_DEADZONE := 2.5

enum DribblePhase { FREE_ROLL, TURNAROUND_ANCHOR }

var players: Array[Dictionary] = []
var ball_position := Vector3(Rules.PITCH_SIZE.x * 0.5, 0.08, Rules.PITCH_SIZE.z * 0.5)
var ball_velocity := Vector3.ZERO
var ball_bounce_count := 0
var ball_grounded := true
var ball_flight_time := 0.0
var _simulation_accumulator := 0.0
var _simulation_tick := 0
var _sampled_just_pressed: Dictionary = {}
var _sampled_just_released: Dictionary = {}
var carrier_id := -1
var controlled_id := -1
var score_home := 0
var score_away := 0
var match_time := MATCH_SECONDS
var kickoff_timer := KICKOFF_DELAY
var restart_team_home := true
var last_touch_home := true
var action_cooldown := 0.0
var cpu_action_cooldown := 0.65
var cpu_tackle_cooldown := 0.0
var frame_count := 0
var camera_shake := 0.0
var camera_lateral_offset := 0.0
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
var dribble_turn_anchor_direction := Vector3.ZERO
var dribble_turn_release_velocity := Vector3.ZERO
var dribble_last_turn_type := DribblePhysics3D.TurnType.NONE
var dribble_phase := DribblePhase.FREE_ROLL
var dribble_turn_lock_timer := 0.0
var dribble_turn_locked_direction := Vector3.ZERO
var _views: Dictionary = {}
var _ball_view: Ball3DView
var _score_label: Label
var _clock_label: Label
var _event_label: Label
var _event_timer := 0.0
var _sfx_players: Dictionary = {}
var _power_bar: ProgressBar

func _ready() -> void:
	_create_match()
	_create_hud()
	_create_audio()
	call_deferred("_frame_camera")

func _frame_camera() -> void:
	var camera := get_node_or_null("Camera") as Camera3D
	if camera != null:
		camera.position = CAMERA_BASE_POSITION
		camera.look_at(CAMERA_BASE_FOCUS)
		camera_fixed_rotation = camera.rotation
		camera_rotation_initialized = true

func _update_camera(delta: float) -> void:
	var camera := get_node_or_null("Camera") as Camera3D
	if camera == null:
		return
	if not camera_rotation_initialized:
		camera.position = CAMERA_BASE_POSITION
		camera.look_at(CAMERA_BASE_FOCUS)
		camera_fixed_rotation = camera.rotation
		camera_rotation_initialized = true
	# In this broadcast orientation, screen-left/right maps to world X. Pan only
	# along that axis; the rotation is restored every frame, so there is no yaw.
	var ball_x := clampf(ball_position.x, 0.0, Rules.PITCH_SIZE.x)
	var center_x := Rules.PITCH_SIZE.x * 0.5
	var lateral_delta := ball_x - center_x
	var target_offset := clampf(sign(lateral_delta) * maxf(absf(lateral_delta) - CAMERA_LATERAL_DEADZONE, 0.0) * CAMERA_LATERAL_FOLLOW,
		-CAMERA_LATERAL_LIMIT, CAMERA_LATERAL_LIMIT)
	camera_lateral_offset = lerpf(camera_lateral_offset, target_offset,
		1.0 - exp(-2.4 * delta))
	camera.position = CAMERA_BASE_POSITION + Vector3(camera_lateral_offset, 0.0, 0.0)
	camera.rotation = camera_fixed_rotation

func _process(delta: float) -> void:
	# Input is sampled once per render frame, while gameplay advances in a
	# deterministic 60 Hz loop. This keeps ball flight independent of V-sync.
	for action in ["p1_pass", "p1_long_pass", "p1_shoot", "p1_through_pass", "p1_special"]:
		_sampled_just_pressed[action] = Input.is_action_just_pressed(action)
		_sampled_just_released[action] = Input.is_action_just_released(action)
	_simulation_accumulator = minf(_simulation_accumulator + delta, 0.25)
	while _simulation_accumulator >= FIXED_TICK:
		_simulation_accumulator -= FIXED_TICK
		_simulate_tick(FIXED_TICK)
	_sync_views()
	_update_camera(delta)
	_update_hud()

func _simulate_tick(step: float) -> void:
	if kickoff_timer > 0.0:
		_handle_kickoff_input()
		kickoff_timer -= step
		_event_timer = maxf(_event_timer - step, 0.0)
		return
	match_time = maxf(match_time - step, 0.0)
	if match_time <= 0.0:
		_event_label.text = "FULL TIME"
		return
	frame_count += 1
	action_cooldown = maxf(action_cooldown - step, 0.0)
	cpu_action_cooldown = maxf(cpu_action_cooldown - step, 0.0)
	cpu_tackle_cooldown = maxf(cpu_tackle_cooldown - step, 0.0)
	_event_timer = maxf(_event_timer - step, 0.0)
	_handle_player_switch()
	_update_controlled_player()
	_step_players(step)
	if action_cooldown <= 0.0 and _action_just_pressed("p1_special"):
		_attempt_tackle(_player_by_id(controlled_id))
	_step_ball(step)
	_resolve_player_separation()
	_simulation_tick += 1

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
		kickoff_timer = 0.0
		_kick_to_target(carrier, false, aim)
	elif _action_just_pressed("p1_long_pass"):
		kickoff_timer = 0.0
		_kick_to_target(carrier, true, aim)
	elif _action_just_pressed("p1_shoot"):
		kickoff_timer = 0.0
		_shoot(carrier, aim.z)

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
				"cutback_cooldown": 0.0}
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
	for index in players.size():
		var player := players[index]
		var player_id := int(player.id)
		var turnaround_locked := player_id == carrier_id and dribble_turn_lock_timer > 0.0
		if turnaround_locked:
			# The turnaround clip plants the supporting foot before launch. Freeze
			# translation and face the committed lane, rather than accepting a new
			# stick direction while the cut is still being performed.
			player.velocity = Vector3.ZERO
			player.movement_intent = false
			if not dribble_turn_locked_direction.is_zero_approx():
				player.facing = player.facing.lerp(dribble_turn_locked_direction, 0.62).normalized()
			players[index] = player
			continue
		var desired := _player_intent(player)
		var has_input_intent := not desired.is_zero_approx()
		player.movement_intent = has_input_intent
		# Releasing the stick never pulls the ball back. Instead, the controlled
		# carrier coasts with the loose ball's remaining ground velocity, so both
		# settle together while possession remains intact.
		var follow_released_ball := player_id == controlled_id and player_id == carrier_id and not has_input_intent
		var released_ball_velocity := Coordinate3D.ground(ball_velocity)
		if follow_released_ball and released_ball_velocity.length() > 0.12:
			desired = released_ball_velocity.normalized()
		var speed := 7.5 if bool(player.goalkeeper) else 8.8
		if follow_released_ball:
			speed = minf(speed, released_ball_velocity.length())
		var sprint_input := player_id == controlled_id and Input.is_action_pressed("p1_sprint")
		var sprinting := player_id == carrier_id and sprint_input
		if sprint_input:
			speed = 11.0
		var acceleration := 24.0
		if sprinting:
			acceleration = 17.0
		player.cutback_cooldown = maxf(float(player.get("cutback_cooldown", 0.0)) - delta, 0.0)
		# Releasing input stops adding drive, but does not erase the player's
		# current momentum. Player and ball therefore come to rest independently.
		var motion := Rules.advance_player(player.position, player.velocity, desired, delta, speed, acceleration)
		player.position = motion.position
		player.velocity = motion.velocity
		player.dribble_mode = DribblePhysics3D.Mode.SPRINT if sprinting else DribblePhysics3D.Mode.JOG
		if not desired.is_zero_approx():
			player.input_direction = Coordinate3D.ground(desired).normalized()
			# Facing follows the actual velocity, with input only as a fallback.
			var actual_direction := Coordinate3D.ground(player.velocity).normalized()
			player.facing = actual_direction if not actual_direction.is_zero_approx() else desired.normalized()
		players[index] = player

func _player_intent(player: Dictionary) -> Vector3:
	var id := int(player.id)
	var home := bool(player.home)
	if id == controlled_id:
		var input := _input_direction()
		if not input.is_zero_approx():
			return input
		# A controlled player is fully manual. Do not fall through to the
		# carrier/formation AI when the stick is released.
		return Vector3.ZERO
	if id == carrier_id:
		var facing: Vector3 = player.facing
		if home:
			return facing.lerp(Vector3.RIGHT, 0.25).normalized()
		return facing.lerp(Vector3.LEFT, 0.25).normalized()
	var target: Vector3 = player.spawn
	var carrier := _player_by_id(carrier_id)
	if not carrier.is_empty():
		var carrier_position: Vector3 = carrier.position
		if bool(carrier.home) == home:
			target += Vector3(2.2 if home else -2.2, 0.0, (carrier_position.z - target.z) * 0.15)
		else:
			var pressure := clampf(1.0 - player.position.distance_to(carrier_position) / 20.0, 0.0, 1.0)
			target = target.lerp(carrier_position, pressure * (0.75 if not bool(player.goalkeeper) else 0.2))
	elif player.position.distance_to(Coordinate3D.ground(ball_position)) < 12.0:
		target = Coordinate3D.ground(ball_position)
	return Coordinate3D.ground(target - player.position).normalized()

func _handle_player_switch() -> void:
	if not _action_just_pressed("p1_through_pass"):
		return
	var direction := _input_direction()
	var next_id := Rules.select_switch_target(players, controlled_id, direction, ball_position)
	if next_id < 0:
		return
	controlled_id = next_id
	_event_label.text = "SWITCH"
	_event_timer = 0.3

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
		if bool(carrier.home):
			_resolve_cpu_tackle(carrier)
		if carrier_id != int(carrier.id):
			_clear_shot_charge()
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
	var contact_direction := dribble_queued_direction
	var intent_plane := DribblePhysics3D.to_pitch_plane(contact_direction)
	var carry_direction_plane := carrier_velocity_plane.normalized()
	if carry_direction_plane.is_zero_approx():
		carry_direction_plane = DribblePhysics3D.to_pitch_plane(carrier.facing).normalized()
	if carry_direction_plane.is_zero_approx():
		carry_direction_plane = intent_plane

	# The 180-degree turnaround has a short support-foot lock before the rear
	# touch is released. Every other period is independent rolling plus ordinary
	# control assistance; there is no continuous turn lerp.
	var turn_anchor_active := dribble_phase == DribblePhase.TURNAROUND_ANCHOR
	if turn_anchor_active:
		dribble_turn_anchor_timer = maxf(dribble_turn_anchor_timer - delta, 0.0)
		ball_plane = carrier_plane + DribblePhysics3D.to_pitch_plane(dribble_turn_anchor_direction) * 0.24
		ball_velocity_plane = Vector2.ZERO
		if dribble_turn_anchor_timer <= 0.0:
			ball_velocity_plane = DribblePhysics3D.to_pitch_plane(dribble_turn_release_velocity)
			dribble_turn_release_velocity = Vector3.ZERO
			dribble_phase = DribblePhase.FREE_ROLL
	else:
		# The ball is free between contacts. A contact is the sole point where a
		# new lane, a velocity reset, or a turn penalty is allowed to take effect.
		ball_velocity_plane = DribblePhysics3D.apply_ground_friction_2d(ball_velocity_plane, delta)
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
			if dribble_last_turn_type == DribblePhysics3D.TurnType.DEGREE_180:
				dribble_turn_anchor_timer = DribblePhysics3D.turn_anchor_duration(dribble_last_turn_type)
				dribble_turn_anchor_direction = DribblePhysics3D.from_pitch_plane(-carry_direction_plane)
				dribble_turn_lock_timer = DribblePhysics3D.TURNAROUND_INPUT_LOCK_SECONDS
				dribble_turn_locked_direction = contact_direction
				dribble_turn_release_velocity = DribblePhysics3D.turn_touch_velocity(
					Vector3.ZERO, carrier.velocity, carrier.facing, technique, mode,
					contact_direction, dribble_last_turn_type)
				ball_plane = carrier_plane + (-carry_direction_plane) * 0.24
				ball_velocity_plane = Vector2.ZERO
				dribble_phase = DribblePhase.TURNAROUND_ANCHOR
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
			if has_movement_intent and carrier_speed > 0.25:
				var desired_lead := DribblePhysics3D.touch_offset(technique, mode) + 0.18
				var current_lead := (ball_plane - carrier_plane).dot(intent_plane)
				if current_lead < desired_lead:
					var running_target := carrier_plane + intent_plane * desired_lead
					var running_error := running_target - ball_plane
					if not running_error.is_zero_approx():
						var running_speed := maxf(carrier_speed * 1.35, 4.0)
						ball_velocity_plane = ball_velocity_plane.move_toward(
							running_error.normalized() * running_speed, 50.0 * delta)

			# Integrate only after touch and forward lead forces. There is deliberately
			# no pull back toward the carrier: an overrun ball remains independent.
			ball_plane += ball_velocity_plane * delta
	ball_plane.x = clampf(ball_plane.x, 0.12, Rules.PITCH_SIZE.x - 0.12)
	ball_plane.y = clampf(ball_plane.y, 0.12, Rules.PITCH_SIZE.z - 0.12)
	var ball_height := 0.08
	if carrier_speed > 0.12 or ball_velocity_plane.length() > 0.001:
		ball_height += sin(float(frame_count) * 0.42) * 0.012
	ball_position = DribblePhysics3D.from_pitch_plane(ball_plane, ball_height)
	ball_velocity = DribblePhysics3D.from_pitch_plane(ball_velocity_plane)
	ball_grounded = true
	ball_flight_time = 0.0
	var post_distance := ball_plane.distance_to(carrier_plane)
	var away_from_carrier := ball_velocity_plane.dot(ball_plane - carrier_plane) > 0.0
	var carrier_pulling_away := carrier_velocity_plane.dot(carrier_plane - ball_plane) > 0.0
	var external_force := (ball_velocity_plane - carrier_velocity_plane).length() > 14.0
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
	dribble_turn_anchor_direction = Vector3.ZERO
	dribble_turn_release_velocity = Vector3.ZERO
	dribble_last_turn_type = DribblePhysics3D.TurnType.NONE
	dribble_phase = DribblePhase.FREE_ROLL
	dribble_turn_lock_timer = 0.0
	dribble_turn_locked_direction = Vector3.ZERO

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

func _opponent_interfering(carrier: Dictionary, ball: Vector3) -> bool:
	var carrier_home := bool(carrier.home)
	for player: Dictionary in players:
		if bool(player.home) == carrier_home:
			continue
		var distance := Coordinate3D.ground((player.position as Vector3) - ball).length()
		if distance <= 1.65:
			return true
	return false

func _resolve_cpu_tackle(carrier: Dictionary) -> void:
	if cpu_tackle_cooldown > 0.0:
		return
	var best: Dictionary = {}
	var best_distance := INF
	for player: Dictionary in players:
		if bool(player.home) or bool(player.goalkeeper):
			continue
		var distance := (player.position as Vector3).distance_to(Coordinate3D.ground(ball_position))
		if distance < best_distance:
			best_distance = distance
			best = player
	if best.is_empty() or best_distance > 1.45:
		return
	var approach: Vector3 = Coordinate3D.ground(carrier.position - best.position).normalized()
	var facing: Vector3 = best.facing
	if facing.dot(approach) < -0.35:
		return
	carrier_id = int(best.id)
	dribble_touch_timer = 0.0
	dribble_loss_timer = 0.0
	_reset_dribble_turn_state()
	last_touch_home = false
	_clear_shot_charge()
	cpu_tackle_cooldown = 0.5
	_event_label.text = "TACKLE"
	_event_timer = 0.32
	_play_sfx("tackle")
	var defender_view := _views.get(int(best.id)) as Player3DView
	if defender_view != null:
		defender_view.play_action("tackle")

func _handle_carrier_actions(carrier: Dictionary, delta: float) -> void:
	var carrier_home := bool(carrier.home)
	if int(carrier.id) == controlled_id:
		var aim := _input_direction()
		if aim.is_zero_approx():
			aim = carrier.facing
		if action_cooldown <= 0.0 and _action_just_pressed("p1_pass"):
			_kick_to_target(carrier, false, aim)
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
			_kick_to_target(carrier, false, Vector3.LEFT)
		cpu_action_cooldown = 0.85

func _kick_to_target(carrier: Dictionary, long_pass: bool, aim: Vector3) -> void:
	var target := Rules.select_pass_target(players, int(carrier.id), bool(carrier.home), aim, ball_position)
	if target.is_empty():
		return
	var target_velocity: Vector3 = target.velocity
	var lead := target_velocity * (0.28 if long_pass else 0.16)
	var launch_velocity: Vector3 = Rules.pass_velocity(ball_position, target.position + lead, long_pass)
	launch_velocity.y = 7.8 if long_pass else 1.4
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
	_event_label.text = "LONG PASS" if long_pass else "PASS"
	_event_timer = 0.35
	_play_sfx("pass")
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
	_play_sfx("shot")
	camera_shake = maxf(camera_shake, 0.08)
	var shooter_view := _views.get(int(carrier.id)) as Player3DView
	if shooter_view != null:
		shooter_view.play_action("shot")

func _attempt_tackle(defender: Dictionary) -> void:
	var carrier := _player_by_id(carrier_id)
	if defender.is_empty() or carrier.is_empty():
		return
	if bool(defender.home) and not bool(carrier.home) and defender.position.distance_to(Coordinate3D.ground(ball_position)) < 1.55:
		carrier_id = int(defender.id)
		dribble_touch_timer = 0.0
		dribble_loss_timer = 0.0
		_reset_dribble_turn_state()
		_clear_shot_charge()
		last_touch_home = true
		_event_label.text = "TACKLE"
		_event_timer = 0.32
		_play_sfx("tackle")
		var tackler_view := _views.get(int(defender.id)) as Player3DView
		if tackler_view != null:
			tackler_view.play_action("tackle")
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
	if home_scored:
		score_home += 1
	else:
		score_away += 1
	_event_label.text = "GOAL!"
	_event_timer = 1.6
	_play_sfx("whistle")
	camera_shake = maxf(camera_shake, 0.3)
	_reset_kickoff(not home_scored)

func _reset_kickoff(home_kicks_off: bool) -> void:
	for index in players.size():
		var player := players[index]
		player.position = player.spawn
		player.velocity = Vector3.ZERO
		players[index] = player
	var kickoff_position := Vector3(Rules.PITCH_SIZE.x * 0.5, 0.08, Rules.PITCH_SIZE.z * 0.5)
	_set_ball_state(kickoff_position, Vector3.ZERO, true)
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

func _sync_views() -> void:
	for player: Dictionary in players:
		var view := _views.get(int(player.id)) as Player3DView
		if view == null:
			continue
		view.sync_world_position(player.position)
		view.set_facing(player.facing)
		view.set_selected(int(player.id) == controlled_id)
		view.set_ball_carrier(int(player.id) == carrier_id)
	if _ball_view != null:
		_ball_view.sync_world_position(ball_position, ball_velocity)

func _create_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var top_bar := ColorRect.new()
	top_bar.size = Vector2(560, 78)
	top_bar.color = Color(0.03, 0.06, 0.12, 0.62)
	layer.add_child(top_bar)
	_score_label = _hud_label(30, HORIZONTAL_ALIGNMENT_CENTER)
	_score_label.position = Vector2(0, 10)
	_score_label.size = Vector2(560, 38)
	layer.add_child(_score_label)
	_clock_label = _hud_label(16, HORIZONTAL_ALIGNMENT_RIGHT)
	_clock_label.position = Vector2(430, 54)
	_clock_label.size = Vector2(110, 24)
	layer.add_child(_clock_label)
	_event_label = _hud_label(22, HORIZONTAL_ALIGNMENT_CENTER)
	_event_label.position = Vector2(120, 276)
	_event_label.size = Vector2(320, 34)
	layer.add_child(_event_label)
	var controls := _hud_label(10, HORIZONTAL_ALIGNMENT_LEFT)
	controls.position = Vector2(12, 334)
	controls.size = Vector2(536, 20)
	controls.text = "WASD MOVE   I SPRINT   K PASS   O LOB   J SHOOT   U TACKLE"
	layer.add_child(controls)
	_power_bar = ProgressBar.new()
	_power_bar.position = Vector2(200, 310)
	_power_bar.size = Vector2(160, 10)
	_power_bar.max_value = SHOOT_CHARGE_SECONDS
	_power_bar.show_percentage = false
	_power_bar.modulate = Color(1.0, 0.82, 0.24)
	_power_bar.visible = false
	layer.add_child(_power_bar)

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

func _hud_label(font_size: int, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0.02, 0.04, 0.08, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label

func _update_hud() -> void:
	if _score_label == null:
		return
	_score_label.text = "BLUE  %d - %d  RED" % [score_home, score_away]
	var seconds := ceili(match_time)
	_clock_label.text = "%d:%02d" % [seconds / 60, seconds % 60]
	if _power_bar != null:
		_power_bar.value = shot_charge
		_power_bar.visible = shot_charging
	if kickoff_timer > 0.0 and _event_timer <= 0.0:
		_event_label.text = "KICK OFF"
	elif _event_timer <= 0.0 and match_time > 0.0:
		_event_label.text = ""

func _input_direction() -> Vector3:
	var input := Input.get_vector("p1_left", "p1_right", "p1_up", "p1_down")
	return Vector3(input.x, 0.0, input.y)

func build_presentation_snapshot() -> Dictionary:
	## Copy-only boundary for interpolation/debug renderers.
	var player_snapshot: Array[Dictionary] = []
	for player: Dictionary in players:
		player_snapshot.append({"id": int(player.id), "home": bool(player.home),
			"position": player.position, "facing": player.facing})
	return {"tick": _simulation_tick, "players": player_snapshot,
		"ball": {"position": ball_position, "velocity": ball_velocity,
			"bounce_count": ball_bounce_count,
			"grounded": ball_grounded, "flight_time": ball_flight_time}}
