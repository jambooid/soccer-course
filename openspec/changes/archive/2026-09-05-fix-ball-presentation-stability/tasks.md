## 1. Stable Ball Presentation

- [x] 1.1 Update the ball view to calculate roll from consecutive rendered horizontal positions, establish a baseline on initialization/reset, and verify an equivalent traveled distance yields an equivalent model orientation across render cadences.
- [x] 1.2 Align the ball mesh scale and shadow contact plane with the authored `0.14` radius, and verify a grounded ball's mesh and shadow touch the pitch without z-fighting.
- [x] 1.3 Remove presentation-only vertical oscillation from carried ground balls and use the contact-point ground height for possession and kickoff placement; verify human and CPU carriers retain a stable ground height.

## 2. Regression Validation

- [x] 2.1 Add focused runtime coverage for ground-height stability, displacement-based roll, and reset behavior; verify `features/match3d/tests/test_runtime.gd` passes.
- [x] 2.2 Run the dribble focused tests and a headless match scene startup check; verify no regression to possession, ball trajectory, or scene loading.
