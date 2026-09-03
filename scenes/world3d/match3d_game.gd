class_name Match3DGame
extends Node3D

const Rules := preload("res://utils/match3d_rules.gd")
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

var players: Array[Dictionary] = []
var ball_position := Rules.PITCH_SIZE * 0.5
var ball_velocity := Vector2.ZERO
var ball_height := 0.0
var ball_height_velocity := 0.0
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
var shot_charge := 0.0
var shot_charging := false

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
		camera.position = Vector3(Rules.PITCH_SIZE.x * 0.5, 42.0, Rules.PITCH_SIZE.y * 0.5 + 32.0)
		camera.look_at(Vector3(Rules.PITCH_SIZE.x * 0.5, 0.0, Rules.PITCH_SIZE.y * 0.5))

func _update_camera(delta: float) -> void:
	var camera := get_node_or_null("Camera") as Camera3D
	if camera == null:
		return
	var camera_target := Rules.camera_target(ball_position)
	var target := Vector3(camera_target.x, 0.0, camera_target.y)
	var shake := Vector3(sin(float(frame_count) * 1.7), cos(float(frame_count) * 2.1), 0.0) * camera_shake
	var desired := target + Vector3(0.0, 42.0, 32.0) + shake
	camera_shake = maxf(camera_shake - delta * 1.8, 0.0)
	camera.position = camera.position.lerp(desired, 1.0 - exp(-3.6 * delta))
	camera.look_at(target)

func _process(delta: float) -> void:
	var step := minf(delta, 1.0 / 30.0)
	if kickoff_timer > 0.0:
		_handle_kickoff_input()
		kickoff_timer -= step
		_event_timer = maxf(_event_timer - step, 0.0)
		_sync_views()
		_update_camera(step)
		_update_hud()
		return
	match_time = maxf(match_time - step, 0.0)
	if match_time <= 0.0:
		_event_label.text = "FULL TIME"
		_sync_views()
		_update_camera(step)
		_update_hud()
		return
	frame_count += 1
	action_cooldown = maxf(action_cooldown - step, 0.0)
	cpu_action_cooldown = maxf(cpu_action_cooldown - step, 0.0)
	cpu_tackle_cooldown = maxf(cpu_tackle_cooldown - step, 0.0)
	_event_timer = maxf(_event_timer - step, 0.0)
	_handle_player_switch()
	_update_controlled_player()
	_step_players(step)
	if action_cooldown <= 0.0 and Input.is_action_just_pressed("p1_special"):
		_attempt_tackle(_player_by_id(controlled_id))
	_step_ball(step)
	_resolve_player_separation()
	_sync_views()
	_update_camera(step)
	_update_hud()

func _handle_kickoff_input() -> void:
	if carrier_id < 0:
		return
	var carrier := _player_by_id(carrier_id)
	if carrier.is_empty() or not bool(carrier.home):
		return
	controlled_id = carrier_id
	var aim := Input.get_vector("p1_left", "p1_right", "p1_up", "p1_down")
	if aim.is_zero_approx():
		aim = carrier.facing
	if Input.is_action_just_pressed("p1_pass"):
		kickoff_timer = 0.0
		_kick_to_target(carrier, false, aim)
	elif Input.is_action_just_pressed("p1_long_pass"):
		kickoff_timer = 0.0
		_kick_to_target(carrier, true, aim)
	elif Input.is_action_just_pressed("p1_shoot"):
		kickoff_timer = 0.0
		_shoot(carrier, aim.y)

func _create_match() -> void:
	var formation := [
		Vector2(4.0, 18.0), Vector2(15.0, 7.0), Vector2(15.0, 14.0), Vector2(15.0, 22.0), Vector2(15.0, 29.0),
		Vector2(29.0, 9.0), Vector2(30.0, 18.0), Vector2(29.0, 27.0), Vector2(43.0, 8.0), Vector2(46.0, 18.0), Vector2(43.0, 28.0),
	]
	for home in [true, false]:
		for index in formation.size():
			var spawn: Vector2 = formation[index]
			if not home:
				spawn.x = Rules.PITCH_SIZE.x - spawn.x
			var id := index if home else index + formation.size()
			var entry := {"id": id, "home": home, "position": spawn, "spawn": spawn,
				"velocity": Vector2.ZERO, "facing": Vector2.RIGHT if home else Vector2.LEFT, "goalkeeper": index == 0}
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
	for index in players.size():
		var player := players[index]
		var desired := _player_intent(player)
		var speed := 7.5 if bool(player.goalkeeper) else 8.8
		if int(player.id) == controlled_id and Input.is_action_pressed("p1_sprint"):
			speed = 11.0
		var motion := Rules.advance_player(player.position, player.velocity, desired, delta, speed)
		player.position = motion.position
		player.velocity = motion.velocity
		if not desired.is_zero_approx():
			player.facing = desired.normalized()
		players[index] = player

