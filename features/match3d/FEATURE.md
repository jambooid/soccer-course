# 3D Single Match

**Status:** [TESTING]  
**Start date:** 2026-09-03

## Goal

Make the default runtime a playable 11v11 low-poly 3D match with the fast,
readable priorities of WE2000: immediate movement, assisted passes, deliberately
tiered kick speeds, a broadcast camera, and simple deterministic match rules.

The current vertical slice is one local match: blue human team against red CPU.
It now includes a deterministic first-half/halftime/second-half/stoppage/full-
time timeline, goal-to-kickoff flow, boundary restart classification, broadcast
HUD, camera direction, and snapshot-based replay. Menus, tournaments, fouls,
offside, substitutions, advanced keeper animation, and online play remain
outside this module.

## WE2000 Reference

- Input changes the controlled player's direction immediately, while motion
  accelerates toward the requested speed.
- Passing chooses a teammate from the intended directional cone rather than
  requiring frame-perfect aim.
- Ball interactions use explicit possession, kicked, and goal states rather
  than rigid-body simulation.
- Nearby players press the ball; distant players return to formation anchors.

## Success Criteria

- [x] Main scene opens directly into a 3D 11v11 match.
- [x] The player can move, sprint, pass, long pass, shoot, and tackle.
- [x] CPU can carry, pass, shoot, contest free balls, and restart after goals.
- [x] CPU defenders can win a close active tackle against the human carrier.
- [x] Pitch, goals, team colours, controlled-player indicator, score, clock,
  and broadcast framing make the match readable.
- [x] Pass, shot, tackle, and goal actions provide short audio/visual feedback.
- [x] Focused deterministic rule tests cover bounds, target selection, ball
  speed tiers, goals, free-ball choice, and body separation.
- [x] Runtime input smoke test confirms movement and pass release through the
  actual match controller.
- [x] Kickoff actions respond immediately during the countdown.
- [x] Match phases, goal records, restart payloads, and presentation snapshots
  have an explicit deterministic contract.
- [x] Goals pause live simulation, record bounded historical snapshots, and
  return through a kickoff-ready tableau without mutating the score in replay.
- [x] The HUD shows score, half, clock, selected player, radar, and dead-ball
  labels within the 560x360 internal safe area.
- [x] Camera direction exposes broadcast, goal focus, replay, and set-piece
  states while retaining the bounded broadcast follow shot.
- [ ] Manual input and feel validation is pending a human play session.

## Mechanism

`Match3DRules` is a pure coordinate-space rules layer. `Match3DGame` owns the
mutable match state and only sends positions to the existing 3D view nodes.
The ball is attached to its carrier or follows a decelerating analytic kick;
goals and possession are resolved by explicit thresholds.

| Parameter | Value | Intended feel |
| --- | ---: | --- |
| Player top speed | 8.8 m/s | Quick, readable WE-era response |
| Sprint top speed | 11.0 m/s | Clear breakaway reward |
| Short / long / shot | 27 / 35 / 48 m/s | Distinct decisions at a glance |
| Control radius | 1.18 m | Forgiving first touch without magnetic capture |

## Match-Feel Calibration Baseline

All gameplay state advances at 60 Hz. Rendering interpolates those snapshots,
so 30, 60, and 120 Hz presentation must not change possession or metrics.

| Parameter | Value | Intent |
| --- | ---: | --- |
| Action buffer | 12 ticks (200 ms) | A pass, shot, tackle, or receive pressed before contact resolves at its first legal window. |
| Directed-receive reservation | 2.4 s | The selected teammate runs to the predicted receiving area before normal formation steering resumes. |
| Receiver assist / interception margin | 2 / 2 ticks | Assistance wins close arrivals, but a defender must arrive clearly earlier to intercept. |
| First-touch duration | 3-18 ticks | Incoming speed, technique, and pressure visibly separate trap, settle, and contested loose outcomes. |
| Ground-pass control speed | <= 14.0 m/s | A receiver can only claim a directed pass after it becomes controllable. |
| Goalkeeper save zone / recovery | 3.2 m / 18 ticks | Saves are committed only when the ball is reachable and the keeper is not recovering. |
| Goalkeeper collect / dive / gap radius | 1.35 / 3.25 / 3.55 m | Low close shots collect, wider reachable shots parry or dive, and authored gaps stay scoreable. |

The seeded scenario suite measures short pass, through pass, long pass, first
touch, interception, shielding, tackle, low save, and coverage-gap shot. The
runtime suite also compares buffered pass reception and goalkeeper collection
at 30, 60, and 120 Hz.

## Tests

Run the focused suite with:

```sh
godot --headless --path . -s features/match3d/tests/test_physics.gd
godot --headless --path . -s features/match3d/tests/test_runtime.gd
godot --headless --path . -s features/match3d/tests/test_feel_scenarios.gd
godot --headless --path . -s features/match3d/tests/test_match_flow.gd
godot --headless --path . -s features/match3d/tests/test_broadcast_presentation.gd
```

Run the manual scene with:

```sh
godot --path . features/match3d/tests/test_scene.tscn
```

The focused suite and the project's full regression runner have been executed
with Godot 4.4.1. See `validation/test-results.txt` for the recorded output;
the remaining checks are subjective input feel and sustained performance.

## Known Issues

- [P1] Automated scene load and a one-frame render pass; subjective input feel
  and sustained performance still need a human play session.
- [P2] Goalkeeper collection and dive now have deterministic presentation
  actions, but their visual timing still requires real-window play validation.
- [P2] The match timeline uses fixed vertical-slice timings (90 second halves,
  8 seconds of stoppage); settings and pause menus are not yet implemented.
- [P2] Replay uses prior-frame history only. It provides a safe fallback when
  insufficient history exists but does not yet include authored alternate cuts.
