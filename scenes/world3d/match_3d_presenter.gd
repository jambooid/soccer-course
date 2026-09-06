class_name Match3DPresenter
extends Node3D

## Presentation-only bridge. It receives copied match snapshots and never
## writes to gameplay nodes, so rendering cadence cannot affect a result.

const PlayerViewScene := preload("res://scenes/world3d/player_3d_view.gd")
const BallViewScene := preload("res://scenes/world3d/ball_3d_view.gd")

@export var simulation_scale := 1.0
@export var interpolation_speed := 16.0
@export var snapshot_source: NodePath

var _player_views: Dictionary = {}
var _previous_snapshot: Dictionary = {}
var _current_snapshot: Dictionary = {}
var _ball_view: Ball3DView

func _ready() -> void:
	_ball_view = BallViewScene.new()
	_ball_view.simulation_scale = simulation_scale
	_ball_view.name = "BallView"
	add_child(_ball_view)

func consume_snapshot(snapshot: Dictionary) -> void:
	_previous_snapshot = _current_snapshot.duplicate(true)
	_current_snapshot = snapshot.duplicate(true)
	_ensure_player_views()

func consume_replay_snapshot(snapshot) -> void:
	consume_snapshot(snapshot.to_dict())

func _process(delta: float) -> void:
	var source := get_node_or_null(snapshot_source)
	if source != null and source.has_method("build_presentation_snapshot"):
		consume_snapshot(source.build_presentation_snapshot())
	if _current_snapshot.is_empty() or _ball_view == null:
		return
	var weight := clampf(delta * interpolation_speed, 0.0, 1.0)
	_sync_players(weight)
	_sync_ball(weight)
	var camera := get_parent().get_node_or_null("Camera") as World3DCamera
	if camera != null:
		camera.set_target_world(_ball_view.global_position)

func _ensure_player_views() -> void:
	for player_data: Dictionary in _current_snapshot.get("players", []):
		var player_id := int(player_data.get("id", -1))
		if player_id < 0 or _player_views.has(player_id):
			continue
		var view := PlayerViewScene.new() as Player3DView
		view.simulation_scale = simulation_scale
		view.name = "Player_%d" % player_id
		view.set_team_color(Color(0.12, 0.28, 0.88) if bool(player_data.get("home", false)) else Color(0.86, 0.18, 0.12))
		_player_views[player_id] = view
		add_child(view)

func _sync_players(weight: float) -> void:
	var previous_by_id := _players_by_id(_previous_snapshot)
	for player_data: Dictionary in _current_snapshot.get("players", []):
		var player_id := int(player_data.get("id", -1))
		var view := _player_views.get(player_id) as Player3DView
		if view == null:
			continue
		var current_position := player_data.get("position", Vector3.ZERO) as Vector3
		var previous: Dictionary = previous_by_id.get(player_id, player_data)
		var previous_position := previous.get("position", current_position) as Vector3
		view.sync_world_position(previous_position.lerp(current_position, weight))

func _sync_ball(weight: float) -> void:
	var current_ball: Dictionary = _current_snapshot.get("ball", {})
	var previous_ball: Dictionary = _previous_snapshot.get("ball", current_ball)
	var current_position := current_ball.get("position", Vector3.ZERO) as Vector3
	var previous_position := previous_ball.get("position", current_position) as Vector3
	var current_velocity := current_ball.get("velocity", Vector3.ZERO) as Vector3
	_ball_view.sync_world_position(previous_position.lerp(current_position, weight), current_velocity)

func _players_by_id(snapshot: Dictionary) -> Dictionary:
	var by_id := {}
	for player_data: Dictionary in snapshot.get("players", []):
		by_id[int(player_data.get("id", -1))] = player_data
	return by_id
