class_name World3DCamera
extends Camera3D

const Coordinate3D := preload("res://utils/pitch_coordinate_3d.gd")

@export var pitch_size := Coordinate3D.PITCH_SIZE
@export var follow_height := 30.0
@export var follow_distance := 34.0
@export var follow_speed := 6.0
@export var horizontal_follow := 0.22
@export var horizontal_limit := 10.0
@export var horizontal_deadzone := 2.5

var target := Vector3.ZERO
var _fixed_position := Vector3.ZERO
var _fixed_focus := Vector3.ZERO
var _lateral_offset := 0.0
var _fixed_rotation := Vector3.ZERO

func _ready() -> void:
	current = true
	_fixed_position = Vector3(pitch_size.x * 0.5, follow_height, pitch_size.z + follow_distance)
	_fixed_focus = Vector3(pitch_size.x * 0.5, 0.0, pitch_size.z * 0.5)
	position = _fixed_position
	target = _fixed_focus
	look_at(_fixed_focus)
	_fixed_rotation = rotation

func set_target_world(world_position: Vector3) -> void:
	target = Vector3(
		clampf(world_position.x, 0.0, pitch_size.x),
		0.0,
		clampf(world_position.z, 0.0, pitch_size.z))

func _process(_delta: float) -> void:
	# In this shot, screen-left/right maps to world X. Keep rotation fixed and
	# make only a small lateral translation toward the ball.
	var lateral_delta := target.x - _fixed_focus.x
	var target_offset := clampf(sign(lateral_delta) * maxf(absf(lateral_delta) - horizontal_deadzone, 0.0) * horizontal_follow,
		-horizontal_limit, horizontal_limit)
	_lateral_offset = lerpf(_lateral_offset, target_offset, 1.0 - exp(-follow_speed * _delta))
	position = _fixed_position + Vector3(_lateral_offset, 0.0, 0.0)
	rotation = _fixed_rotation
