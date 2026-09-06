## Why

The current 3D prototype is playable, but its match rules, HUD, camera, and
audio are still coupled inside one scene and do not yet reproduce the complete
WE2000 broadcast loop visible in the reference video. A narrow vertical slice
will establish the authoritative match timeline and the presentation events
needed to validate the upgraded game before investing in full content.

## What Changes

- Add a deterministic match-flow contract covering kickoff, live play, goals,
  restarts, halftime, stoppage time, and full time.
- Add typed match events and immutable presentation snapshots for HUD, audio,
  camera, and replay consumers.
- Add a broadcast camera director with bounded follow, goal focus, set-piece,
  and replay states.
- Add the minimum WE2000-style match HUD: team identity, score, half, clock,
  selected player, radar, and event labels.
- Record a short rolling history around goals and play it back without mutating
  the authoritative match simulation.
- Add focused deterministic tests for the vertical-slice flow and snapshot
  isolation.
- Keep the current low-poly assets, input mappings, and simplified AI as the
  baseline for this slice; advanced fouls, substitutions, online play, and
  final stadium art remain outside scope.

## Capabilities

### New Capabilities

- `match-broadcast-loop`: Defines the observable match timeline, event stream,
  presentation snapshots, camera states, replay behavior, and minimum HUD data.

### Modified Capabilities

- `we2000-core-loop`: Extends the core loop from kickoff/possession behavior to
  deterministic restarts, half transitions, stoppage time, and result data.
- `3d-presentation`: Extends the presentation contract with event-driven camera
  states, replay isolation, and broadcast readability requirements.

## Impact

- Affected runtime areas: `scenes/world3d/match3d_game.gd`,
  `scenes/world3d/match_3d_presenter.gd`, the 3D camera and HUD creation code,
  and new simulation/presentation event data classes.
- Affected tests: `features/match3d/tests/test_physics.gd`,
  `features/match3d/tests/test_runtime.gd`, plus new match-flow tests.
- No new third-party dependency is required. Existing Godot 4.x scene,
  animation, audio, and low-poly assets remain compatible.
- The change introduces a snapshot/event boundary. Consumers that currently
  read mutable fields directly must migrate to copied snapshots.
