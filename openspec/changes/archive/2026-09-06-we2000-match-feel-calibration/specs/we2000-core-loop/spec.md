## ADDED Requirements

### Requirement: Buffered directional actions

The core loop SHALL accept directional pass, shot, tackle, and receive inputs
through a bounded input buffer and SHALL resolve each action at one deterministic
contact window. Input sampled outside a valid window SHALL NOT alter a completed
action retroactively.

#### Scenario: Direction held before contact

- **WHEN** a player supplies a directional action input before the next contact
  window
- **THEN** the resolved action uses that stored direction at the contact window

### Requirement: Controlled first touch

An eligible intended receiver SHALL use a bounded first-touch result determined
by incoming ball speed, approach direction, technique, and pressure. The first
touch SHALL remain visibly separate from a later carry or kick.

#### Scenario: Unpressured ground reception

- **WHEN** an intended receiver meets a reachable ground pass without an earlier
  opponent interception
- **THEN** it controls the ball in a bounded first-touch area before accepting a
  new carry or kick action

#### Scenario: Pressured reception

- **WHEN** a defender reaches the receiver's control area within the contest
  margin
- **THEN** the first touch can become a contested loose ball rather than granting
  unconditional possession

