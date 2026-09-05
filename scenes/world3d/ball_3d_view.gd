class_name Ball3DView
extends Node3D

const LowPolyBallScene := preload("res://assets/3d/generated/ball.obj")

## Match3D gameplay coordinates are already in pitch/world units (85 x 36).
@export var simulation_scale := 1.0
@export var radius := 0.14

var model: MeshInstance3D
var shadow: MeshInstance3D
var _previous_world_position := Vector3.ZERO
var _has_previous_world_position := false

func _ready() -> void:
	model = MeshInstance3D.new()
	model.mesh = LowPolyBallScene
	model.material_override = _make_material(Color(0.96, 0.96, 0.88))
	add_child(model)

	shadow = MeshInstance3D.new()
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = radius * 1.2
	shadow_mesh.bottom_radius = radius * 1.2
	shadow_mesh.height = 0.01
	shadow.mesh = shadow_mesh
	shadow.material_override = _make_material(Color(0.02, 0.03, 0.02, 0.5), true)
	shadow.position.y = shadow_mesh.height * 0.5 + 0.001
	add_child(shadow)

func sync_world_position(position: Vector3, _velocity: Vector3 = Vector3.ZERO) -> void:
	var target_position := position * maxf(simulation_scale, 0.0001)
	if model != null and _has_previous_world_position:
		# A view may be synchronized fewer times than the simulation advances. Roll
		# by the distance this rendered transform actually traveled, not by a
		# velocity-sized angle once per render callback.
		var displacement := target_position - _previous_world_position
		var horizontal_displacement := Vector3(displacement.x, 0.0, displacement.z)
		var distance := horizontal_displacement.length()
		if distance > 0.0001:
			var travel := horizontal_displacement / distance
			model.rotate(Vector3(-travel.z, 0.0, travel.x), distance / maxf(radius, 0.001))
	global_position = target_position
	_previous_world_position = target_position
	_has_previous_world_position = true

func reset_roll_baseline() -> void:
	_has_previous_world_position = false

func _make_material(color: Color, transparent := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
