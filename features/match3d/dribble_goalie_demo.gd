extends "res://scenes/world3d/match3d_game.gd"

## Focused WE2000-style dribbling lab: one blue carrier against one red keeper.
## It inherits the real match controller so tuning here cannot diverge from
## the 11v11 simulation.

const DEMO_PLAYER_ID := 0
const DEMO_KEEPER_ID := 1
const DEMO_START := Vector3(18.0, 0.0, 18.0)
const DEMO_KEEPER_START := Vector3(76.0, 0.0, 18.0)
const KEEPER_PRESS_DISTANCE := 1.55
const DEMO_CAMERA_BASE_POSITION := Vector3(32.0, 21.0, 32.0)
const DEMO_CAMERA_BASE_FOCUS := Vector3(32.0, 0.0, 18.0)
const DEMO_CAMERA_LATERAL_LIMIT := 18.0
const DEMO_CAMERA_LATERAL_DEADZONE := 1.8
const DEMO_CAMERA_LATERAL_FOLLOW := 0.38

var _demo_label: Label

func _ready() -> void:
	print("DEMO_READY_BEGIN")
	super._ready()
	print("DEMO_READY_END")

func _frame_camera() -> void:
	var camera := get_node_or_null("Camera") as Camera3D
	if camera == null:
		return
	camera.position = DEMO_CAMERA_BASE_POSITION
	camera.look_at(DEMO_CAMERA_BASE_FOCUS)
	camera_fixed_rotation = camera.rotation
	camera_rotation_initialized = true

func _update_camera(delta: float) -> void:
	var camera := get_node_or_null("Camera") as Camera3D
	if camera == null:
		return
	if not camera_rotation_initialized:
		_frame_camera()
	var ball_x := clampf(ball_position.x, 0.0, Rules.PITCH_SIZE.x)
	var center_x := Rules.PITCH_SIZE.x * 0.5
	var lateral_delta := ball_x - center_x
	var target_offset := clampf(sign(lateral_delta) * maxf(absf(lateral_delta) - DEMO_CAMERA_LATERAL_DEADZONE, 0.0) * DEMO_CAMERA_LATERAL_FOLLOW,
		-DEMO_CAMERA_LATERAL_LIMIT, DEMO_CAMERA_LATERAL_LIMIT)
	camera_lateral_offset = lerpf(camera_lateral_offset, target_offset, 1.0 - exp(-3.0 * delta))
	camera.position = DEMO_CAMERA_BASE_POSITION + Vector3(camera_lateral_offset, 0.0, 0.0)
	camera.rotation = camera_fixed_rotation

func _create_match() -> void:
	players.clear()
	_views.clear()
	var carrier_entry := {"id": DEMO_PLAYER_ID, "home": true, "position": DEMO_START,
		"spawn": DEMO_START, "velocity": Vector3.ZERO, "facing": Vector3.RIGHT,
		"input_direction": Vector3.RIGHT, "goalkeeper": false, "technique": 78.0,
		"dribble_mode": DribblePhysics3D.Mode.JOG, "cutback_cooldown": 0.0}
	var keeper_entry := {"id": DEMO_KEEPER_ID, "home": false, "position": DEMO_KEEPER_START,
		"spawn": DEMO_KEEPER_START, "velocity": Vector3.ZERO, "facing": Vector3.LEFT,
		"input_direction": Vector3.LEFT, "goalkeeper": true, "technique": 72.0,
		"dribble_mode": DribblePhysics3D.Mode.JOG, "cutback_cooldown": 0.0}
	players.append(carrier_entry)
	players.append(keeper_entry)
	_add_demo_player_view(carrier_entry, "DemoCarrier", HOME_COLOR)
	_add_demo_player_view(keeper_entry, "DemoKeeper", KEEPERS_COLOR)
	_ball_view = BallView.new() as Ball3DView
	_ball_view.name = "DemoBall"
	add_child(_ball_view)
	_reset_kickoff(true)

