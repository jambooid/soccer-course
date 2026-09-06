## Purpose

This capability defines a deterministic WE2000-style match broadcast loop so
gameplay state, camera direction, HUD, audio, and replay can react to the same
observable events without competing authorities.

## ADDED Requirements

### Requirement: Authoritative match timeline

The match SHALL expose a deterministic timeline with `KICKOFF`, `FIRST_HALF`,
`HALFTIME`, `SECOND_HALF`, `STOPPAGE_TIME`, and `FULL_TIME` phases. Match time
SHALL advance only during live play and SHALL pause during goal, halftime, and
restart presentation windows.

#### Scenario: Goal restart

- **WHEN** the ball completely crosses the goal line within the goal mouth
- **THEN** the score and scorer statistics update once, a goal event is emitted,
  live time pauses, and both teams enter a bounded restart window before the
  next kickoff

#### Scenario: Halftime transition

- **WHEN** first-half live time reaches zero
- **THEN** the match emits a halftime event, swaps attacking directions for the
  second half, and resumes only after the halftime presentation window ends

#### Scenario: Full time with stoppage

- **WHEN** regulation time reaches zero while play is active
- **THEN** the match enters stoppage time for the configured duration, displays
  a loss-time indicator, and emits exactly one full-time event when that window
  expires

### Requirement: Deterministic restart decisions

The match SHALL classify a dead ball as kickoff, throw-in, corner, goal kick,
or indirect restart using the last touch team, exit boundary, and goal-mouth
position. A restart SHALL identify the restart team, location, and reason in a
copied restart payload.

#### Scenario: Defender clears over own goal line

- **WHEN** the defending team is the last team to touch the ball before it
  crosses its own goal line outside the goal mouth
- **THEN** the match emits a corner restart for the attacking team at the
  corresponding corner location

#### Scenario: Attacker sends ball over opponent goal line

- **WHEN** the attacking team is the last team to touch the ball before it
  crosses the opponent goal line outside the goal mouth
- **THEN** the match emits a goal-kick restart for the defending team

### Requirement: Shared event and snapshot boundary

Every goal, save, tackle, restart, half transition, stoppage-time transition,
and full-time outcome SHALL be represented by an immutable event payload. A
presentation snapshot SHALL contain copied player, ball, score, clock, phase,
selected-player, and radar data and SHALL be safe for consumers to retain.

#### Scenario: Snapshot consumer retains prior frame

- **WHEN** a consumer stores a presentation snapshot and the simulation advances
  several ticks
- **THEN** the stored snapshot remains unchanged and cannot alter simulation
  state through nested player or ball data

#### Scenario: Goal event fan-out

- **WHEN** a goal event is emitted
- **THEN** HUD, audio, camera, and replay consumers can observe the same scorer,
  assist, minute, and score values without each recomputing them

### Requirement: Isolated goal replay

The system SHALL capture a bounded history of presentation snapshots surrounding
key events and SHALL replay that history without advancing or mutating the
authoritative simulation.

#### Scenario: Replay playback

- **WHEN** a goal replay starts
- **THEN** the camera and player/ball views consume historical snapshots,
  simulation time and score remain frozen, and playback ends in a restart-ready
  live snapshot

#### Scenario: Replay history is unavailable

- **WHEN** a key event has fewer than the minimum required history frames
- **THEN** the system shows the event result without crashing and returns to the
  normal broadcast camera after the configured fallback duration

### Requirement: Minimum broadcast HUD

During a live match the HUD SHALL display both team identities, score, half,
match clock, selected player identity, and a radar containing all active players
and the ball. Dead-ball events SHALL display a readable event label without
covering the score or clock.

#### Scenario: Live match readability

- **WHEN** the match is in either half and the viewport is 1280x720
- **THEN** score, clock, half marker, selected-player panel, and radar are
  simultaneously visible within the safe area with no overlapping text

#### Scenario: Set-piece label

- **WHEN** a corner or goal-kick restart is active
- **THEN** the HUD displays the restart label and hides it after live play resumes

