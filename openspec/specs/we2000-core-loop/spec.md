# we2000-core-loop Specification

## Purpose

TBD: Define the long-term gameplay contract for the WE2000-style core loop.

## Requirements

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

### Requirement: Buffered directional actions

The core loop SHALL accept directional pass, shot, tackle, and receive inputs
through a bounded input buffer and SHALL resolve each action at one deterministic
contact window. Input sampled outside a valid window SHALL NOT alter a completed
action retroactively.

#### Scenario: Direction held before contact

- **WHEN** a player supplies a directional action input before the next contact
  window
- **THEN** the resolved action uses that stored direction at the contact window.

### Requirement: Controlled first touch

An eligible intended receiver SHALL use a bounded first-touch result determined
by incoming ball speed, approach direction, technique, and pressure. The first
touch SHALL remain visibly separate from a later carry or kick.

#### Scenario: Unpressured ground reception

- **WHEN** an intended receiver meets a reachable ground pass without an earlier
  opponent interception
- **THEN** it controls the ball in a bounded first-touch area before accepting a
  new carry or kick action.

#### Scenario: Pressured reception

- **WHEN** a defender reaches the receiver's control area within the contest
  margin
- **THEN** the first touch can become a contested loose ball rather than granting
  unconditional possession.
