class_name Pitch3D
extends Node3D

const LowPolyPitchScene := preload("res://assets/3d/generated/pitch.obj")
const Match3DRulesScript := preload("res://utils/match3d_rules.gd")

## Keep the visible goal mouth on the same contract as goal_scoring_team().
const GOAL_HALF_WIDTH := Match3DRulesScript.GOAL_HALF_WIDTH
const GOAL_WIDTH := GOAL_HALF_WIDTH * 2.0
const GOAL_DEPTH := 4.2

@export var simulation_scale := 0.1

func _ready() -> void:
	var pitch := MeshInstance3D.new()
	pitch.mesh = LowPolyPitchScene
	var pitch_material := _make_material(Color(0.16, 0.42, 0.12))
	pitch_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pitch.material_override = pitch_material
	add_child(pitch)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	light.light_energy = 1.0
	light.shadow_enabled = true
	add_child(light)
	_add_markings()
	_add_goals()
	_add_stands()
	_add_environment()

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material

func _add_markings() -> void:
	var white := Color(0.93, 0.96, 0.85)
	var line := 0.14
	var width := PitchConstants.WIDTH * simulation_scale
	var height := PitchConstants.HEIGHT * simulation_scale
	_add_box(Vector3(width, 0.018, line), Vector3(width * 0.5, 0.014, line * 0.5), white)
	_add_box(Vector3(width, 0.018, line), Vector3(width * 0.5, 0.014, height - line * 0.5), white)
	_add_box(Vector3(line, 0.018, height), Vector3(line * 0.5, 0.014, height * 0.5), white)
	_add_box(Vector3(line, 0.018, height), Vector3(width - line * 0.5, 0.014, height * 0.5), white)
	_add_box(Vector3(line, 0.018, height), Vector3(width * 0.5, 0.014, height * 0.5), white)
	var circle := MeshInstance3D.new()
	var circle_mesh := TorusMesh.new()
	circle_mesh.inner_radius = 1.45
	circle_mesh.outer_radius = 1.49
	circle_mesh.rings = 4
	circle_mesh.ring_segments = 24
	circle.mesh = circle_mesh
	circle.position = Vector3(width * 0.5, 0.022, height * 0.5)
	circle.material_override = _make_material(white)
	add_child(circle)
	_add_box(Vector3(3.1, 0.018, line), Vector3(1.55, 0.014, height * 0.5 - 4.7), white)
	_add_box(Vector3(3.1, 0.018, line), Vector3(1.55, 0.014, height * 0.5 + 4.7), white)
	_add_box(Vector3(line, 0.018, 9.45), Vector3(3.1, 0.014, height * 0.5), white)
	_add_box(Vector3(3.1, 0.018, line), Vector3(width - 1.55, 0.014, height * 0.5 - 4.7), white)
	_add_box(Vector3(3.1, 0.018, line), Vector3(width - 1.55, 0.014, height * 0.5 + 4.7), white)
	_add_box(Vector3(line, 0.018, 9.45), Vector3(width - 3.1, 0.014, height * 0.5), white)

func _add_goals() -> void:
	var width := PitchConstants.WIDTH * simulation_scale
	var center_z := PitchConstants.HEIGHT * simulation_scale * 0.5
	for goal_x in [0.0, width]:
		# Goal depth extends away from the playable pitch: left goal toward -X,
		# right goal toward +X. The front frame remains on the scoring line.
		var direction := -1.0 if is_zero_approx(goal_x) else 1.0
		var goal_color := Color(0.9, 0.92, 0.86)
		# The scoring plane is x=0/x=width. Put the front frame on that same
		# plane; the rear frame and net extend outside the pitch from there.
		_add_goal_frame(goal_x, center_z, goal_color)
		var frame_x: float = goal_x + direction * GOAL_DEPTH
		# Match3DRules uses metres; the pitch mesh is already 85x36 world units
		# after converting the legacy 850x360 coordinates with simulation_scale.
		var goal_half_width := GOAL_HALF_WIDTH
		var goal_width := GOAL_WIDTH
		# The visible rear frame spans the complete scoring mouth, not a narrow placeholder.
		_add_goal_frame(frame_x, center_z, goal_color)
		_add_box(Vector3(GOAL_DEPTH, 0.06, goal_width),
			Vector3(goal_x + direction * GOAL_DEPTH * 0.5, 0.04, center_z),
			Color(0.76, 0.82, 0.8, 0.48), true)
		_add_box(Vector3(0.06, 1.9, 0.06),
			Vector3(goal_x + direction * GOAL_DEPTH * 0.64, 0.95, center_z - goal_half_width),
			Color(0.7, 0.76, 0.74, 0.38), true)
		_add_box(Vector3(0.06, 1.9, 0.06),
			Vector3(goal_x + direction * GOAL_DEPTH * 0.64, 0.95, center_z + goal_half_width),
			Color(0.7, 0.76, 0.74, 0.38), true)

func _add_goal_frame(frame_x: float, center_z: float, goal_color: Color) -> void:
	var goal_half_width := GOAL_HALF_WIDTH
	var goal_width := GOAL_WIDTH
	_add_box(Vector3(0.18, 3.1, 0.18), Vector3(frame_x, 1.55, center_z - goal_half_width), goal_color)
	_add_box(Vector3(0.18, 3.1, 0.18), Vector3(frame_x, 1.55, center_z + goal_half_width), goal_color)
	_add_box(Vector3(0.18, 0.18, goal_width), Vector3(frame_x, 3.1, center_z), goal_color)

func _add_stands() -> void:
	var width := PitchConstants.WIDTH * simulation_scale
	var height := PitchConstants.HEIGHT * simulation_scale
	_add_box(Vector3(width + 5.0, 2.1, 2.8), Vector3(width * 0.5, 0.8, -2.0), Color(0.12, 0.18, 0.26))
	_add_box(Vector3(width + 5.0, 2.1, 2.8), Vector3(width * 0.5, 0.8, height + 2.0), Color(0.16, 0.12, 0.2))

func _add_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.17, 0.28, 0.42)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.72, 0.84)
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)

func _add_box(size: Vector3, position: Vector3, color: Color, transparent := false) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := _make_material(color)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	instance.material_override = material
	add_child(instance)
