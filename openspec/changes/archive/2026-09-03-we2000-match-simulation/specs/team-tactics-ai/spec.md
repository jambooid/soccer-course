## Purpose

Provide predictable, football-shaped CPU behavior that preserves team structure, creates viable options, and reacts to the same match state consistently in the arcade WE2000-style match loop.

## ADDED Requirements

### Requirement: Team defensive assignments
When the opposing team controls or can first reach the ball, each CPU-controlled outfield player SHALL receive a team role that preserves defensive structure, including an active presser, cover support, and goal-side protection where applicable.

#### Scenario: Opponent attacks near midfield
- **WHEN** an opponent carries the ball through midfield
- **THEN** at most the assigned pressure role commits directly while remaining defenders retain their coverage or formation responsibility.

### Requirement: Formation-aware off-ball movement
CPU-controlled players SHALL maintain role-appropriate formation anchors and adjust width, depth, and support positions according to ball side and possession phase.

#### Scenario: Team attacks on one wing
- **WHEN** a team controls the ball near a wing
- **THEN** supporting players create defined central, wide, and safety options without every player converging on the ball.

### Requirement: Offside-aware support and passing
The team tactical state SHALL expose an offside boundary. CPU off-ball targets and CPU pass candidates SHALL exclude positions or recipients that are offside at the planned release tick unless the relevant restart rule exempts offside.

#### Scenario: Forward near the defensive line
- **WHEN** a forward's support target would cross the current offside boundary
- **THEN** the target is constrained to an onside position and an offside recipient is not selected for a normal pass.

### Requirement: Reproducible CPU decisions
Given the same tactical snapshot, attributes, input replay, and match seed, CPU movement and action choices SHALL be reproducible. Performance scheduling SHALL NOT change the decision result for a player with an active ball or defensive assignment.

#### Scenario: Same CPU possession replay
- **WHEN** a CPU ball carrier is replayed from the same tactical snapshot
- **THEN** it selects the same action and target at the same decision tick.

### Requirement: Reachability-based action selection
CPU passing, shooting, interception, and goalkeeper collection decisions SHALL evaluate the ball's predicted arrival time and position, eligible player reachability, and relevant rule constraints before committing an action.

#### Scenario: Blocked passing lane
- **WHEN** an opposing player can reach a planned pass trajectory before the intended receiver
- **THEN** the CPU does not rate that option as safely reachable over a viable alternative.

### Requirement: Responsive control assignment
In player-controlled modes, possession changes and defensive switching SHALL assign human control to a tactically appropriate eligible teammate within a bounded decision delay, while preserving a short switch lock to avoid oscillation.

#### Scenario: Defending a loose ball
- **WHEN** the player's team does not control a loose ball
- **THEN** the control assignment selects an eligible defensive candidate according to the current tactical state and does not switch repeatedly during the lock interval.

