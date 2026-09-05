## MODIFIED Requirements

### Requirement: Simulation-driven 3D views

3D player and ball views SHALL render simulation snapshots and SHALL NOT decide possession, collisions, trajectory, or rule outcomes. Ball roll SHALL be derived from the rendered horizontal displacement so identical simulation movement produces the same final orientation regardless of render cadence. A grounded ball SHALL remain in visible contact with the pitch without presentation-only vertical oscillation, and its mesh and shadow SHALL use the same authored contact radius.

#### Scenario: Snapshot synchronization

- **WHEN** a simulation snapshot changes a player's 2D position and ball height
- **THEN** the corresponding 3D views map them to XZ position and Y height without changing the snapshot.

#### Scenario: Grounded carried ball

- **WHEN** either a human-controlled or CPU-controlled player carries the ball along the pitch
- **THEN** the ball remains at its grounded contact height and its shadow remains aligned to the pitch.

#### Scenario: Render cadence variation

- **WHEN** the same horizontal ball movement is rendered over different frame cadences
- **THEN** the ball reaches an equivalent rendered roll orientation without frame-rate-dependent spin jumps.
