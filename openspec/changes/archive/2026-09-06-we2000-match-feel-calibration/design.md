## Context

See `proposal.md` for motivation. The runtime currently uses deterministic
fixed ticks, an explicit free-ball capture path, pass target assistance, and a
small set of player animations. It does not yet distinguish input acceptance
from action contact, calculate a shared receiver/interceptor race, or expose
scenario metrics for tuning.

## Goals / Non-Goals

**Goals:**

- Make intentional actions feel forgiving without making every action succeed.
- Give player, receiver, defender, and goalkeeper one shared arrival-time and
  contact-window vocabulary.
- Make calibration changes measurable and replayable before they are judged by
  subjective playtests.

**Non-Goals:**

- Full animation-event authoring, motion matching, or a rigid-body simulation.
- New player models, stadium presentation, formation menus, offside rules, or
  competitive online synchronization.
- Perfect real-football statistical simulation.

## Decisions

### 1. One action-intent queue per controlled actor

Store action type, sampled direction, source tick, and expiry tick when input is
accepted. The simulation consumes an intent only at the action's compatible
contact window. A single-slot queue is selected over arbitrary action chaining:
it gives a generous WE-style buffer while preserving predictable priority and
avoiding accidental multi-command macros.

### 2. Shared arrival race instead of free-ball nearest-only capture

Represent a pass with receiver id, predicted receiving area, expiry, and
estimated arrival. Each eligible player is scored with a deterministic arrival
estimate based on ground distance, movement speed, action lock, and legal
contact volume. The receiver gets a small assist margin; an opponent that beats
it by the explicit interception margin wins. This replaces the current
nearest-player-at-one-frame result, which can look random.

Pure target teleportation was rejected because it removes defensive counterplay;
fully physical contact was rejected because it would make control cadence and
results unstable.

### 3. First touch as an explicit short state

A winning receiver enters a short first-touch state that consumes the incoming
velocity into a bounded settle position before it can carry or kick. The state
creates a visible action window and gives pressure a predictable contest point.
It uses the existing ball state and player-view action system rather than a new
physics engine.

### 4. Goalkeeper outcome table with coverage gaps

Evaluate goalkeeper actions from arrival direction, height, lateral reach,
current recovery, and deterministic skill parameters. Coverage gaps are authored
parameters, not random failures. This deliberately creates learnable shooting
patterns while protecting against impossible late animation starts.

### 5. Calibration scenarios and metric records

Add a small scenario runner that constructs controlled player/ball snapshots and
records `ActionMetric` dictionaries. Gate tuning with arrival error, first-touch
duration, interception margin, and save outcome assertions. Human recordings
remain the final qualitative judgment, but no parameter changes land without
fixed-tick evidence.

## Risks / Trade-offs

- [Risk] Assisted reception becomes magnetic or removes interceptions. ->
  [Mitigation] Cap receiver assist by arrival margin and retain pressure/first-
  touch contest scenarios.
- [Risk] Input buffering makes controls feel delayed. -> [Mitigation] Consume at
  the earliest compatible window and publish buffered/expired diagnostics.
- [Risk] Goalkeeper coverage gaps become exploitable in every situation. ->
  [Mitigation] Parameterize gaps by shot height, lateral angle, recovery, and
  goalkeeper attributes; test both save and exposure cases.
- [Risk] Calibration records add allocations at 60 Hz. -> [Mitigation] Record
  only scenario/test mode or significant interaction events, not every movement
  tick.

## Migration Plan

1. Add pure intent, arrival-race, first-touch, goalkeeper, and metric helpers
   with deterministic tests.
2. Route current direct pass/receive flow through the race while retaining the
   existing public input actions and current fallback capture behavior.
3. Add buffered contact consumption for pass, shot, and tackle, then player
   views expose matching action windows.
4. Add goalkeeper outcome states and update team roles for receivers/interceptors.
5. Run fixed scenarios, existing regression tests, and a recorded human match;
   retain prior parameter presets for rollback.

## Open Questions

- Exact visual feedback for an input that expires can be chosen after the
  interaction metrics establish the desired buffer duration.
- Final goalkeeper gap values require recorded human playtest evidence but do
  not change the outcome-table approach.
