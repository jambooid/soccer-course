# CLAUDE.md

Guidance for Claude Code working in this repository.

## Project

**Soccer Course** — a 2D arcade soccer game built in **Godot 4.4** (GDScript, GL Compatibility renderer). This repo doubles as a *course* for building a 2D soccer game, so code is written to be readable and instructive rather than maximally terse.

Low-res pixel art: internal viewport is **560×360**, integer-scaled up to 2240×1440 (`window/stretch/mode="viewport"`, `scale_mode="integer"`). `default_texture_filter=0` (nearest) keeps pixels crisp — never apply smoothing/filtering to art assets.

## Running

Open in the Godot 4.4 editor and press Play, or from CLI:

```sh
godot --path .          # open editor
godot --path . --main   # run the game (if your godot build supports --main)
```

There is no linter or build step. Tests live in `tools/` (see **Testing** below). `.godot/` and `.import/` are gitignored (generated).

## Architecture

The codebase is built around a **state-machine pattern applied uniformly** to four domains: the game/match (`GameManager`), the ball, the player, and the screens. Each domain follows the same triad:

- **`*State`** (extends `Node`) — one class per state. Receives context via `setup(...)`, holds a `state_transition_requested` signal, and calls `transition_state(Enum.VALUE, data)` to switch. Override hooks like `on_animation_complete()`, `can_carry_ball()`, etc. default to no-op/`false`.
- **`*StateFactory`** — maps an `enum` → state class in a `Dictionary`, instantiated fresh via `.new()` in `get_fresh_state()`.
- **`*StateData`** — a plain object carrying transition payload, built fluently: `PlayerStateData.build().set_shot_direction(v).set_shot_power(p)`.

The owner (e.g. `Player`, `Ball`, `GameManager`) holds `switch_state(enum, data)` which `queue_free()`s the old state, creates the new one via the factory, wires its `state_transition_requested` signal back to `switch_state` (using `.bind()`), and `call_deferred("add_child", ...)`s it. States are **Nodes added as children**, not plain objects — this is intentional and consistent.

### Screens

`SoccerGame` (root, `scenes/soccer_game.gd`) is itself a screen state machine over `ScreenType {MAIN_MENU, TEAM_SELECTION, TOURNAMENT, IN_GAME}`. `Screen` (base) carries a `screen_transition_requested` signal and a `ScreenData` payload (carries a `tournament` reference); `ScreenFactory` builds fresh instances. `WorldScreen` is the in-game screen and kicks off `GameManager.start_game()`. After game over, it advances the tournament bracket or returns to the main menu.

### Autoloads (singletons, see `project.godot` `[autoload]`)

| Name | File | Role |
|------|------|------|
| `DataLoader` | `utils/data_loader.gd` | Loads `res://assets/json/squads.json` once at `_init()`. Holds `countries` (9 total: DEFAULT + 8 real) and `squads` (country → `[PlayerResource]`, 11 players each). |
| `GameEvents` | `scenes/screens/world/game_events.gd` | **Global signal bus** — the decoupling layer. Signals: `ball_possessed`, `ball_possessed_by(player)`, `ball_released`, `game_over`, `kickoff_ready`, `kickoff_started`, `impact_received`, `score_changed`, `team_reset`, `team_scored`, `possession_changed(country)`, `offside_called(offender, pos)`, `halftime_started`, `second_half_started`. Prefer emitting/connecting here over direct cross-node references. |
| `GameManager` | `scenes/game_manager/game_manager.gd` | Owns `current_match` (`Match`), `player_setup` (2 country strings), the game state machine, match timer, hitstop (impact pause), and possession tracking. `process_mode = ALWAYS` so it can unpause the tree. |
| `InputBuffer` | `utils/input_buffer.gd` | 200ms input buffer; `press(action)`, `consume(action)`, `consume_any(actions)`, `has(action)`, `clear()`. Lets buffered inputs trigger actions on state transitions. |
| `SoundPlayer` | `scenes/audio/sound_player.gd` | SFX via a pool of 4 `AudioStreamPlayer`s. `SoundPlayer.play(SoundPlayer.Sound.X)`. Sounds: `BOUNCE, HURT, PASS, POWERSHOT, SAVE, SHOT, TACKLING, UI_NAV, UI_SELECT, WHISTLE`. |
| `MusicPlayer` | `scenes/audio/music_player.gd` | Per-screen music; `Screen._enter_tree()` calls `MusicPlayer.play_music(music)`. |

### Game states

`GameManager.State { FIRST_HALF, SECOND_HALF, HALFTIME, SCORED, RESET, KICKOFF, OVERTIME, GAMEOVER }` — 8 states total.

