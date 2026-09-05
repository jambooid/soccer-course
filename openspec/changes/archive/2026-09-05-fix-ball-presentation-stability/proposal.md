## Why

The carried ball visibly flickers and appears to float for both human and CPU carriers. The current view rotates the low-poly model by a velocity-sized angle on every render update and adds an artificial vertical oscillation to ground dribbles, making the artifact frame-rate dependent and visually disconnected from the pitch.

## What Changes

- Make rendered ball roll derive from physical horizontal displacement over elapsed presentation time.
- Keep a grounded dribbling ball at its authored contact height instead of applying a periodic vertical bob.
- Align the ball model's rendered radius, ground contact height, and shadow placement.
- Add regression coverage for stable grounded-ball presentation behavior.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `3d-presentation`: Grounded ball presentation must have frame-rate-independent roll and stable contact with the pitch.

## Impact

- Affects `scenes/world3d/ball_3d_view.gd` and the grounded dribble presentation in `scenes/world3d/match3d_game.gd`.
- Extends match runtime tests; gameplay ownership, trajectory, and AI decisions remain unchanged.
