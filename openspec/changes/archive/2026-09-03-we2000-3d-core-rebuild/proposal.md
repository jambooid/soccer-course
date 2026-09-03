## Why

The project has many isolated football systems, but the live match still behaves differently from the deterministic utilities and lacks the spatial contact rules that make WE2000 readable and physical. The next step is to establish a stable WE2000-style match core and a 3D presentation path without coupling gameplay outcomes to rendering or a general-purpose physics solver.

## What Changes

- Establish a fixed-tick, match-scoped simulation authority for gameplay-affecting time and randomness.
- Unify ball trajectory prediction and live execution behind one trajectory API.
- Resolve player occupancy, body contact, tackles, goalkeeper actions, and possession through one deterministic interaction pass per tick.
- Fix offside-line direction and action-context errors that currently create false calls and empty aerial actions.
- Add bounded kickoff progression and restart hooks for future throw-ins, corners, and goal kicks.
- Add a 3D presentation layer that maps simulation coordinates to XZ space and renders low-poly players, ball, goals, pitch, and camera without deciding match outcomes.
- Add replay-oriented and gameplay-feel regression checks for contact, kickoff, passing, and 3D synchronization.

## Capabilities

### New Capabilities

- `we2000-core-loop`: Deterministic fixed-tick match progression, player spatial occupancy, physical contests, unified interaction arbitration, and restart flow.
- `3d-presentation`: 3D render bridge for players, ball, pitch, goals, camera, animation, and PS1-style visual constraints.

### Modified Capabilities

- `deterministic-match-simulation`: Extend the existing contract from utility-only simulation to the live match path.
- `team-tactics-ai`: Require contact-aware reachability and stable movement scheduling in the live match.

## Impact

Affected areas include `scenes/game_manager`, `scenes/characters`, `scenes/ball`, `scenes/screens/world`, `utils`, `project.godot`, and new 3D scenes/resources under `scenes/world3d` and `assets/3d`. Existing 2D scenes remain usable during migration; no external runtime dependency is required.
