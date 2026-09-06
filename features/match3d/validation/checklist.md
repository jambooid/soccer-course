# 3D Single Match Manual Checklist

**Scene:** `features/match3d/tests/test_scene.tscn`  
**Status:** Pending human play session

- [ ] The scene opens with 22 visible players, one ball, pitch markings, goals, and stands.
- [ ] The fixed broadcast camera frames both goal mouths and never shows an empty scene.
- [ ] Blue player selection follows the ball carrier or nearest blue player.
- [ ] The current ball carrier has a visible gold marker.
- [ ] L/through-pass switches to a teammate in the held direction.
- [ ] Movement and sprint feel immediate but retain a small acceleration ramp.
- [ ] Pass/shoot during the kickoff countdown responds immediately.
- [ ] Holding J fills the shot bar and releasing J launches the charged shot.
- [ ] A roughly aimed short pass finds a forward teammate.
- [ ] A buffered pass entered just before a first touch resolves once at the
  first legal contact, with the originally sampled direction.
- [ ] The selected receiver runs into the intended lane and takes control when
  it arrives first; an earlier defender can still intercept.
- [ ] First-touch trap, settle, and pressured loose-ball outcomes are visually
  distinguishable and do not feel like automatic possession.
- [ ] Long pass visibly carries farther and higher than short pass.
- [ ] Shots are visibly fastest and score only through the goal mouth.
- [ ] A nearby blue player can take the ball from a red carrier with tackle.
- [ ] Red CPU advances, passes, shoots, and a goal returns play to kick-off.
- [ ] GOAL/SHOT/PASS/TACKLE feedback remains visible for its short feedback window.
- [ ] Score and match timer update correctly; full time freezes play.
- [ ] Debug output has no errors and 22-player gameplay sustains 60 FPS.

# Match-Feel Calibration Validation

Automated calibration completed on 2026-09-06:

- [x] Fixed-tick action buffers, receiving races, first touches, and goalkeeper
  outcome records match at 30, 60, and 120 Hz.
- [x] Seeded short pass, through pass, long pass, first touch, interception,
  shielding, tackle, low-save, and coverage-gap scenarios report their budgets.
- [x] Real-window 1280x720 review completed against `../we2000_replay.mkv`:
  assisted pass, first touch, tackle, and goalkeeper feedback remain intentional
  without automatic possession; no baseline tuning delta was identified.
# WE2000 Remaster Vertical Slice Validation

Automated verification completed on 2026-09-06:

- [x] `test_physics.gd`: 26 passed, 0 failed
- [x] `test_runtime.gd`: 89 passed, 0 failed
- [x] `test_match_flow.gd`: 23 passed, 0 failed
- [x] `test_broadcast_presentation.gd`: 7 passed, 0 failed
- [x] Strict OpenSpec validation for `we2000-remaster-vertical-slice`

Manual validation still required in a real OpenGL window at 1280x720:

- [ ] Play from kickoff through a goal, goal focus/replay, and kickoff restart.
- [ ] Force a touchline exit, corner, and goal kick; confirm event labels and
  restart takers are readable.
- [ ] Reach halftime, verify team directions swap, then reach stoppage/full time.
- [ ] Check score, clock, selected-player panel, and radar never overlap or
  clip during normal play and dead-ball framing.