- **FIRST_HALF / SECOND_HALF** — countdown timer, score → SCORED, time up → HALFTIME (first) or OVERTIME/GAMEOVER (second, based on tie)
- **HALFTIME** — 3s pause, swaps sides via `ActorsContainer.swap_sides()`, transitions to RESET
- **SCORED** — 3s celebration, increments score, → RESET
- **RESET** — emits `team_reset`, waits for `kickoff_ready`, → KICKOFF
- **KICKOFF** — waits for pass input from the kicking team, emits `kickoff_started`, → FIRST_HALF or SECOND_HALF
- **OVERTIME** — golden goal (any score → GAMEOVER)
- **GAMEOVER** — emits `game_over`

Match length: **1 min per half = 2 min total** (`DURATION_HALF_SEC := 60`).

### Match & tournament

- `Match` (`scenes/screens/tournament/match.gd`) — tracks home/away countries, goals, winner, final score. `increase_score(country_scored_on)` increments the *opposite* side. CPU-only matches `resolve()` with random scores.
- `Tournament` (`scenes/screens/tournament/tournament.gd`) — 8-country single-elim bracket from `countries.slice(1, 9)`: `QUARTER_FINALS → SEMI_FINALS → FINAL → COMPLETE`. `advance()` resolves the current stage and seeds the next from winners.
- `ActorsContainer` (`scenes/screens/world/actors_container.gd`) — spawns both **11-player** squads (4-3-3: 1 GK + 4 DEF + 3 MID + 3 FWD) from `DataLoader`, wires goals/control schemes. Runs CPU "on-duty" steering weights, **auto-swap on possession** (when teammate gains ball), and **defense auto-swap** (closest player to ball, with cooldown + distance threshold). Handles side swapping at halftime, offside checks via `OffsideJudge`, and intercept resolution via `InterceptResolver`.

### Possession tracking

Built into `GameManager` — tracks `possession_home` / `possession_away` (cumulative seconds), `possession_country`, and `possession_last_switch_ms`. `get_possession_ratio(country)` returns 0.0–1.0. Reset at halftime. Updates on `ball_possessed_by` / `ball_released` signals.

### Players & ball

- **`Player`** (CharacterBody2D): **11 per squad** — 1 `GOALIE` + 10 outfield across `DEFENSE/MIDFIELD/OFFENSE` (4-3-3). `ControlScheme {CPU, P1, P2}`. `SkinColor` and team color applied via palette shader. 7 stat attributes: `speed, power, technique, shooting, defense, jump, stamina`. Has `height`/`height_velocity` for jump/air physics. Emits `swap_requested`.
  - **15 states**: MOVING, TACKLING, SHOOTING, **PREPPING_SHOT**, PASSING, HEADER, VOLLEY_KICK, BICYCLE_KICK, **CHEST_CONTROL**, **DIVING** (goalie), **HURT**, **RECOVERING**, **RESETING**, CELEBRATING, MOURNING.
  - **AI** delegated to `AIBehavior` (field vs goalie) built by `AIBehaviorFactory`. Field AI has carrier steering, assist formation, offensive support runs (per-role), pass-quality scoring, tackle decisions. Goalie AI has goal-line positioning, rush-out, catch, diving save, and distribution (throw/kick).
  - **Pass types**: `PlayerStateData.PassType {SHORT, LONG, THROUGH}`.

- **`Ball`** (AnimatableBody2D): **7 states** — CARRIED, FREEFORM, KICKED, SHOT, SAVED, DEFLECTED, HELD_BY_GOALKEEPER. Custom `height`/`height_velocity` for 2.5D bounce; sprite offset `Vector2.UP * height`. Three pass methods: `short_pass()`, `long_pass()` (arcing), `through_pass()` (ground penetrating). Goalkeeper interactions: `save_by()`, `deflect_by()`, `hold_by_goalkeeper()`, `release_with_throw()`, `release_with_kick()`, `place_at()`. Trajectory prediction APIs: `predict_landing_time()`, `predict_landing_position()`, `predict_position_at_time()`, `predict_height_at_time()`, `can_air_connect()`. `tumble()` for tackle knockaways. `player_proximity_area` for nearby teammate counting.

- **Hitstop**: high-impact collisions `emit impact_received(pos, true)` → `GameManager` pauses the tree for `DURATION_IMPACT_PAUSE` (100ms), then unpauses in `_process`.

### Goal

`Goal` (Node2D): has `back_net_area` (stops ball), `scoring_area` (triggers score via `team_scored`), and a `Targets` node with multiple target positions (`get_random/center/top/bottom_target_position()`). Used by shooting/passing AI and keeper positioning.

### UI

`UI` (`scenes/ui/ui.gd`): score with flags, timer, half indicator, player name label, goal scorer animation, game over animation, radar minimap. Uses `ScoreHelper` and `TimeHelper` utilities.

