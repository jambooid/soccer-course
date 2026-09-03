## 1. Planning And Contracts

- [x] 1.1 Add the WE2000 core-loop and 3D presentation specs and validate the change artifacts with `openspec validate we2000-3d-core-rebuild --type change --strict`
- [x] 1.2 Define a snapshot-to-3D coordinate contract and verify it with a pure utility test

## 2. Immediate Live-Path Corrections

- [x] 2.1 Correct both offside-line implementations and add directional regression cases for left- and right-attacking teams
- [x] 2.2 Gate non-carrier aerial actions by ball distance, height, and detection-area eligibility; verify distant shoot input never enters an aerial state
- [x] 2.3 Make pass execution cancel when the passer no longer owns the ball and use sampled directional input for assisted targeting
- [x] 2.4 Add deterministic kickoff timeout progression and verify an idle kickoff enters active play within the configured tick bound

## 3. Deterministic Contact Core

- [x] 3.1 Add ground-plane player footprint separation with stable ordering and verify overlapping players resolve without oscillation
- [ ] 3.2 Route body contact, tackle, and possession attempts through one per-tick interaction arbitration path and verify one winner per tick
- [ ] 3.3 Replace live gameplay random/time calls with match-scoped tick state where touched by the core loop and verify replay equality

## 4. 3D Presentation Bridge

- [x] 4.1 Add primitive `Player3DView`, `Ball3DView`, and `Pitch3D` scenes driven by snapshots and verify a headless scene load
- [x] 4.2 Add bounded elevated camera and render interpolation; verify camera remains inside pitch limits during a fast shot
- [ ] 4.3 Add low-poly materials, nearest filtering, shadows, and placeholder animation hooks; verify the 3D match scene visually loads

## 5. Regression And Handoff

- [ ] 5.1 Extend the authoritative headless runner with kickoff, footprint, directional-pass, and contact arbitration checks
- [ ] 5.2 Run the full headless suite and a manual 3D match checklist; record remaining tuning gaps in the change notes
