## ADDED Requirements

### Requirement: Deterministic reception race

For every directed pass, the simulation SHALL resolve an intended receiver,
eligible interceptors, estimated arrival ticks, and one resulting possession or
loose-ball outcome in stable player order.

#### Scenario: Equal arrival candidates

- **WHEN** two eligible players reach a directed pass on the same simulation
  tick within the configured tie tolerance
- **THEN** the simulation resolves one winner using stable ordering and records
  the tie in the interaction metric

### Requirement: Action calibration record

Every calibrated action SHALL emit a serializable record containing the fixed
tick, source and target identifiers, sampled direction, contact window, expected
arrival, actual arrival, and resolved outcome.

#### Scenario: Replayable first-touch record

- **WHEN** a calibrated receive completes
- **THEN** its record is sufficient to compare the same receive outcome across
  rendering cadences without reading presentation state

