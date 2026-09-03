# Validation Notes

## 2026-09-03

- `tools/headless_runner.gd` completed with 136 passing checks and no failures.
- Godot editor resource loading completed for the 2D match, generated OBJ assets,
  `world3d_preview.tscn`, and `world3d_match.tscn`.
- 3D checklist: the pitch loads, player and ball views use XZ ground mapping with
  Y ball height, ground shadows exist, the camera clamps to pitch bounds, and
  `Match3DPresenter` accepts copied match snapshots without gameplay writes.
- Strict OpenSpec validation passed for `we2000-3d-core-rebuild`.

## Remaining Tuning Gaps

- The 3D scene is a presentation bridge; selecting it as the primary match view
  and tuning its camera framing against human play sessions is still a product
  decision, not a simulation dependency.
- Generated player bodies currently share one low-poly silhouette. Jersey
  palette, animation poses, goalkeeper shape, goals, crowd, and stadium art
  remain deliberately outside this core-loop change.
- Godot reports an existing invalid UID warning for
  `assets/art/characters/soccer-player.png`; it falls back to the text path and
  does not block the scene load, but it should be regenerated during asset
  cleanup.
