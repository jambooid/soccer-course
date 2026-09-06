class_name Player3DView
extends Node3D

const CharacterModelScene := preload("res://assets/player/Soccer Game Pack/Ch38_nonPBR.fbx")
const IdleScene := preload("res://assets/player/Soccer Game Pack/offensive idle.fbx")
const JogScene := preload("res://assets/player/Soccer Game Pack/jog forward.fbx")
const DribbleScene := preload("res://down3d/Soccer Game Pack/Dribble.fbx")
const TurnaroundScene := preload("res://assets/player/Soccer Game Pack/transition.fbx")
const PassScene := preload("res://assets/player/Soccer Game Pack/kick soccerball.fbx")
const ShotScene := preload("res://assets/player/Soccer Game Pack/soccer penalty kick.fbx")
const TackleScene := preload("res://assets/player/Soccer Game Pack/soccer tackle.fbx")
const KeeperIdleScene := preload("res://assets/player/Soccer Game Pack/goalkeeper idle.fbx")
const PressureScene := preload("res://assets/player/Soccer Game Pack/goalkeeper sidestep.fbx")
const KeeperCatchScene := preload("res://assets/player/Soccer Game Pack/goalkeeper catch.fbx")
const KeeperDiveScene := preload("res://assets/player/Soccer Game Pack/goalkeeper diving save.fbx")
const TURNAROUND_PLAYBACK_SPEED := 3.8

## Match3D gameplay coordinates are already in pitch/world units (85 x 36).
## Keep this at one because the simulation already uses world metres.
@export var simulation_scale := 1.0
@export var body_radius := 0.32
@export var body_height := 1.65

var model_root: Node3D
var animation_player: AnimationPlayer
var shadow: MeshInstance3D
var team_color := Color(0.12, 0.28, 0.88)
var selection_ring: MeshInstance3D
var carrier_marker: MeshInstance3D
var _motion_speed := 0.0
var _goalkeeper := false
var _dribbling := false
var _action_animation := StringName()

func _ready() -> void:
	_create_character_model()
	_create_pitch_markers()

func _create_character_model() -> void:
	model_root = CharacterModelScene.instantiate() as Node3D
	model_root.name = "CharacterModel"
	# The imported character is 1.66 m tall. A small reduction avoids visual
	# overlap while retaining the same pitch scale as the simulation.
	model_root.scale = Vector3.ONE * 0.92
	add_child(model_root)
	animation_player = model_root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if animation_player != null:
		_add_clip(IdleScene, &"idle", true)
		_add_clip(JogScene, &"jog", true)
		_add_clip(DribbleScene, &"dribble", true)
		_add_clip(TurnaroundScene, &"turnaround", false)
		_add_clip(PassScene, &"pass", false)
		_add_clip(ShotScene, &"shot", false)
		_add_clip(TackleScene, &"tackle", false)
		_add_clip(PressureScene, &"pressure", false)
		_add_clip(KeeperCatchScene, &"keeper_collect", false)
		_add_clip(KeeperDiveScene, &"keeper_dive", false)
		_add_clip(KeeperIdleScene, &"keeper_idle", true)
		animation_player.animation_finished.connect(_on_animation_finished)
		_play_locomotion(true)
	_apply_team_color()

func _add_clip(source_scene: PackedScene, library_name: StringName, loop: bool) -> void:
	var source_root := source_scene.instantiate() as Node
	var source_player := source_root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if source_player == null:
		source_root.free()
		return
	var source_clip := source_player.get_animation(&"mixamo_com")
	if source_clip == null:
		source_root.free()
		return
	var clip := source_clip.duplicate(true) as Animation
	clip.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_lock_horizontal_root_motion(clip)
	var library := AnimationLibrary.new()
	library.add_animation(&"clip", clip)
	animation_player.add_animation_library(library_name, library)
	source_root.free()

