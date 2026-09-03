class_name Pitch3D
extends Node3D

const LowPolyPitchScene := preload("res://assets/3d/generated/pitch.obj")

@export var simulation_scale := 0.1

func _ready() -> void:
	var generated_pitch := LowPolyPitchScene.instantiate() as Node3D
	if generated_pitch != null:
		add_child(generated_pitch)
	else:
		var pitch := MeshInstance3D.new()
		var pitch_mesh := BoxMesh.new()
		pitch_mesh.size = Vector3(PitchConstants.WIDTH * simulation_scale, 0.08,
			PitchConstants.HEIGHT * simulation_scale)
		pitch.mesh = pitch_mesh
		pitch.position = Vector3(PitchConstants.CENTER_X * simulation_scale, -0.04,
			PitchConstants.CENTER_Y * simulation_scale)
		pitch.material_override = _make_material(Color(0.16, 0.42, 0.12))
		add_child(pitch)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	light.light_energy = 1.0
	add_child(light)

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material
