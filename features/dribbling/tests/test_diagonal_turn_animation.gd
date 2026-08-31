extends SceneTree

## Resource-level regression test for the diagonal turning dribble animations.
## Run with: godot --headless --path . -s features/dribbling/tests/test_diagonal_turn_animation.gd

const TURN_TEXTURE := preload("res://assets/art/characters/player_diagonal_turn.png")
const TURN_UP := preload("res://scenes/characters/animations/player_turn_45.tres")
const TURN_DOWN := preload("res://scenes/characters/animations/player_turn_45_down.tres")

func _init() -> void:
	var failures := 0
	failures += _check(TURN_TEXTURE.get_width() == 128 and TURN_TEXTURE.get_height() == 144,
		"diagonal texture is a 4x2 frame sheet")
	failures += _check(_check_animation(TURN_UP, [0, 1, 2, 3]), "upper-right animation uses frames 0..3")
	failures += _check(_check_animation(TURN_DOWN, [4, 5, 6, 7]), "lower-right animation uses frames 4..7")

	var scene_text := FileAccess.get_file_as_string("res://scenes/characters/player.tscn")
	failures += _check(scene_text.contains('[node name="TurnSprite" type="Sprite2D" parent="."]')
		and scene_text.contains("hframes = 4") and scene_text.contains("vframes = 2"),
		"Player scene exposes TurnSprite as a 4x2 sheet")

	print("Diagonal turn animation tests: %d passed, %d failed" % [4 - failures, failures])
	quit(1 if failures > 0 else 0)

func _check_animation(animation: Animation, expected_frames: Array[int]) -> bool:
	if animation.get_track_count() != 1 or animation.track_get_key_count(0) != expected_frames.size():
		return false
	if animation.track_get_path(0) != NodePath("TurnSprite:frame"):
		return false
	for index in expected_frames.size():
		if animation.track_get_key_value(0, index) != expected_frames[index]:
			return false
	return true

func _check(condition: bool, label: String) -> int:
	if condition:
		print("[PASS] ", label)
		return 0
	print("[FAIL] ", label)
	return 1
