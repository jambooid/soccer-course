## Context

The existing 3D match is a single playable prototype. `Match3DGame` owns the
simulation loop, view synchronization, camera follow, HUD, and sound, while
`Match3DPresenter` already demonstrates a snapshot-based rendering boundary.
The reference video requires additional phases and event presentation, but the
first implementation must preserve the current 11v11 controls and deterministic
60 Hz tests.

## Goals / Non-Goals

**Goals:**

- Establish one authoritative fixed-tick match timeline and event stream.
- Make presentation consumers read copied snapshots rather than mutable match
  fields.
- Deliver a complete testable goal-to-restart slice with camera, HUD, audio, and
  replay hooks.
- Keep the current low-poly player and pitch assets usable during migration.

**Non-Goals:**

- Rebuilding all player models, stadium art, or broadcast audio.
- Fouls, cards, substitutions, online multiplayer, tournaments, or penalties.
- Replacing the existing AI decision model in this change.
- Matching every original WE2000 menu and licensed asset.

## Decisions

### 1. Event bus plus copied snapshots

The simulation emits typed dictionary payloads (or lightweight RefCounted data
objects if needed by the implementation) and publishes a deep-copied snapshot
at fixed ticks. HUD, camera, audio, and replay subscribe to the same event and
never infer scorer, restart type, or clock transitions independently. This
builds on the existing `build_presentation_snapshot()` pattern.

An all-in-one scene callback was rejected because it duplicates side effects and
makes replay or headless testing order-dependent.

### 2. Explicit phase and restart state machines

Use explicit phase/restart enums with bounded timers. A goal enters
`GOAL_RESULT`, optionally `REPLAY`, then `KICKOFF`; boundaries resolve to a
restart payload before live play resumes. The simulation clock advances only in
live phases. This is preferable to scattered boolean flags, which currently
make a future halftime or set-piece implementation ambiguous.

### 3. Ring-buffer replay history

Keep a small fixed-size ring buffer of presentation snapshots (approximately
4 seconds before and 2 seconds after a key event at 60 Hz). Replay reads a
separate cursor over copied frames. The simulation continues to own the real
clock and is frozen during the result/replay window, so no rollback or physics
rewind is required.

### 4. Camera director above bounded follow

Retain the existing bounded broadcast follow math as the `BROADCAST` shot and
add a director that selects `GOAL_FOCUS`, `REPLAY`, and `SET_PIECE` with minimum
hold times and deterministic exit conditions. Director decisions consume events
and snapshots; they do not reposition simulation actors.

### 5. HUD as a single layout owner

Replace ad hoc labels in `Match3DGame` incrementally with one HUD owner that
receives a snapshot and current event. It owns the top score/clock band, bottom
player panels, radar, and event label, with a fixed safe-area layout at the
internal 560x360 viewport and integer scaling to the output window.

### 6. Compatibility-first migration

Keep existing input actions and public helper methods while adding new event and
snapshot fields. First route current gameplay through the new boundary, then
remove direct field reads after tests pass. This limits regression risk in the
already passing physics/runtime suite.

## Risks / Trade-offs

- [Risk] Migrating a large `Match3DGame` script can temporarily create two phase
  authorities. -> [Mitigation] Add phase/event tests first and keep one adapter
  method as the only writer during migration.
- [Risk] Deep-copying 22 players at 60 Hz can allocate excessively. ->
  [Mitigation] Start with dictionaries for correctness, measure allocations,
  then introduce reusable snapshot objects or a frame pool if profiling shows a
  real cost.
- [Risk] Replay camera cuts can expose missing animation frames. ->
  [Mitigation] Use the same interpolated views and a graceful no-history result
  shot; do not block match restart on replay assets.
- [Risk] Existing HUD coordinates are tuned to the prototype and may overlap
  after adding radar and player panels. -> [Mitigation] Validate at the fixed
  internal viewport and add a screenshot checklist for 16:9 output.
- [Risk] The reference video contains licensed names and art that cannot be
  shipped. -> [Mitigation] Use original teams/assets while reproducing layout,
  rhythm, and readability rather than protected content.

## Migration Plan

1. Add event, phase, restart, snapshot, and replay data contracts with unit
   tests; no visible behavior changes yet.
2. Route goal and kickoff handling through the phase machine and publish events.
3. Migrate presenter, HUD, audio, and camera to snapshot/event inputs.
4. Add set-piece classification, halftime, stoppage time, and result payload.
5. Run focused headless tests plus a manual 1280x720 playthrough of the complete
   vertical slice.

Rollback is limited to reverting the adapter wiring and leaving the existing
`Match3DGame` loop intact; the new data contracts can remain unused without
changing saved data or project settings.

## Open Questions

- Exact art direction for team flags and fictional team branding can be chosen
  after the slice proves the layout; it does not change the behavior contract.
- Final replay camera angles can be tuned from playtest footage after event
  timing is stable.
