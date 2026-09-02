## 1. Validation Bootstrap

- [x] 1.1 Remove audit-generated `.import` metadata churn only after confirming it is not user work, and verify `git status --short` contains no unintended import-only changes.
- [x] 1.2 Document the supported Godot 4.4.x binary contract, `GODOT_BIN`, writable user-data location, and parse/import preflight command; verify the command succeeds on the supported local runtime.
- [x] 1.3 Create one `SceneTree` headless runner with suite registration, structured failure output, bounded timeouts, and non-zero failure exits; verify an intentional failing fixture exits non-zero.
- [x] 1.4 Migrate existing pure dribble, shooting, interception, and offside checks to the runner; verify all passing suites run through one command and failures change the process status.
- [x] 1.5 Add a seeded test-RNG utility and prohibit global gameplay random calls in new simulation code; verify repeated utility suites produce identical values for the same seed.

## 2. Deterministic Match Foundation

- [x] 2.1 Define match snapshot, input-frame, event-log, and tick-hash data structures; verify a constructed snapshot serializes to a stable hash across repeated runs.
- [x] 2.2 Add a fixed 60 Hz match simulation coordinator that advances tick state independently of rendering; verify a scripted idle replay yields the same snapshots at multiple render cadences.
- [x] 2.3 Add match-scoped RNG state to simulation snapshots and replay diagnostics; verify a seeded contested-event replay consumes and restores the same RNG state.
- [x] 2.4 Convert Player and Ball movement writes from render-frame processing to the simulation path while keeping rendering as a consumer; verify player and ball transforms remain equal under 30/60/120 FPS replay harnesses.
- [x] 2.5 Replace deferred gameplay state transitions with a tick-end transition queue; verify a same-tick shot, save, and possession change creates one committed state transition per owner.

## 3. Ball Trajectory And Interaction Resolution

- [x] 3.1 Implement one trajectory model for ground friction, air height, bounce, landing position, and arrival time; verify prediction error against fixed-tick simulation stays within the declared scenario tolerance.
- [x] 3.2 Route short pass, long pass, and through pass creation through the trajectory solver; verify target-distance scenarios reach receiving areas within their position and timing tolerances.
- [x] 3.3 Define control profiles for foot, chest, head, volley, tackle, and goalkeeper hands; verify identical height/contact geometry has the same eligibility result regardless of prior ball state.
- [x] 3.4 Add interaction intents and a deterministic resolver for control, interception, tackle, deflection, collection, and kick; verify simultaneous candidates produce one stable outcome and one carrier.
- [ ] 3.5 Convert free-ball capture and Area callbacks into non-authoritative candidate collection; verify collision callback ordering cannot change the winner in a repeated scenario.
- [ ] 3.6 Migrate goalkeeper collection and deflection to the resolver with penalty-area, height, speed, and release-lock rules; verify keeper scenario matrix covers valid catch, parry, invalid collection, and opponent pass.

## 4. WE-Style Action Rhythm

- [ ] 4.1 Replace per-frame dribble position/velocity correction with seeded, logged touch impulses and control-distance rules; verify straight, stop, 90-degree, 180-degree, and sprint scenarios emit expected touch sequences.
- [ ] 4.2 Make turn handling affect player intent and action timing without directly rewriting ball movement; verify identical turn replays retain the same touch events and loss-of-control tick.
- [ ] 4.3 Model pass, shot, tackle, aerial contact, and goalkeeper actions as startup, active, and recovery phases; verify each action affects the ball only during its active window.
- [ ] 4.4 Split standing interception and sliding tackle eligibility, including direction, approach speed, defense, technique, and ball-first ordering; verify the five canonical tackle scenarios return the expected outcome.
- [ ] 4.5 Connect action events to existing player/ball state-machine adapters and remove superseded direct ownership mutations; verify a playable kickoff, pass, shot, save, and tackle flow has no duplicate possession events.

## 5. Team Tactics And Control Assignment

- [x] 5.1 Build a team tactical snapshot containing possession phase, formation anchors, offside line, active presser, cover player, defensive line, and support slots; verify a fixture exposes stable assignments for both teams.
- [ ] 5.2 Replace nearest-ball team steering with role-aware pressure, cover, marking, and goal-side protection; verify an attack fixture retains defensive shape while only the designated presser commits.
- [ ] 5.3 Add possession-aware width, depth, ball-side shifting, and support movement from formation anchors; verify wing and central attack fixtures retain central, wide, and safety options.
- [ ] 5.4 Apply the tactical offside line to CPU support targets and pass candidate filtering; verify forward-run and pass-selection scenarios never choose a normal-pass offside target.
- [ ] 5.5 Replace CPU action coin flips with reachability and utility scoring using trajectory ETA, interception risk, attributes, and rule constraints; verify identical snapshots select the same pass, shot, or retain-ball action.
- [ ] 5.6 Rework goalkeeper line, set, rush, claim, dive, and distribution choices to use trajectory predictions; verify a shot/collection matrix produces consistent decisions and legal collection behavior.
- [ ] 5.7 Implement possession and defensive player-switch scoring with eligibility, direction intent, goalkeeper policy, and switch lock; verify possession gain and loose-ball fixtures select a stable human-controlled player without oscillation.

## 6. Integration And Regression Gate

- [ ] 6.1 Add minimal deterministic headless scenarios for kickoff, dribble, ground pass, contest, tackle, shot/save, CPU action choice, and player switching; verify each scenario has a bounded tick timeout and replay diagnostic.
- [ ] 6.2 Add long CPU-vs-CPU diagnostic simulations with fixed seeds and summary metrics for goals, passes, interceptions, offside calls, tackles, and formation spread; verify repeated runs produce identical metrics.
- [x] 6.3 Adapt legacy smoke and runtime scripts to the unified runner or label them diagnostic-only with explicit limitations; verify no documented CI command treats print-only scripts as passing tests.
- [ ] 6.4 Run the complete supported Godot 4.4.x headless suite and manual WE-feel checklist; verify no parser errors, no duplicate ball ownership, deterministic replay hashes, and acceptable gameplay behavior for dribble, passing, shooting, tackling, goalkeeping, and AI shape.
