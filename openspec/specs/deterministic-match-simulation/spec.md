# deterministic-match-simulation Specification

## Purpose

Provide a repeatable match simulation whose ball, player, action, and possession outcomes are independent of rendering cadence and can be inspected or replayed when gameplay behavior regresses.

## Requirements

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

### Requirement: Single interaction outcome
For every simulation tick, the system SHALL resolve competing possession, interception, tackle, deflection, goalkeeper collection, and action-contact attempts into at most one authoritative ball interaction outcome.

#### Scenario: Simultaneous player contact
- **WHEN** two eligible players reach a free ball in the same simulation tick
- **THEN** the system emits one resolved interaction outcome and assigns at most one carrier.

### Requirement: Consistent ball trajectories
Passes, shots, deflections, and goalkeeper decisions SHALL use one trajectory model for horizontal movement, height, landing, and arrival time. A requested pass target SHALL determine a trajectory that reaches the intended receiving area within the allowed error budget.

#### Scenario: Ground pass target
- **WHEN** a ground pass is requested to a reachable target position
- **THEN** the ball first enters the receiving area within the configured position and arrival-time tolerance.

### Requirement: Action contact windows
Dribbling touches, kicks, tackles, headers, volleys, and goalkeeper actions SHALL affect the ball only during their defined gameplay contact windows. A player's attributes and approach geometry SHALL influence eligible interactions.

#### Scenario: Tackle outside active window
- **WHEN** a player overlaps a ball or opponent before or after a tackle contact window
- **THEN** the tackle does not resolve as a successful ball interaction.
