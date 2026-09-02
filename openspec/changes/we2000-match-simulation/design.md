## Context

See `proposal.md` for the motivation and the three delta specifications for the required behavior. The current Godot project has state machines for players, ball, match flow, and screens, but gameplay transitions occur from per-render-frame nodes, physics callbacks, and direct mutations. Global `randf()` calls and deferred state attachment prevent reliable replay.

The project remains a 2D, 2.5D-height arcade game and must remain readable as a teaching codebase. Godot 4.4.x is the compatibility target. The current test scripts are useful diagnostics but are not a reliable process-level test interface.

## Goals / Non-Goals

**Goals:**

- Make match outcomes deterministic for a seed and recorded input sequence.
- Make ball ownership, contact, and action timing explicit and traceable.
- Give CPU players a shared tactical picture rather than independent nearest-ball steering.
- Establish fast headless tests before visual tuning starts.

**Non-Goals:**

- Recreate PS1 WE2000 source behavior or match every animation exactly.
- Replace Godot's renderer, menus, tournament progression, art pipeline, or audio systems.
- Add cards, substitutions, penalties, online multiplayer, or a full professional-football rules simulation in this change.
- Require deterministic visual particles, audio playback, or camera interpolation.

## Decisions

### 1. Introduce a fixed-tick simulation boundary

Gameplay advances at a fixed 60 Hz simulation tick. A match-owned state record contains the tick number, seed/RNG stream state, ball kinematics, player kinematics, action clocks, ownership, and tactical assignments. Presentation nodes consume the resulting state, while gameplay writes occur only in the fixed-tick path.

This is preferred over continuing `_process` gameplay with delta normalization because Godot physics callbacks, input timing, and state-node scheduling can still vary around it. A complete ECS rewrite is rejected: a match-owned coordinator can preserve the project's state-machine teaching pattern while centralizing sequencing.

### 2. Resolve interactions as intents, then commit once

Movement and active action windows create typed intents: `CONTROL`, `INTERCEPT`, `TACKLE`, `DEFLECT`, `COLLECT`, and `KICK`. A resolver receives all intents for a tick, rejects ineligible candidates, orders remaining candidates deterministically, and commits one ball interaction event. The event owns ball carrier changes and transitions.

This replaces direct `Area2D.body_entered` ownership changes. Areas remain broad-phase candidate collection and visual debugging aids, but do not authoritatively mutate gameplay. Replacing all collision detection with custom geometry is rejected because Godot areas still provide useful candidate discovery.

### 3. Use one trajectory and control-profile model

`BallTrajectory` represents horizontal position/velocity, height, vertical velocity, friction regime, and bounce rules. Pass creation solves against that same model; AI interception, goalkeeper positioning, and actual simulation consume identical predictions.

`ControlProfile` describes foot, chest, head, volley, tackle, and goalkeeper-hand height/range/action constraints. It removes per-ball-state pickup threshold divergence. Fully continuous 3D rigid-body simulation is rejected because it reduces arcade control and makes deterministic tuning harder.

### 4. Use event-based dribbling and action phases

Dribbling produces discrete, logged touch impulses at a technique- and movement-dependent cadence. Turning changes the player's intended movement, not the ball through direct per-frame position or velocity overrides. Kicks and tackles are modeled as startup, active, and recovery phases; only active phases emit interaction intents.

This supports a readable WE-like rhythm: a player can carry reliably, expose the ball while sprinting or turning, and lose it for understandable geometric reasons. Retaining magnetic per-frame correction is rejected because it conflicts with deterministic contests and masks bad trajectory values.

### 5. Split AI into tactical snapshot and player intent

At a fixed tactical cadence, `TeamTactics` derives possession phase, formation anchors, offside line, active presser, cover player, defensive line, and support slots from the match snapshot. Players then use the snapshot to emit movement and action intents. LOD may reduce refresh of distant formation interpolation but cannot downgrade a ball carrier, active presser, or keeper's core decision cadence.

This is preferred over adding more local steering weights because the observed failure is team coordination, not insufficient steering constants. Random style variation, if retained, draws only from the match RNG after viable options are scored.

### 6. Make tests scenario-first and process-authoritative

A single `SceneTree`-based headless runner will register pure logic and minimal match scenarios. Scenarios define an initial snapshot, seed, per-tick input/actions, bounded tick count, and assertions over events/snapshots. The runner returns non-zero on every failure and prints the replay diagnostic.

Existing long runtime scripts will remain diagnostic/nightly tools after being adapted to emit assertions. They are not used as the initial merge gate. A third-party testing framework is deferred until the bespoke runner proves inadequate; the project already uses lightweight GDScript tests and the required assertions are simulation-specific.

### 7. Migrate incrementally behind behavior-preserving boundaries

The existing `Player`, `Ball`, and state-machine APIs stay as adapters during migration. The simulation coordinator initially owns only deterministic scenario paths, then becomes the live match authority once old direct mutation paths are removed. Each subsystem switches only after its scenario coverage passes.

This reduces the risk of a wholesale rewrite that leaves the game temporarily unplayable. Dual-authority is permitted only during isolated migration steps and must be deleted before the corresponding milestone is complete.

## Risks / Trade-offs

- [A fixed simulation changes existing feel] → Capture baseline trajectories and adjust only through named tuning parameters with scenario tolerances.
- [Godot callbacks arrive between simulation ticks] → Treat callbacks as candidate data consumed on the next deterministic tick; never commit gameplay from callback code.
- [Migration temporarily duplicates paths] → Gate each adapter behind explicit ownership and delete the previous direct path after verification.
- [AI tactical calculation costs more than nearest-ball steering] → Recompute a compact team snapshot at a bounded cadence and reuse it across players.
- [Headless runs fail because of local `user://` permissions or binary drift] → Require `GODOT_BIN`, a writable user-data path, and an explicit engine-version preflight in the single runner command.
- [Generated `.import` metadata churn] → Do not invoke editor import scans as a gameplay test; keep generated metadata out of feature changes unless an asset is intentionally updated.

## Migration Plan

1. Add the version-pinned headless preflight and deterministic pure-logic runner without changing live gameplay.
2. Introduce simulation snapshots, seed handling, event logging, and tick hashing; mirror selected live state for comparison.
3. Move ball trajectories and interactions into the resolver; migrate dribbling, passes, shots, tackles, and goalkeeper collection scenario by scenario.
4. Add team tactics and switch AI movement/action output from direct state transitions to intents.
5. Route the live match through the coordinator, remove legacy direct ownership and global gameplay-random paths, and run the full scenario matrix.

Rollback during development is by retaining the pre-migration adapter behind a temporary feature boundary. After a subsystem has passed its scenario suite and the legacy path is deleted, rollback is a source-control revert of that isolated task group rather than a runtime option.

## Open Questions

- The exact release distribution for Godot 4.4.x on developer machines and CI can be decided during the validation bootstrap, provided it remains pinned and supports a writable user-data path.
- Match-rule fidelity beyond the current simplified foul model remains deferred; the resolver will expose outcomes needed to add fouls later without making fouls part of this change.
