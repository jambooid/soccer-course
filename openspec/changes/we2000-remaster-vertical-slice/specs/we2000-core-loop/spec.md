## MODIFIED Requirements

### Requirement: Kickoff progression

Every kickoff SHALL enter live play within a bounded number of simulation ticks
even when the human-controlled kicker provides no input. Kickoff SHALL also be
used as the deterministic restart state after a valid goal and at the beginning
of the second half.

#### Scenario: No input after kickoff

- **WHEN** the kickoff player remains idle until the kickoff timeout
- **THEN** the kickoff state performs a deterministic safe advance and the ball
  enters active play

#### Scenario: Goal restart kickoff

- **WHEN** a goal presentation window completes
- **THEN** players return to their half-specific kickoff anchors, the conceding
  team is assigned the kickoff, and live play resumes within the same bounded
  timeout

### Requirement: Match phase transitions

The match SHALL preserve deterministic player positions, attacking directions,
score, and clock semantics across first-half, halftime, second-half, stoppage,
and full-time transitions.

#### Scenario: Side swap at halftime

- **WHEN** the first half ends
- **THEN** both teams swap attacking direction and restart anchors while the
  score and player match statistics remain unchanged

#### Scenario: Full-time result

- **WHEN** stoppage time expires
- **THEN** live input no longer changes the match, a result payload contains the
  final score and goal records, and the match emits one terminal event

