## Why

The current match loop allows rendering cadence, Area callbacks, deferred state nodes, and global random calls to independently change ball ownership and action outcomes. This produces inconsistent dribbling, passing, tackling, goalkeeper behavior, and AI, and makes headless failures impossible to reproduce or tune.

The project needs a deterministic gameplay foundation before further WE2000-style mechanics or content can be added safely.

## What Changes

- Add a fixed-tick match simulation boundary with seedable randomness, input replay, and inspectable tick snapshots.
- Add a single ball-interaction resolver for possession, interceptions, tackles, goalkeeper collection, and action contact windows.
- Replace mixed per-frame dribble correction with recorded touch impulses and consistent ball trajectories for passes, shots, and goalkeeper prediction.
- Add a team-tactics layer that assigns defensive roles, maintains shape, exposes an offside line, and makes CPU action selection reproducible.
- Add a version-pinned headless test entry point and deterministic scenario tests that fail with a non-zero exit code.
- Preserve the current 2D arcade presentation and existing menu/tournament flow while changing the gameplay internals.

## Capabilities

### New Capabilities

- `deterministic-match-simulation`: Fixed-step match state, event ordering, seeded randomness, replay, and ball/action interaction resolution.
- `team-tactics-ai`: Team-level defensive assignments, formation anchors, offside-aware support, and deterministic CPU action selection.
- `headless-match-validation`: Version-pinned, automation-friendly test runner and gameplay scenario regression coverage.

### Modified Capabilities

- None.

## Impact

- Affects the player, ball, player-state, ball-state, AI, ActorsContainer, GameManager, input, trajectory, interception, and test tool modules.
- Replaces direct ownership/state mutations performed by collision callbacks and individual state nodes with simulation-owned decisions.
- Requires Godot 4.4.x to be made explicit for local and CI headless execution.
