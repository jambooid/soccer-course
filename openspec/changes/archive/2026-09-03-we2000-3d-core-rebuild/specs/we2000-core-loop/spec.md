# WE2000 Core Loop Specification

## ADDED Requirements

### Requirement: Spatial player occupancy

The match SHALL maintain a non-overlapping ground-plane footprint for every active player and SHALL resolve separation in stable player order.

#### Scenario: Two players enter the same space
- **WHEN** two active players' footprints overlap during a simulation tick
- **THEN** the resolver separates them within the same tick and produces the same positions for the same snapshot and inputs.

### Requirement: Readable physical contest

The match SHALL distinguish passive body contact, shielding, and active tackle contact windows. A tackle outside its active window SHALL NOT change possession.

#### Scenario: Shielded carrier meets defender
- **WHEN** a defender contacts a carrier from outside the active tackle window
- **THEN** the carrier remains in possession and both players receive bounded contact displacement.

### Requirement: Kickoff progression

Every kickoff SHALL enter live play within a bounded number of simulation ticks even when the human-controlled kicker provides no input.

#### Scenario: No input after kickoff
- **WHEN** the kickoff player remains idle until the kickoff timeout
- **THEN** the kickoff state performs a deterministic safe advance and the ball enters active play.

### Requirement: Directional passing intent

Pass target selection SHALL use the direction sampled at action acceptance, including vertical and diagonal input, and SHALL remain deterministic for a fixed input frame.

#### Scenario: Diagonal pass input
- **WHEN** a player presses pass with a diagonal direction
- **THEN** target selection searches that directional cone before fallback targets.