func _player_intent(player: Dictionary) -> Vector2:
	var id := int(player.id)
	var home := bool(player.home)
	if id == controlled_id:
		var input := Input.get_vector("p1_left", "p1_right", "p1_up", "p1_down")
		if not input.is_zero_approx():
			return input
	if id == carrier_id:
		var facing: Vector2 = player.facing
		if home:
			return facing.lerp(Vector2.RIGHT, 0.25).normalized()
		return facing.lerp(Vector2.LEFT, 0.25).normalized()
	var target: Vector2 = player.spawn
	var carrier := _player_by_id(carrier_id)
	if not carrier.is_empty():
		var carrier_position: Vector2 = carrier.position
		if bool(carrier.home) == home:
			target += Vector2(2.2 if home else -2.2, (carrier_position.y - target.y) * 0.15)
		else:
			var pressure := clampf(1.0 - player.position.distance_to(carrier_position) / 20.0, 0.0, 1.0)
			target = target.lerp(carrier_position, pressure * (0.75 if not bool(player.goalkeeper) else 0.2))
	elif player.position.distance_to(ball_position) < 12.0:
		target = ball_position
	return player.position.direction_to(target)

func _handle_player_switch() -> void:
	if not Input.is_action_just_pressed("p1_through_pass"):
		return
	var direction := Input.get_vector("p1_left", "p1_right", "p1_up", "p1_down")
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
			_clear_shot_charge()
			return
		if bool(carrier.home):
			_resolve_cpu_tackle(carrier)
		if carrier_id != int(carrier.id):
			_clear_shot_charge()
			return
		_handle_carrier_actions(carrier, delta)
		if carrier_id >= 0:
			var facing: Vector2 = carrier.facing
			ball_position = carrier.position + facing * 0.66
			ball_velocity = carrier.velocity
			ball_height = 0.08 + sin(float(frame_count) * 0.3) * 0.025
		return
	ball_position += ball_velocity * delta
	ball_velocity = ball_velocity.move_toward(Vector2.ZERO, 14.0 * delta)
	ball_height_velocity -= 22.0 * delta
	ball_height = maxf(0.08, ball_height + ball_height_velocity * delta)
	if ball_height <= 0.08:
		ball_height_velocity = 0.0
	if ball_position.y < 0.0 or ball_position.y > Rules.PITCH_SIZE.y:
		ball_position.y = clampf(ball_position.y, 0.0, Rules.PITCH_SIZE.y)
		ball_velocity.y *= -0.62
	var scorer := Rules.goal_scoring_team(ball_position)
	if scorer != 0:
		_score_goal(scorer > 0)
		return
	_capture_free_ball()

