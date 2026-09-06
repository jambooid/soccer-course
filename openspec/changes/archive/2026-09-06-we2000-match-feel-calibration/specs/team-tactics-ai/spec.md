## ADDED Requirements

### Requirement: Receiving and interception commitments

When a pass selects a teammate, that teammate SHALL receive a bounded receiving
role toward the predicted receiving area. Defending candidates SHALL only leave
their tactical role for a pass interception when their deterministic arrival
estimate beats the receiver by the configured margin.

#### Scenario: Receiver run after a directed pass

- **WHEN** a directed pass names an onside teammate as receiver
- **THEN** that teammate runs toward the predicted receiving area until the
  pass resolves, expires, or is intercepted

#### Scenario: Defender cannot reach pass

- **WHEN** no defender can beat the selected receiver's predicted arrival by the
  interception margin
- **THEN** defensive players retain their coverage roles rather than converging
  on the pass path

### Requirement: Goalkeeper reachability choice

The goalkeeper AI SHALL evaluate collection, parry, dive, recovery, and hold
choices against the same arrival-time model used by ball interactions.

#### Scenario: Late dive is rejected

- **WHEN** a shot arrives after the goalkeeper's latest legal dive start tick
- **THEN** the goalkeeper does not begin an impossible dive and instead retains
  its prior deterministic state

