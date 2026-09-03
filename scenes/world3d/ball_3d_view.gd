class_name Ball3DView
extends Node3D

const Presentation3DScript := preload("res://utils/presentation_3d.gd")
const LowPolyBallScene := preload("res://assets/3d/generated/ball.obj")

@export var simulation_scale := 0.1
@export var radius := 0.14

var model: MeshInstance3D
var shadow: MeshInstance3D
var model_root: Node3D

func _ready() -> void:
	model = MeshInstance3D.new()
	model.mesh = LowPolyBallScene
	model.scale = Vector3.ONE * 1.45
	model.material_override = _make_material(Color(0.96, 0.96, 0.88))
	add_child(model)

	shadow = MeshInstance3D.new()
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = radius * 1.2
	shadow_mesh.bottom_radius = radius * 1.2
	shadow_mesh.height = 0.01
	shadow.mesh = shadow_mesh
	shadow.material_override = _make_material(Color(0.02, 0.03, 0.02, 0.5), true)
	shadow.position.y = -radius + 0.006
	add_child(shadow)

func sync_from_simulation(position: Vector2, height: float = 0.0) -> void:
	global_position = Presentation3DScript.to_world(position, height, simulation_scale)

func _make_material(color: Color, transparent := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
