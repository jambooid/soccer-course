class_name Player3DView
extends Node3D

const Presentation3DScript := preload("res://utils/presentation_3d.gd")
const Coordinate3D := preload("res://utils/pitch_coordinate_3d.gd")
const LowPolyPlayerScene := preload("res://assets/3d/generated/player.obj")

## Match3D gameplay coordinates are already in pitch/world units (85 x 36).
## Keep this at one; legacy pixel scenes can still pass an explicit scale.
@export var simulation_scale := 1.0
@export var body_radius := 0.32
@export var body_height := 1.65

var model: MeshInstance3D
var shadow: MeshInstance3D
var model_root: Node3D
var animation_time := 0.0
var team_color := Color(0.12, 0.28, 0.88)
var selection_ring: MeshInstance3D
var carrier_marker: MeshInstance3D
var action_timer := 0.0
var action_sign := 1.0

func _ready() -> void:
	model = MeshInstance3D.new()
	model.mesh = LowPolyPlayerScene
	model.scale = Vector3.ONE * 1.22
	model.material_override = _make_material(team_color)
	add_child(model)
	_apply_team_color()

	shadow = MeshInstance3D.new()
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = body_radius * 1.15
	shadow_mesh.bottom_radius = body_radius * 1.15
	shadow_mesh.height = 0.01
	shadow.mesh = shadow_mesh
	shadow.position.y = 0.005
	shadow.material_override = _make_material(Color(0.02, 0.03, 0.02, 0.45), true)
	add_child(shadow)

	selection_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = body_radius * 1.35
	ring_mesh.outer_radius = body_radius * 1.58
	ring_mesh.rings = 8
	ring_mesh.ring_segments = 12
	selection_ring.mesh = ring_mesh
	selection_ring.position.y = 0.035
	selection_ring.material_override = _make_material(Color(1.0, 0.92, 0.18))
	selection_ring.visible = false
	add_child(selection_ring)

	carrier_marker = MeshInstance3D.new()
	var marker_mesh := TorusMesh.new()
	marker_mesh.inner_radius = body_radius * 1.7
	marker_mesh.outer_radius = body_radius * 1.82
	marker_mesh.rings = 6
	marker_mesh.ring_segments = 12
	carrier_marker.mesh = marker_mesh
	carrier_marker.position.y = 0.045
	carrier_marker.material_override = _make_material(Color(1.0, 0.72, 0.08))
	carrier_marker.visible = false
	add_child(carrier_marker)

func sync_from_simulation(position: Vector2, height: float = 0.0) -> void:
	sync_world_position(Coordinate3D.to_world(position, height))

func sync_world_position(position: Vector3) -> void:
	global_position = Presentation3DScript.to_world_3d(position, simulation_scale)

func set_team_color(color: Color) -> void:
	team_color = color
	_apply_team_color()

func set_facing(direction: Vector2) -> void:
	if direction.is_zero_approx():
		return
	rotation.y = atan2(direction.x, direction.y)

func set_selected(selected: bool) -> void:
	if selection_ring != null:
		selection_ring.visible = selected

func set_ball_carrier(active: bool) -> void:
	if carrier_marker != null:
		carrier_marker.visible = active

func play_action(kind: String) -> void:
	action_timer = 0.18 if kind != "goal" else 0.32
	action_sign = -1.0 if kind == "tackle" else 1.0

func _process(delta: float) -> void:
	animation_time += delta
	if model != null:
		model.position.y = sin(animation_time * 7.0) * 0.015
		if action_timer > 0.0:
			action_timer = maxf(action_timer - delta, 0.0)
			model.rotation.z = sin((0.18 - action_timer) * 34.0) * 0.12 * action_sign
		else:
			model.rotation.z = 0.0

func _make_material(color: Color, transparent := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

func _apply_team_color() -> void:
	if model != null:
		model.material_override = _make_material(team_color)
