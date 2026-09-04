class_name Ball3DView
extends Node3D

const LowPolyBallScene := preload("res://assets/3d/generated/ball.obj")

## Match3D gameplay coordinates are already in pitch/world units (85 x 36).
@export var simulation_scale := 1.0
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

func sync_world_position(position: Vector3, velocity: Vector3 = Vector3.ZERO) -> void:
	global_position = position * maxf(simulation_scale, 0.0001)
	if model != null and velocity.length_squared() > 0.0001:
		# Roll around the ground-plane perpendicular to travel direction.
		var distance := velocity.length() * simulation_scale
		var travel := Vector3(velocity.x, 0.0, velocity.z).normalized()
		if travel.is_zero_approx():
			return
		model.rotate(Vector3(-travel.z, 0.0, travel.x), distance / maxf(radius, 0.001))

func _make_material(color: Color, transparent := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