`RadarMinimap` (`scenes/ui/radar_minimap.gd`): custom-drawn minimap (extends `Control`). Shows all players (home=yellow, away=red), ball (white), pitch outline. Human-controlled players get a white ring. Updates every 3 frames. Optional offside line display. Pitch size: `850 × 360`.

### Offside system

`OffsideJudge` (static utility): `check_offside_at_pass()` checks if a pass target is beyond the second-last defender (2px tolerance, ball position reference). `ActorsContainer.check_pass_offside()` integrates it; `offside_called` signal emitted on `GameEvents`. Radar minimap can show the offside line.

### Intercept system

`InterceptResolver` (static utility): `check_auto_intercept()` determines if a defender can intercept a pass/dribble. Uses defender `defense` stat vs dribbler `technique` stat. `find_best_interceptor()` scans nearby defenders.

### Rendering: palette shader

`shaders/replace_color.gdshader` swaps pixel colors from two palette textures (`skin_palette`, `team_palette`) — one sprite serves all skin tones and all team colors. `team_color` is the country's index in `DataLoader.countries`. When adding teams/players, keep palette indices consistent.

## Testing

Test scenes live in `tools/`. Run from editor or CLI:

| File | What it tests |
|------|---------------|
| `test_runner.gd` | Smoke test — loads all 4 screens, runs each 1s, checks for crashes |
| `test_automated.gd` | Automated game — creates match, simulates kickoff, runs 30s |
| `test_gameplay.gd` | Gameplay flow — main menu → team selection → match, 15s gameplay |
| `test_full_game.gd` | Full match — kickoff → 60s first half → halftime → 60s second half |
| `test_runtime.gd` | Runtime error detection — 60s match with state/player/ball checks at 10s/30s/60s |

## Conventions

- **GDScript style**: `class_name` PascalCase at top of file. Variables/functions `snake_case`. Constants and enum members `UPPER_SNAKE_CASE`. Types use `:=` inference or explicit `: Type`.
- **Node access**: `%UniqueNodeName` (`@onready`) for scene-internal refs; `@export` for editor-wired dependencies (ball, goals, control scheme).
- **Files**: each script gets its own `.gd` + an auto-generated `.gd.uid` (Godot 4 UID). Never hand-edit `.uid`/`.import` files.
- **Communication**: prefer the `GameEvents` bus and the `state_transition_requested`/`setup` pattern over ad-hoc `get_node()`/signal wiring. Context is passed *into* states via `setup(...)`, not read from the parent tree.
- **Assets**: `res://assets/{art,sfx,music,fonts,json}/`. Squads data is `assets/json/squads.json` (array of `{country, players:[{name, skin, role, speed, power, technique, shooting, defense, jump, stamina, number}]}` × 11 players per team in 4-3-3 formation: GK + 4 DEF + 3 MID + 3 FWD, indices map to `Player.SkinColor`/`Player.Role` enums). Flags: `assets/art/ui/flags/flag-<COUNTRY_LOWER>.png`, cached by `FlagHelper`.
- **Physics layers** (see `[layer_names]`): `PitchWalls`, `Player`, `Ball`, `InvisibleWalls`, `ScoringArea`, `GoalKeeperHands`.
- **Input map** (`project.godot` `[input]`): P1 = arrow keys + `[` (short pass) / `]` (shoot) / `'` (long pass) / `\` (through pass) / RShift (sprint) / RCtrl (special). P2 = WASD + `0` (short pass) / `1` (shoot) / `2` (long pass) / `3` (through pass) / Shift (sprint) / Q (special). Game modes: single-player (P2 empty), versus, co-op (both pick the same country).
- **Input abstraction**: `KeyUtils` provides `Action {LEFT, RIGHT, UP, DOWN, SHOOT, SHORT_PASS, LONG_PASS, THROUGH_PASS, SPRINT, SPECIAL}` and methods like `is_action_just_pressed(control_scheme, action)` — use this instead of raw `Input.is_action_just_pressed()`.

## When making changes

- Adding a new **state**: create the `*State` subclass, register `Enum → Class` in the matching `*StateFactory._init()`, add the enum value to the owner's `State` enum. If it needs payload, extend the `*StateData` builder.
- Adding a **screen**: add to `SoccerGame.ScreenType` + `ScreenFactory`, extend `Screen`, set its `music` export.
- Adding a **team/country**: add to `squads.json` (11 players, 4-3-3 formation), drop a `flag-<name>.png`, and note that `Tournament` slices `countries[1..9]` (index 0 is `"DEFAULT"` placeholder) — keep 8 real teams after DEFAULT for the bracket.
- Adding a **sound**: add to `SoundPlayer.Sound` enum and `SFX_MAP`.
- Adding an **input action**: add to `KeyUtils.Action` enum, add the P1/P2 action strings to `project.godot` `[input]`, and add mapping in `KeyUtils`.
- Keep the viewport/scaling and nearest-filter settings intact — they define the pixel-art look.
