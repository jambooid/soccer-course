extends Node

## Shared dimensions for the world-space match. Values are metres and use the
## Godot 3D convention: X is pitch length and Z is pitch width.

const WORLD_SCALE := 0.1
const WORLD_PITCH_LENGTH := 85.0
const WORLD_PITCH_WIDTH := 36.0
const WORLD_PITCH_SIZE := Vector3(WORLD_PITCH_LENGTH, 0.0, WORLD_PITCH_WIDTH)
