---
name: soccer-feature-development
description: Create, extend, test, and integrate feature modules in this Godot WE2000-style soccer project while keeping feature documentation, state-machine integration, Godot tests, and manual validation synchronized.
metadata:
  author: soccer-course
  version: "1.0"
---

# Soccer Course Feature Development

Use this skill when implementing a new gameplay or platform feature, or when making a substantial iteration to an existing feature. The deliverable is working project code plus an auditable module under `features/<feature-slug>/`; do not treat a code-only patch as complete.

## Project Context

- This is a Godot 4.x 2D soccer game with WE2000/PES-inspired game feel. Runtime code is primarily in `scenes/`, `utils/`, `resources/`, and `tools/`.
- Gameplay is organized around explicit player, ball, and game-manager state machines. State changes should go through the existing factories and transition signals rather than ad-hoc node replacement.
- Prefer deterministic, testable utility functions and scripted/analytic motion. Do not introduce a general-purpose physics solution when a state rule or closed-form calculation fits the existing architecture.
- Reuse shared event buses, input buffering, player attributes, and `utils/pitch_constants.gd`. Preserve the reference pitch scale (850x360) and avoid new hard-coded dimensions when a project constant exists.
- Game feel is an acceptance criterion: responsive input, readable feedback, useful assistance, and WE2000-like control take priority over physically exhaustive simulation.

## Read Before Editing

Read the smallest set that answers the current question, then inspect the actual code paths and current git status:

1. Always read `features/README.md`, `features/QUICK_START.md`, `docs/superpowers/feature-module-framework.md`, and `features/dribbling/FEATURE.md` as the reference module.
2. For architecture or lifecycle decisions, read the relevant sections of `docs/design-document.md` and `docs/implementation-plan.md`.
3. For gameplay feel or WE2000 mechanics, read the relevant sections of `docs/we2000-core-techniques.md`, `docs/we2000-implementation-research.md`, and the matching `docs/How-*.md` or design document.
4. For test scope, read `docs/testing-strategy.md` and `docs/manual-testing-guide.md`. For resolution or coordinate work, also read the `docs/pixel-independence-*.md` documents.
5. For an existing feature, read its `FEATURE.md`, `implementation/files.txt`, tests, validation results, changelog, and any fix/design notes before changing behavior.

Do not assume a path from a document still exists. Confirm references with `rg --files` and inspect the implementation that is actually present.

## Workflow

### 1. Define the module boundary

- Choose a short lowercase feature slug and confirm it is not an existing module or unrelated user work.
- State the player-visible behavior, the WE2000 reference, non-goals, measurable success criteria, affected attributes, and likely integration points before coding.
- For an iteration, keep the existing module and add a changelog entry; do not create a duplicate module.

### 2. Create or update the feature record

For a new feature, copy `features/_template/` to `features/<feature-slug>/`. Keep these paths even when a directory is initially empty:

```text
FEATURE.md
implementation/files.txt
tests/
docs/
validation/checklist.md
```

Fill `FEATURE.md` as the design contract: goal and WE2000 comparison, success criteria, core mechanism and parameters/formulas, attribute effects, implementation/test files, test strategy, known issues, follow-up work, validation record, and references. Replace every placeholder; do not leave template prose in a claimed implementation.

### 3. Fit the existing architecture

- Put pure calculations in a focused `utils/` class so they can run headless and be tested without a scene tree.
- Put lifecycle and ownership rules in the appropriate state class; register new states in its factory and use the existing `state_transition_requested` signal path.
- Update every entry and exit path, including human input, AI behavior, ball/player possession, kickoff/reset, and failure or release cases. Search for all enum and state references before declaring migration complete.
- Keep tunable constants centralized and document the expected feel of each parameter. Use attributes to create deliberate, testable differences rather than arbitrary randomness.
- Preserve a clear fallback or rollback path for risky state migrations when practical, and record it as a known risk.

### 4. Track implementation and tests

Record every production file touched in `implementation/files.txt`, grouped or commented by role when useful. Keep test and documentation paths in `FEATURE.md` accurate; stale file lists are a defect.

Use the project test layers proportionally:

- **L1:** headless tests for pure formulas, boundaries, normalization, and attribute effects.
- **L2:** lightweight system tests for ball/player physics and AI decisions.
- **L3:** scene smoke or gameplay tests for state transitions, loading, and match flow. Reuse the existing scripts in `tools/` where applicable.
- **L4:** manual `test_scene.tscn` validation for feel, animation/visual feedback, human-vs-AI behavior, edge cases, and performance.

At minimum, a gameplay feature needs focused automated coverage and a filled `validation/checklist.md`. Add integration and performance checks when it crosses state, AI, rendering, or match-flow boundaries.

### 5. Verify before integration

Run the narrowest relevant tests first, then broaden for shared changes. Typical commands are:

```bash
godot --headless --path . -s features/<feature-slug>/tests/test_physics.gd
godot --headless --path . -s tools/test_runner.gd
godot --path . features/<feature-slug>/tests/test_scene.tscn
```

Use the test script's actual entry point if it differs. Capture the real pass/fail counts and notable observations in `validation/test-results.txt` or the module's validation record. Do not claim manual, AI, performance, or integration success without running or explicitly marking it unverified.

Before marking `[INTEGRATED]`, check:

- all required automated tests pass;
- the manual checklist has concrete results and WE2000 feel is acceptable;
- transitions work in both human and AI paths and no stale state enum references remain;
- the main gameplay/smoke flow still loads and runs;
- performance remains within the project's expected stable 60 FPS target for the relevant scenario;
- `features/README.md` and any affected project documentation reflect the new status.

Keep the feature directory after integration as the traceable design, test, and rollback record.

## Completion Standard

Report the module path, production files changed, tests actually run, manual checks completed or still pending, known risks, and the resulting status (`[DEVELOPMENT]`, `[TESTING]`, or `[INTEGRATED]`). If a test cannot run because Godot or a scene is unavailable, state that blocker instead of substituting an unverified claim.

## References

- Framework and templates: `docs/superpowers/feature-module-framework.md`, `docs/superpowers/feature-framework-summary.md`, `docs/superpowers/DELIVERY.md`, `features/_template/`
- Complete example: `features/dribbling/`
- Architecture and implementation roadmap: `docs/design-document.md`, `docs/implementation-plan.md`
- Testing: `docs/testing-strategy.md`, `docs/manual-testing-guide.md`, `tools/test_runner.gd`
- WE2000 feel and mechanics: `docs/we2000-core-techniques.md`, `docs/we2000-implementation-research.md`
