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
- [ ] Long pass visibly carries farther and higher than short pass.
- [ ] Shots are visibly fastest and score only through the goal mouth.
- [ ] A nearby blue player can take the ball from a red carrier with tackle.
- [ ] Red CPU advances, passes, shoots, and a goal returns play to kick-off.
- [ ] GOAL/SHOT/PASS/TACKLE feedback remains visible for its short feedback window.
- [ ] Score and match timer update correctly; full time freezes play.
- [ ] Debug output has no errors and 22-player gameplay sustains 60 FPS.
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
