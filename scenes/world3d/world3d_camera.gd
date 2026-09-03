class_name World3DCamera
extends Camera3D

@export var pitch_size := Vector2(85.0, 36.0)
@export var follow_height := 30.0
@export var follow_distance := 34.0
@export var follow_speed := 6.0

var target := Vector3.ZERO

func _ready() -> void:
	current = true
	position = Vector3(pitch_size.x * 0.5, follow_height, pitch_size.y + follow_distance)
	target = Vector3(pitch_size.x * 0.5, 0.0, pitch_size.y * 0.5)
	look_at(target)

func set_target_world(world_position: Vector3) -> void:
	target = Vector3(
		clampf(world_position.x, 0.0, pitch_size.x),
		0.0,
		clampf(world_position.z, 0.0, pitch_size.y))

func _process(delta: float) -> void:
	var desired := Vector3(
		clampf(target.x, 0.0, pitch_size.x),
		follow_height,
		clampf(target.z + follow_distance, follow_distance, pitch_size.y + follow_distance))
	position = position.lerp(desired, 1.0 - exp(-follow_speed * delta))
	look_at(target)