func _resolve_cpu_tackle(carrier: Dictionary) -> void:
	if cpu_tackle_cooldown > 0.0:
		return
	var best: Dictionary = {}
	var best_distance := INF
	for player: Dictionary in players:
		if bool(player.home) or bool(player.goalkeeper):
			continue
		var distance := (player.position as Vector2).distance_to(ball_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	if best.is_empty() or best_distance > 1.45:
		return
	var approach: Vector2 = (best.position as Vector2).direction_to(carrier.position)
	var facing: Vector2 = best.facing
	if facing.dot(approach) < -0.35:
		return
	carrier_id = int(best.id)
	last_touch_home = false
	_clear_shot_charge()
	cpu_tackle_cooldown = 0.5
	_event_label.text = "TACKLE"
	_event_timer = 0.32
	_play_sfx("tackle")
	camera_shake = maxf(camera_shake, 0.12)
	var defender_view := _views.get(int(best.id)) as Player3DView
	if defender_view != null:
		defender_view.play_action("tackle")

func _handle_carrier_actions(carrier: Dictionary, delta: float) -> void:
	var carrier_home := bool(carrier.home)
	if int(carrier.id) == controlled_id:
		var aim := Input.get_vector("p1_left", "p1_right", "p1_up", "p1_down")
		if aim.is_zero_approx():
			aim = carrier.facing
		if action_cooldown <= 0.0 and Input.is_action_just_pressed("p1_pass"):
			_kick_to_target(carrier, false, aim)
		elif action_cooldown <= 0.0 and Input.is_action_just_pressed("p1_long_pass"):
			_kick_to_target(carrier, true, aim)
		elif action_cooldown <= 0.0 and Input.is_action_pressed("p1_shoot"):
			shot_charging = true
			shot_charge = minf(shot_charge + maxf(delta, 0.0), SHOOT_CHARGE_SECONDS)
		elif shot_charging and Input.is_action_just_released("p1_shoot"):
			_shoot(carrier, aim.y, shot_charge / SHOOT_CHARGE_SECONDS)
			shot_charge = 0.0
			shot_charging = false
		return
	if shot_charging:
		_clear_shot_charge()
	if not carrier_home and cpu_action_cooldown <= 0.0:
		var goal_distance := absf(carrier.position.x - (0.0 if not carrier_home else Rules.PITCH_SIZE.x))
		if goal_distance < 21.0:
			_shoot(carrier, (Rules.PITCH_SIZE.y * 0.5 - carrier.position.y) * 0.35)
		elif frame_count % 3 == 0:
			_kick_to_target(carrier, false, Vector2.LEFT)
		cpu_action_cooldown = 0.85

func _kick_to_target(carrier: Dictionary, long_pass: bool, aim: Vector2) -> void:
	var target := Rules.select_pass_target(players, int(carrier.id), bool(carrier.home), aim, ball_position)
	if target.is_empty():
		return
	var target_velocity: Vector2 = target.velocity
	var lead := target_velocity * (0.28 if long_pass else 0.16)
	ball_velocity = Rules.pass_velocity(ball_position, target.position + lead, long_pass)
	ball_height = 0.12
	ball_height_velocity = 7.8 if long_pass else 1.4
	carrier_id = -1
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
	ball_velocity = launch * power
	ball_height = 0.14
	ball_height_velocity = 5.0
	carrier_id = -1
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
	if bool(defender.home) and not bool(carrier.home) and defender.position.distance_to(ball_position) < 1.55:
		carrier_id = int(defender.id)
		_clear_shot_charge()
		last_touch_home = true
		_event_label.text = "TACKLE"
		_event_timer = 0.32
		_play_sfx("tackle")
		camera_shake = maxf(camera_shake, 0.12)
		var tackler_view := _views.get(int(defender.id)) as Player3DView
		if tackler_view != null:
			tackler_view.play_action("tackle")
	action_cooldown = 0.35

func _capture_free_ball() -> void:
	var candidate_id := Rules.nearest_player_id(players, ball_position)
	var candidate := _player_by_id(candidate_id)
	if candidate.is_empty() or candidate.position.distance_to(ball_position) > Rules.CONTROL_RADIUS:
		return
	if bool(candidate.home) == last_touch_home and ball_velocity.length() > 21.0:
		return
	carrier_id = candidate_id
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
		player.velocity = Vector2.ZERO
		players[index] = player
	ball_position = Rules.PITCH_SIZE * 0.5
	ball_velocity = Vector2.ZERO
	ball_height = 0.08
	ball_height_velocity = 0.0
	carrier_id = 9 if home_kicks_off else 20
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

func _sync_views() -> void:
	for player: Dictionary in players:
		var view := _views.get(int(player.id)) as Player3DView
		if view == null:
			continue
		view.sync_from_simulation(player.position * 10.0, 0.0)
		view.set_facing(player.facing)
		view.set_selected(int(player.id) == controlled_id)
		view.set_ball_carrier(int(player.id) == carrier_id)
	if _ball_view != null:
		_ball_view.sync_from_simulation(ball_position * 10.0, ball_height * 10.0)

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
