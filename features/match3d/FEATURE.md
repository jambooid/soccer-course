# 3D Single Match

**Status:** [TESTING]  
**Start date:** 2026-09-03

## Goal

Make the default runtime a playable 11v11 low-poly 3D match with the fast,
readable priorities of WE2000: immediate movement, assisted passes, deliberately
tiered kick speeds, a broadcast camera, and simple deterministic match rules.

The first scope is one local match: blue human team against red CPU. Menus,
tournaments, fouls, offside, substitutions, advanced keeper animation, and
online play remain outside this module.

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

## Tests

Run the focused suite with:

```sh
godot --headless --path . -s features/match3d/tests/test_physics.gd
godot --headless --path . -s features/match3d/tests/test_runtime.gd
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
- [P2] This prototype uses simple formation steering and no goalkeeper-specific
  save animation; it is intended as the first playable match loop, not a full
  production simulation.
- [P2] The match duration is fixed at three minutes and no pause menu exists.
