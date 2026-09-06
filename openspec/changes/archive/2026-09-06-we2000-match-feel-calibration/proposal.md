## Why

The current vertical slice now has a deterministic broadcast loop, but its
moment-to-moment play still relies on loosely connected movement, kick, and
free-ball thresholds. WE2000-like control requires deliberate assistance and
contact timing so players can predict the result of an input, learn defensive
counterplay, and trust the same outcome in repeated situations.

## What Changes

- Add an input-action buffer and action contact windows for pass, shot, tackle,
  receive, and goalkeeper actions.
- Make a selected pass receiver reserve a reachable receiving lane, show a
  bounded assisted first touch, and allow an opponent to win only a clearly
  earlier interception.
- Calibrate short pass, through pass, long pass, shot, first touch, shielding,
  tackle, and goalkeeper outcomes against shared arrival-time and control-area
  rules.
- Add goalkeeper collect, parry, dive, recovery, and intentional coverage-gap
  behavior that creates learnable scoring opportunities.
- Record match-feel metrics and deterministic scenario replays for pass success,
  first-touch time, interception, tackle, save, and possession changes.
- Keep the current input layout, team formations, 3D asset set, and broadcast
  flow compatible.

## Capabilities

### New Capabilities

- `match-feel-calibration`: Defines observable assistance, action timing,
  goalkeeper contest behavior, and calibration telemetry for the playable match.

### Modified Capabilities

- `we2000-core-loop`: Extends directional passing and physical contests with
  buffered actions, assisted receiver commitment, and controllable first-touch
  outcomes.
- `deterministic-match-simulation`: Extends trajectory and single-interaction
  guarantees with deterministic arrival-time, receiver, and metric records.
- `team-tactics-ai`: Extends formation movement with receiver runs, interception
  races, and goalkeeper reachability decisions.

## Impact

- Affected gameplay areas: `Match3DGame`, `Match3DRules`, ball trajectory and
  dribble helpers, player/goalkeeper view actions, and match event payloads.
- Affected tests: focused physics/runtime suites, new seeded feel scenarios,
  and repeatable metric assertions.
- No external dependency or project-wide asset replacement is required.
- Existing direct action paths will become buffered at their defined contact
  windows; public input action names remain unchanged.
