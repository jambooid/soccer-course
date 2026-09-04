# Feature modules

`match3d` is the active gameplay module. It owns the playable 11v11 match and
uses `Vector3(x, y, z)` world coordinates throughout: X is goal-to-goal, Y is
height, and Z is touchline-to-touchline.

Run its validation with:

```sh
godot --headless --path . -s features/match3d/tests/test_physics.gd
godot --headless --path . -s features/match3d/tests/test_runtime.gd
```
