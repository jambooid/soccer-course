# headless-match-validation Specification

## Purpose

Provide a version-pinned, non-interactive validation path that can prove core football behavior and make gameplay regressions reproducible on developer machines and continuous integration.

## Requirements

### Requirement: Pinned headless runtime
The project SHALL document one supported Godot 4.4.x headless executable contract and provide a command that verifies project parsing and imports using a writable engine user-data location.

#### Scenario: Fresh validation environment
- **WHEN** a developer supplies the supported Godot executable and a writable user-data location
- **THEN** the documented validation command completes project parsing without interactive editor input.

### Requirement: Authoritative test exit status
The headless test runner SHALL exit with a non-zero status when any registered assertion, setup step, timeout, or runtime error fails.

#### Scenario: Failing scenario
- **WHEN** a registered scenario assertion fails
- **THEN** the runner reports the failed scenario and returns a non-zero process status.

### Requirement: Deterministic gameplay scenarios
The headless suite SHALL execute deterministic scenarios for kickoff, controlled dribbling, ground pass receipt, contested possession, tackle resolution, shot or goalkeeper interaction, and CPU decision selection.

#### Scenario: Scenario regression
- **WHEN** a core gameplay scenario runs with its declared seed and input frames
- **THEN** it asserts the expected state and event sequence within a bounded tick timeout.

### Requirement: Replay diagnostics
For every failed deterministic scenario, the runner SHALL report the scenario name, seed, simulation tick, expected outcome, actual outcome, and replayable input or snapshot reference.

#### Scenario: Snapshot mismatch
- **WHEN** a replay produces a snapshot hash different from its baseline
- **THEN** the runner reports the first divergent tick and the information required to rerun that case.
