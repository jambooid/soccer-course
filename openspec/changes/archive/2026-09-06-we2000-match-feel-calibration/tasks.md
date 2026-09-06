## 1. Deterministic Feel Primitives

- [x] 1.1 Add pure action-intent, contact-window, arrival-race, and calibration-metric helpers; verify unit tests cover expiry, stable ties, and serializable records.
- [x] 1.2 Add pass receiving-area prediction and deterministic receiver/interceptor arrival estimates; verify a closer receiver, an earlier interceptor, and an equal-arrival tie resolve as specified.
- [x] 1.3 Add a bounded first-touch state and settle calculation; verify low-speed, high-speed, and pressured receptions produce separate deterministic outcomes.

## 2. Input and Passing Integration

- [x] 2.1 Route existing pass, shot, tackle, and receive inputs through a single-slot bounded action buffer; verify buffered direction is consumed at the earliest valid contact window and expired input has no effect.
- [x] 2.2 Replace nearest-only free-ball resolution for directed passes with the shared arrival race; verify intended receivers auto-switch human control while valid early interceptions still win possession.
- [x] 2.3 Add receiver and interceptor tactical assignments that preserve formation for unreachable defenders; verify receiving runs end on receipt, expiry, or interception.
- [x] 2.4 Emit match events and calibration records for pass, receive, interception, first touch, and possession change; verify no duplicate interaction outcome occurs in one tick.

## 3. Contest and Goalkeeper Calibration

- [x] 3.1 Tune shielding and tackle contact windows around the shared first-touch state; verify protected, front-side, and late-tackle scenarios remain deterministic.
- [x] 3.2 Add deterministic goalkeeper collect, parry, dive, recovery, and coverage-gap outcome selection; verify reachable low shots save, late dives are rejected, and configured gaps remain scoreable.
- [x] 3.3 Connect goalkeeper outcomes to ball states, player-view actions, camera/HUD events, and audio; verify each resolved outcome is visible and emits once.

## 4. Calibration Evidence

- [x] 4.1 Add seeded headless feel scenarios for short pass, through pass, long pass, first touch, interception, shielding, tackle, low save, and coverage-gap shot; verify each reports its measured budget.
- [x] 4.2 Add render-cadence comparisons for action buffers, receiving races, first touches, and goalkeeper outcomes; verify snapshots, metrics, and possession outcomes match at 30/60/120 Hz.
- [x] 4.3 Record and review a real-window 1280x720 play session against the WE2000 reference; verify assisted actions feel intentional rather than automatic and capture tuning deltas in validation notes.
- [x] 4.4 Update match feature documentation and calibration baseline values; verify all focused suites and the project OpenSpec strict validation pass.
