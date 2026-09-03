# Deterministic Match Simulation Delta

## MODIFIED Requirements

### Requirement: Fixed match progression

The live match path SHALL advance gameplay state in fixed ticks and SHALL expose the same snapshots and event sequence for an identical setup, seed, and input stream regardless of rendering cadence.

#### Scenario: Live replay at different render cadences
- **WHEN** the same live match replay runs with different rendering frame rates
- **THEN** player transforms, ball trajectory, action timing, possession, and rule outcomes are identical per simulation tick.

#### Scenario: Same replay at different render cadences
- **WHEN** the same initial state, seed, and input replay run under different rendering cadences
- **THEN** each fixed tick produces the same simulation snapshot and event sequence.

### Requirement: Seeded gameplay randomness

Every gameplay-affecting random outcome in the live match SHALL come from the match-scoped seed and SHALL record enough state to replay the outcome.

#### Scenario: Live contested ball replay
- **WHEN** a contested-ball event is replayed from the same snapshot and seed
- **THEN** the winner, resulting ball state, and trajectory are identical.

#### Scenario: Replaying a contested ball
- **WHEN** a replay repeats a contested-ball event with the original seed and inputs
- **THEN** it selects the same winner, ball state, and resulting trajectory.
