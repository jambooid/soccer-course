# 3D Presentation Specification

## ADDED Requirements

### Requirement: Simulation-driven 3D views

3D player and ball views SHALL render simulation snapshots and SHALL NOT decide possession, collisions, trajectory, or rule outcomes.

#### Scenario: Snapshot synchronization
- **WHEN** a simulation snapshot changes a player's 2D position and ball height
- **THEN** the corresponding 3D views map them to XZ position and Y height without changing the snapshot.

### Requirement: Player volume representation

Each active player SHALL render a visible low-poly body with a ground shadow and a footprint-aligned base so body volume is readable from the match camera.

#### Scenario: Crowded players
- **WHEN** players are separated by the simulation footprint resolver
- **THEN** their 3D bases remain visibly separated and their meshes use depth ordering from the 3D camera.

### Requirement: PS1-style camera and materials

The presentation SHALL support a bounded elevated broadcast camera, nearest-filtered low-resolution textures, and simple non-PBR materials.

#### Scenario: Match camera bounds
- **WHEN** the ball travels toward either goal
- **THEN** the camera follows with bounded look-ahead without exposing outside the pitch limits.