func _add_demo_player_view(player: Dictionary, view_name: String, color: Color) -> void:
	var view := PlayerView.new() as Player3DView
	view.name = view_name
	view.set_team_color(color)
	add_child(view)
	_views[int(player.id)] = view

func _reset_kickoff(_home_kicks_off: bool, _update_flow := true) -> void:
	for index in players.size():
		var player := players[index]
		player.position = DEMO_START if int(player.id) == DEMO_PLAYER_ID else DEMO_KEEPER_START
		player.spawn = player.position
		player.velocity = Vector3.ZERO
		player.facing = Vector3.RIGHT if int(player.id) == DEMO_PLAYER_ID else Vector3.LEFT
		player.input_direction = player.facing
		players[index] = player
	var carrier_position := DEMO_START
	_set_ball_state(carrier_position + Vector3(0.62, 0.0, 0.0), Vector3.ZERO, true)
	if _ball_view != null:
		_ball_view.reset_roll_baseline()
	carrier_id = DEMO_PLAYER_ID
	controlled_id = DEMO_PLAYER_ID
	dribble_touch_timer = 0.0
	dribble_loss_timer = 0.0
	dribble_touch_count = 0
	_reset_dribble_turn_state()
	kickoff_timer = 0.0
	_clear_shot_charge()
	last_touch_home = true

func _create_hud() -> void:
	super._create_hud()
	_demo_label = _hud_label(11, HORIZONTAL_ALIGNMENT_LEFT)
	_demo_label.position = Vector2(12, 84)
	_demo_label.size = Vector2(536, 44)
	_demo_label.text = "DRIBBLE LAB: WASD MOVE   I SPRINT   J SHOOT   U TACKLE   R RESET"
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(_demo_label)

func _player_intent(player: Dictionary) -> Vector3:
	if int(player.id) == DEMO_KEEPER_ID:
		var keeper_position: Vector3 = player.position
		var target_z := clampf(ball_position.z, 5.2, Rules.PITCH_SIZE.z - 5.2)
		return Vector3(0.0, 0.0, target_z - keeper_position.z).normalized()
	return super._player_intent(player)

func _resolve_cpu_tackle(carrier: Dictionary) -> void:
	var keeper := _player_by_id(DEMO_KEEPER_ID)
	if keeper.is_empty() or not bool(carrier.home):
		return
	var distance := (keeper.position as Vector3).distance_to(Coordinate3D.ground(ball_position))
	if distance > KEEPER_PRESS_DISTANCE:
		return
	carrier_id = -1
	ball_velocity = Coordinate3D.ground(carrier.position - keeper.position).normalized() * 6.0
	dribble_touch_timer = 0.0
	dribble_loss_timer = 0.0
	_reset_dribble_turn_state()
	last_touch_home = true
	_event_label.text = "KEEPER CONTACT"
	_event_timer = 0.45
	_play_sfx("tackle")

func _update_hud() -> void:
	super._update_hud()
	if _demo_label == null:
		return
	var carrier := _player_by_id(DEMO_PLAYER_ID)
	var keeper := _player_by_id(DEMO_KEEPER_ID)
	var distance := (carrier.position as Vector3).distance_to(keeper.position as Vector3)
	var possession := "PLAYER" if carrier_id == DEMO_PLAYER_ID else ("KEEPER" if carrier_id == DEMO_KEEPER_ID else "LOOSE")
	_demo_label.text = "DRIBBLE LAB: WASD MOVE   I SPRINT   J SHOOT   U TACKLE   R RESET\nBALL %.2fm   KEEPER %.2fm   TOUCHES %d   POSSESSION %s" % [
		(carrier.position as Vector3).distance_to(Coordinate3D.ground(ball_position)), distance,
		dribble_touch_count, possession]

func _process(delta: float) -> void:
	super._process(delta)
	if Input.is_key_pressed(KEY_R):
		_reset_kickoff(true)
