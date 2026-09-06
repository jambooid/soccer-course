## 1. Contracts and test harness

- [x] 1.1 Add phase, restart, and match-event data contracts with stable event
  names and serializable payloads.
- [x] 1.2 Add immutable/deep-copy presentation snapshot coverage for players,
  ball, score, clock, phase, selected player, and radar data.
- [x] 1.3 Add a fixed-tick match-flow test fixture that can drive kickoff,
  goal, restart, halftime, stoppage, and full-time scenarios without rendering.

## 2. Authoritative match flow

- [x] 2.1 Move kickoff, goal result, and restart timing behind one explicit phase
  state machine while preserving current controls and deterministic tick order.
- [x] 2.2 Implement goal deduplication, scorer/assist/minute records, and
  restart ownership/location payloads.
- [x] 2.3 Classify throw-in, corner, goal-kick, and kickoff restarts and resume
  live play within bounded timers.
- [x] 2.4 Implement halftime side swap, second-half kickoff, configurable
  stoppage time, and one-shot full-time result emission.

## 3. Presentation boundary

- [x] 3.1 Route `Match3DPresenter` and direct 3D views through copied snapshots;
  ensure replay frames cannot write simulation state.
- [x] 3.2 Add a ring-buffer replay recorder and fallback behavior for short
  histories.
- [x] 3.3 Add a camera director for broadcast, goal focus, replay, and set-piece
  shots with bounded movement and minimum shot hold times.
- [x] 3.4 Extract a match HUD owner with score/clock/half, team identity,
  selected-player panel, radar, and non-overlapping event labels.
- [x] 3.5 Route goal, save, tackle, restart, halftime, and full-time events to
  audio and visual feedback without duplicate playback.

## 4. Verification and tuning

- [x] 4.1 Extend focused physics/runtime tests for all new phase and event
  transitions, including deterministic replay isolation.
- [x] 4.2 Add an automated snapshot/layout assertion for the 560x360 internal
  viewport and 1280x720 output safe area.
- [ ] 4.3 Manually play the vertical slice through goal, replay, set piece,
  halftime, stoppage, and result at 60 fps; record timing and readability gaps.
- [x] 4.4 Update `features/match3d/FEATURE.md` and validation notes with the
  completed scope and remaining non-goals.
