## MODIFIED Requirements

### Requirement: PS1-style camera and materials

The presentation SHALL support a bounded elevated broadcast camera,
nearest-filtered low-resolution textures, simple non-PBR materials, and an
event-driven camera director with stable shot transitions.

#### Scenario: Match camera bounds

- **WHEN** the ball travels toward either goal
- **THEN** the camera follows with bounded look-ahead without exposing outside
  the pitch limits

#### Scenario: Goal focus transition

- **WHEN** the presentation receives a goal event
- **THEN** the camera enters a goal-focus shot for a minimum hold duration,
  transitions to replay if history is available, and then returns to a
  restart-ready broadcast shot without changing simulation state

#### Scenario: Set-piece framing

- **WHEN** a corner or goal-kick restart becomes active
- **THEN** the camera frames the restart location, keeps the ball and taker in
  view, and returns to regular follow after the ball becomes live

### Requirement: Simulation-driven 3D views

3D player and ball views SHALL render simulation or replay snapshots and SHALL
NOT decide possession, collisions, trajectory, or rule outcomes. During replay,
views SHALL consume the replay snapshot source exclusively.

#### Scenario: Snapshot synchronization

- **WHEN** a simulation snapshot changes a player's 2D position and ball height
- **THEN** the corresponding 3D views map them to XZ position and Y height
  without changing the snapshot

#### Scenario: Grounded carried ball

- **WHEN** either a human-controlled or CPU-controlled player carries the ball
  along the pitch
- **THEN** the ball remains at its grounded contact height and its shadow
  remains aligned to the pitch

#### Scenario: Render cadence variation

- **WHEN** the same horizontal ball movement is rendered over different frame
  cadences
- **THEN** the ball reaches an equivalent rendered roll orientation without
  frame-rate-dependent spin jumps

#### Scenario: Replay isolation

- **WHEN** replay playback is active
- **THEN** rendered positions may change between historical frames while the
  authoritative simulation tick, score, and possession remain unchanged
