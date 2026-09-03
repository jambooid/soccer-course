# Team Tactics AI Delta

## MODIFIED Requirements

### Requirement: Reachability-based action selection

CPU passing, shooting, interception, and goalkeeper decisions SHALL evaluate the shared ball trajectory, player arrival time, blocking opponents, and player footprint/contact eligibility before committing an action.

#### Scenario: Contact blocks a planned pass
- **WHEN** an opponent can reach the planned pass channel or contact the receiver before the ball
- **THEN** the CPU rejects or downgrades that option in favor of a reachable legal alternative.

#### Scenario: Blocked passing lane
- **WHEN** an opposing player can reach a planned pass trajectory before the intended receiver
- **THEN** the CPU does not rate that option as safely reachable over a viable alternative.

### Requirement: Reproducible CPU decisions

CPU movement and action choices SHALL be reproducible for the same tactical snapshot, input replay, and match seed, including when players are scheduled at different LOD frequencies.

#### Scenario: LOD scheduling replay
- **WHEN** the same tactical snapshot is evaluated with equivalent render cadence but different presentation scheduling
- **THEN** active pressers and ball carriers choose the same movement and action at the same simulation tick.

#### Scenario: Same CPU possession replay
- **WHEN** a CPU ball carrier is replayed from the same tactical snapshot
- **THEN** it selects the same action and target at the same decision tick.