func _lock_horizontal_root_motion(clip: Animation) -> void:
	for track in clip.get_track_count():
		if clip.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var path := clip.track_get_path(track)
		if path.get_subname_count() != 1 or path.get_subname(0) != &"mixamorig5_Hips":
			continue
		if clip.track_get_key_count(track) == 0:
			continue
		for key in clip.track_get_key_count(track):
			var position := clip.track_get_key_value(track, key) as Vector3
			# Source FBX actions often bake forward movement into the Hips track.
			# Gameplay owns X/Z translation, so anchor every action at its first pose
			# and preserve only vertical body motion.
			position.x = 0.0
			position.z = 0.0
			clip.track_set_key_value(track, key, position)

func _create_pitch_markers() -> void:
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

func sync_world_position(position: Vector3) -> void:
	global_position = position * maxf(simulation_scale, 0.0001)

func set_team_color(color: Color) -> void:
	team_color = color
	_apply_team_color()

func set_facing(direction: Vector3) -> void:
	if direction.is_zero_approx():
		return
	rotation.y = atan2(direction.x, direction.z)

func set_motion(velocity: Vector3, goalkeeper: bool = false, dribbling: bool = false) -> void:
	_motion_speed = Vector2(velocity.x, velocity.z).length()
	_goalkeeper = goalkeeper
	_dribbling = dribbling
	if _action_animation.is_empty():
		_play_locomotion()

func set_selected(selected: bool) -> void:
	if selection_ring != null:
		selection_ring.visible = selected

func set_ball_carrier(active: bool) -> void:
	if carrier_marker != null:
		carrier_marker.visible = active

func play_action(kind: String) -> void:
	if animation_player == null:
		return
	var next_action := StringName()
	match kind:
		"turnaround":
			next_action = &"turnaround/clip"
		"pass":
			next_action = &"pass/clip"
		"shot":
			next_action = &"shot/clip"
		"tackle":
			next_action = &"tackle/clip"
		"pressure":
			next_action = &"pressure/clip"
		"keeper_collect":
			next_action = &"keeper_collect/clip"
		"keeper_dive":
			next_action = &"keeper_dive/clip"
		_:
			return
	if animation_player.has_animation(next_action):
		_action_animation = next_action
		# The source transition is longer than the gameplay plant. Compress it to
		# the same 0.2 s input-lock window so reverse movement resumes on its exit.
		animation_player.speed_scale = TURNAROUND_PLAYBACK_SPEED if kind == "turnaround" else 1.0
		animation_player.play(next_action, 0.04)

func is_playing_action(kind: String) -> bool:
	return _action_animation == StringName("%s/clip" % kind)

func _play_locomotion(immediate: bool = false) -> void:
	if animation_player == null:
		return
	var next_animation := &"keeper_idle/clip" if _goalkeeper and _motion_speed < 0.12 else &"idle/clip"
	var playback_speed := 1.0
	if _motion_speed >= 0.12:
		next_animation = &"dribble/clip" if _dribbling else &"jog/clip"
		# "strike foward jog" includes a kicking pose, so use the ordinary jog
		# clip for both movement speeds and make sprinting read faster instead.
		playback_speed = 1.34 if _motion_speed >= 6.8 else 1.0
	if animation_player.current_animation == next_animation and animation_player.is_playing():
		animation_player.speed_scale = playback_speed
		return
	animation_player.speed_scale = playback_speed
	animation_player.play(next_animation, 0.0 if immediate else 0.14)

func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != _action_animation:
		return
	_action_animation = StringName()
	_play_locomotion()

func _make_material(color: Color, transparent := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

func _apply_team_color() -> void:
	if model_root == null:
		return
	for mesh_path in [NodePath("Skeleton3D/Ch38_Shirt"), NodePath("Skeleton3D/Ch38_Shorts"), NodePath("Skeleton3D/Ch38_Socks")]:
		var mesh_instance := model_root.get_node_or_null(mesh_path) as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source_material := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if source_material == null:
				continue
			var tinted_material := source_material.duplicate() as BaseMaterial3D
			tinted_material.albedo_color = team_color
			mesh_instance.set_surface_override_material(surface, tinted_material)
