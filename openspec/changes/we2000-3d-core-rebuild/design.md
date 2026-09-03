## Context

The current live game uses Node/physics callbacks, wall-clock timers, and global random values while deterministic helpers exist separately. Player and ball visuals are 2D, but the desired target needs PS1-style 3D volume and contact. See `proposal.md` for motivation and scope.

## Goals / Non-Goals

**Goals:**

- Make one fixed-tick simulation the authority for match outcomes.
- Represent player volume with deterministic ground-plane footprints, not 3D rigid-body resolution.
- Make body contests readable: normal contact, shielding, and active tackle windows have distinct outcomes.
- Keep simulation coordinates independent from presentation coordinates.
- Support a low-poly, low-resolution, nearest-filtered 3D look with a broadcast-style camera.

**Non-Goals:**

- Photorealistic models, motion capture, or a full stadium asset pipeline.
- Replacing gameplay rules with Godot `CharacterBody3D` or rigid-body physics.
- Implementing every restart type and tournament feature in this first pass.

## Decisions

### Fixed simulation with render interpolation

The live match advances at 60 simulation ticks per second. Inputs are sampled into tick frames; wall-clock time is used only by the presentation layer. Rendering interpolates between the last two snapshots. This preserves replayability and prevents frame cadence from changing outcomes. A fully frame-driven approach was rejected because it already causes the current AI and action timing drift.

### Ground-plane footprint for 3D volume

Each player has a deterministic circle/capsule footprint on the simulation plane. The 3D mesh, skeleton, and shadow are visual children. Pair separation runs in stable player-id order with a small allowed visual tolerance. A general 3D physics solver was rejected because it introduces solver-order and cadence-dependent behavior.

### Single interaction arbitration

Players submit interaction intents during a tick. A resolver orders active tackle, goalkeeper, interception, shielding, and passive control intents, then commits at most one ball outcome. Existing area callbacks become detection inputs only.

### Shared trajectory model

Ground movement, aerial height, landing time, and prediction use `BallTrajectory`. Live ball states call the same functions used by AI and goalkeeper decisions. Fixed lead multipliers and duplicate friction formulas are removed from decision paths.

### Presentation bridge

`Player3DView` and `Ball3DView` consume snapshots and map `Vector2(x, y)` to `Vector3(x, height, y)`. Animation controls pose only; simulation controls transform. A simple `Pitch3D` scene is introduced before final art assets so the bridge can be tested with primitives.

## Risks / Trade-offs

- [Risk] Migrating live states incrementally can create two authorities. -> Keep one adapter boundary and add assertions when a visual node attempts to mutate simulation state.
- [Risk] Strict separation can make crowded areas feel sticky. -> Use small penetration tolerance, bounded separation iterations, and explicit shielding/strength rules.
- [Risk] 3D assets may arrive later than code. -> Validate the renderer with primitive meshes and placeholder animations first.
- [Risk] Existing tests encode old formulas. -> Preserve pure utility tests where valid and add live-path regression tests before changing constants.

## Migration Plan

1. Correct live rule bugs and add footprint/contact primitives while the current 2D view remains active.
2. Route live timing, randomness, and ball decisions through the simulation adapter.
3. Add the 3D presentation scene and snapshot interpolation using primitive meshes.
4. Replace primitives with low-poly assets and tune camera/materials without changing simulation contracts.
5. Keep the 2D scene as a debug view until 3D parity checks pass.
