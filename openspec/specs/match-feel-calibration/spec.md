# match-feel-calibration Specification

## Purpose

Define observable assisted-action timing, receiving contests, goalkeeper
outcomes, and deterministic calibration evidence for the playable match.

## Requirements

### Requirement: Buffered action acceptance

The match SHALL retain a valid pass, shot, tackle, receive, or goalkeeper input
pressed during an action lock until its next compatible contact window or until
the configured buffer duration expires. The accepted action SHALL use the
direction sampled with the input.

#### Scenario: Buffered pass after first touch

- **WHEN** a player presses pass before a receive action reaches its compatible
  contact window
- **THEN** the player performs that directed pass at the window without
  requiring the input to be pressed again.

#### Scenario: Expired buffered action

- **WHEN** no compatible contact window occurs before the configured buffer
  duration expires
- **THEN** the input has no later effect and the player returns to a controllable
  state.

### Requirement: Assisted but contestable receiving

For a directed pass, the selected eligible teammate SHALL commit to the intended
receiving area and receive assisted control when it reaches the ball within the
configured arrival and control tolerance. An opponent SHALL take precedence
only when it reaches a legal interception point by the configured earlier-arrival
margin.

#### Scenario: Intended receiver arrives first

- **WHEN** the intended receiver reaches a controllable ball before every
  opponent by at least the interception margin
- **THEN** that receiver gains possession and becomes the controlled player for
  a human-controlled team.

#### Scenario: Opponent has an earlier interception

- **WHEN** an opponent reaches the pass path or receiving area earlier than the
  intended receiver by the interception margin
- **THEN** the opponent gains possession and the pass assistance is cancelled.

### Requirement: Learnable goalkeeper contest

The goalkeeper SHALL select collect, parry, dive, recover, or hold-position
outcomes from ball arrival time, reachable volume, current action window, and
configured coverage gaps. Repeating the same snapshot and input SHALL produce
the same goalkeeper outcome.

#### Scenario: Reachable low shot

- **WHEN** a low shot reaches a goalkeeper's legal collection or dive volume
  during its active window
- **THEN** the goalkeeper performs the resolved save outcome and the ball enters
  the corresponding held or deflected state.

#### Scenario: Exposed coverage gap

- **WHEN** a shot targets a configured reachable-volume gap while the goalkeeper
  cannot start a new save action in time
- **THEN** the shot remains unblocked so players can learn and exploit that gap.

### Requirement: Feel calibration evidence

The match SHALL record deterministic scenario metrics for each pass, receive,
interception, tackle, save, and possession change, including action tick,
actor, target, arrival delta, and outcome. Calibration scenarios SHALL run from
fixed snapshots and inputs.

#### Scenario: Repeated pass scenario

- **WHEN** the same calibrated pass scenario is run with the same seed and
  input stream
- **THEN** the selected target, receiving outcome, metric record, and possession
  transition are identical on every run.

#### Scenario: Metric budget regression

- **WHEN** a calibrated scenario exceeds its configured arrival, first-touch, or
  control error budget
- **THEN** automated validation reports the scenario name and measured value.
