class_name Player3DView
extends Node3D

const Presentation3DScript := preload("res://utils/presentation_3d.gd")

@export var simulation_scale := 0.1
@export var body_radius := 0.32
@export var body_height := 1.65

var model: MeshInstance3D
var shadow: MeshInstance3D

func _ready() -> void:
	model = MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = body_radius
	body_mesh.bottom_radius = body_radius * 1.08
	body_mesh.height = body_height
	model.mesh = body_mesh
	model.position.y = body_height * 0.5
	model.material_override = _make_material(Color(0.82, 0.12, 0.08))
	add_child(model)

	shadow = MeshInstance3D.new()
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = body_radius * 1.15
	shadow_mesh.bottom_radius = body_radius * 1.15
	shadow_mesh.height = 0.01
	shadow.mesh = shadow_mesh
	shadow.position.y = 0.005
	shadow.material_override = _make_material(Color(0.02, 0.03, 0.02, 0.45), true)
	add_child(shadow)

func sync_from_simulation(position: Vector2, height: float = 0.0) -> void:
	global_position = Presentation3DScript.to_world(position, height, simulation_scale)

func set_team_color(color: Color) -> void:
	if model != null:
		model.material_override = _make_material(color)

func _make_material(color: Color, transparent := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
