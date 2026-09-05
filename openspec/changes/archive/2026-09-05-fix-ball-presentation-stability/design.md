## Context

See `proposal.md` for motivation. The match simulation publishes an authoritative ball position and velocity at fixed ticks, while `Ball3DView` is synchronized at render cadence. The current view treats instantaneous velocity as a per-sync displacement and the carried-ball simulation adds a decorative vertical sine wave. The imported mesh's native radius is 0.14 world units, but the view scales it and positions its shadow according to a different radius convention.

## Goals / Non-Goals

**Goals:**

- Make a ball's visual roll proportional to the horizontal distance its view actually traveled.
- Keep grounded possession visually grounded for all carriers.
- Establish one radius/contact convention for the ball mesh and shadow.
- Verify behavior without changing fixed-tick match outcomes.

**Non-Goals:**

- Change possession, dribble-contact, collision, free-ball, or camera rules.
- Add animation-event synchronization or alter airborne ball physics.
- Rework the low-poly ball asset.

## Decisions

### Derive roll from position delta

`Ball3DView` will retain its most recently rendered world position and rotate around the horizontal travel axis by displacement divided by the authored radius. Initial placement and discontinuous resets will establish the baseline rather than produce a visible spin.

Using the position delta matches the transform actually presented after fixed-tick catch-up and is independent of the number of render callbacks. Passing a render `delta` into each existing sync caller was considered, but it would still derive motion from velocity and risks disagreement when more than one simulation tick occurs per frame.

### Grounded position is the ball mesh's contact point

The mesh will render at its native radius and the authoritative grounded ball position will represent its contact point on the pitch. Grounded possession and kickoff placement will use zero height; the shadow will be placed at the same contact plane with only a small anti-z-fighting offset.

Re-centering the imported mesh around a center-height simulation coordinate was considered, but would require changing all free-ball trajectory and ground tests. Using the existing contact-point convention minimizes the gameplay surface affected.

### Remove decorative vertical motion

Grounded dribble state will publish a fixed ground height. The model's rolling orientation is sufficient movement feedback; vertical bob is reserved for actual airborne trajectory state.

## Risks / Trade-offs

- [Unexpected large transform is treated as normal motion and spins the ball] -> Treat initialization and known reset-sized jumps as position baselines, and cover reset behavior in tests.
- [Existing tests encode the old 0.08 grounded position] -> Update only presentation assertions to the contact-point convention; leave airborne assertions intact.
- [A flat native-size model feels smaller than before] -> Verify its 0.14 radius against player foot scale in the match scene before accepting the change.

## Migration Plan

1. Update the ball view and grounded presentation values together.
2. Run the focused runtime and dribble tests, then a headless scene startup check.
3. Roll back by reverting the view and grounded-height changes as one unit; no saved-state migration is required.
