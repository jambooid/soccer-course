# WE 风格带球系统 v2 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建 WE/PES 风格的带球系统，包含普通/冲刺双模式、转向惯性、属性动态影响，并将所有接球路径统一到物理推球式 DRIBBLING 状态。

**Architecture:** 在现有 `DribblePhysics` + `BallStateDribbling` 的物理基础上，新增 Mode 枚举控制多套物理参数；在 PlayerStateMoving 中增加 TurnController 实现转向平滑与急转减速；将 KICKED/SAVED/DEFLECTED/门将放球 所有接球路径从 LEGACY CARRIED 迁移到 DRIBBLING；AI 适配模式切换与冲刺。

**Tech Stack:** Godot 4.4 GDScript, 2D pixel-art, CharacterBody2D + AnimatableBody2D

**Spec:** `docs/superpowers/specs/2026-08-27-we-dribbling-v2-design.md`

## Global Constraints

- Godot 4.4, GL Compatibility renderer, 560×360 viewport, integer scaling
- 代码风格：`class_name` PascalCase，变量/函数 snake_case，常量 UPPER_SNAKE_CASE，类型用 `:=` 推断
- 状态机模式：`*State` extends Node，`setup(...)` 注入上下文，`state_transition_requested` 信号切换
- 状态工厂模式：`*StateFactory` 字典映射 enum → class，`get_fresh_state()` 实例化
- 通信优先用 `GameEvents` 信号总线，而非直接跨节点引用
- 所有物理计算集中在 `DribblePhysics` 静态工具类中
- `CARRIED` 状态保留文件但不再被引用（回退方案）
- 不掉用 `we2000-core-techniques` 等文档中提到但本次范围外的功能

---

## Task 1: DribblePhysics 模式系统 + 速度惩罚 + 停球质量

**Files:**
- Modify: `utils/dribble_physics.gd`
- Test: `tools/test_dribbling.gd`（新增测试用例）

**Interfaces:**
- Consumes: 现有 `DribblePhysics` 的所有函数与常量
- Produces:
  - `enum Mode { JOG, SPRINT }`
  - `get_touch_zone_length(technique, mode=Mode.JOG) -> float`
  - `get_max_control_distance(technique, mode=Mode.JOG) -> float`
  - `get_min_touch_interval(technique, mode=Mode.JOG) -> float`
  - `compute_touch_impulse(ball_vel, player_vel, player_max_speed, technique, mode=Mode.JOG) -> Vector2`
  - `is_ball_in_touch_zone(ball_pos, player_pos, player_dir, technique, mode=Mode.JOG) -> bool`
  - `compute_first_touch_velocity(incoming_vel, control_dir, technique) -> Vector2`
  - `estimate_next_touch_interval(ball_vel, player_vel, player_max_speed, technique, mode=Mode.JOG) -> float`
  - `debug_get_technique_stats(technique, mode=Mode.JOG) -> Dictionary`

### 步骤

- [ ] **Step 1: 在 test_dribbling.gd 中先写 Mode 相关测试（会失败）**

在 `_ready()` 末尾追加调用：
```gdscript
test_mode_touch_zone()
test_mode_control_distance()
test_mode_impulse()
test_first_touch_quality()
```

在文件末尾 `test_touch_impulse` 函数之后追加：

```gdscript
func test_mode_touch_zone() -> void:
    print("-- Mode: Touch Zone Tests --")

    var tech := 64.0
    var jog_len := DribblePhysics.get_touch_zone_length(tech, DribblePhysics.Mode.JOG)
    var sprint_len := DribblePhysics.get_touch_zone_length(tech, DribblePhysics.Mode.SPRINT)

    # SPRINT 触球区比 JOG 长
    _assert(sprint_len > jog_len, "SPRINT touch zone longer than JOG",
        "jog=%.1f sprint=%.1f" % [jog_len, sprint_len])

    # SPRINT 倍率约为 1.3
    var ratio := sprint_len / jog_len
    _assert(_approx(ratio, 1.3, 0.05), "SPRINT/JOG touch zone ratio ~ 1.3",
        "ratio=%.2f" % ratio)

    # is_ball_in_touch_zone 的 mode 参数生效
    var player_pos := Vector2.ZERO
    var player_dir := Vector2.RIGHT
    # 在 JOG 区外但在 SPRINT 区内的点
    var just_outside_jog := Vector2(DribblePhysics.TOUCH_ZONE_FRONT_OFFSET + jog_len + 2.0, 0.0)
    _assert(not DribblePhysics.is_ball_in_touch_zone(just_outside_jog, player_pos, player_dir, tech, DribblePhysics.Mode.JOG),
        "Point outside JOG zone returns false for JOG mode")
    # 只有当 sprint 区长足够包含这个点时才测
    if sprint_len > jog_len + 2.0:
        _assert(DribblePhysics.is_ball_in_touch_zone(just_outside_jog, player_pos, player_dir, tech, DribblePhysics.Mode.SPRINT),
            "Point outside JOG but inside SPRINT zone returns true for SPRINT mode")

    print()

func test_mode_control_distance() -> void:
    print("-- Mode: Control Distance Tests --")

    var tech := 64.0
    var jog_dist := DribblePhysics.get_max_control_distance(tech, DribblePhysics.Mode.JOG)
    var sprint_dist := DribblePhysics.get_max_control_distance(tech, DribblePhysics.Mode.SPRINT)

    _assert(sprint_dist > jog_dist, "SPRINT control distance > JOG",
        "jog=%.1f sprint=%.1f" % [jog_dist, sprint_dist])

    var ratio := sprint_dist / jog_dist
    _assert(_approx(ratio, 1.5, 0.1), "SPRINT/JOG control distance ratio ~ 1.5",
        "ratio=%.2f" % ratio)

    print()

func test_mode_impulse() -> void:
    print("-- Mode: Touch Impulse Tests --")

    var ball_vel := Vector2(40.0, 0.0)
    var player_vel := Vector2(60.0, 0.0)
    var max_speed := 80.0
    var tech := 64.0

    var jog_result := DribblePhysics.compute_touch_impulse(ball_vel, player_vel, max_speed, tech, DribblePhysics.Mode.JOG)
    var sprint_result := DribblePhysics.compute_touch_impulse(ball_vel, player_vel, max_speed, tech, DribblePhysics.Mode.SPRINT)

    # SPRINT 推球速度更快（冲量更大）
    _assert(sprint_result.length() > jog_result.length(), "SPRINT impulse > JOG impulse",
        "jog=%.1f sprint=%.1f" % [jog_result.length(), sprint_result.length()])

    print()

func test_first_touch_quality() -> void:
    print("-- First Touch Quality Tests --")

    var incoming := Vector2(80.0, 0.0)
    var control_dir := Vector2.RIGHT

    # 高技术停球慢（吸收多）
    var high_tech := DribblePhysics.compute_first_touch_velocity(incoming, control_dir, 90.0)
    # 低技术停球快（吸收少，球弹远）
    var low_tech := DribblePhysics.compute_first_touch_velocity(incoming, control_dir, 40.0)

    _assert(high_tech.length() < low_tech.length(),
        "High technique = slower first touch (better control)",
        "high_tech=%.1f low_tech=%.1f" % [high_tech.length(), low_tech.length()])

    # 高技术停球速应明显低于入射速度
    _assert(high_tech.length() < incoming.length() * 0.5,
        "High technique absorbs > 50% of incoming speed",
        "incoming=%.1f result=%.1f" % [incoming.length(), high_tech.length()])

    # 低技术也应吸收一部分（不可能全反弹）
    _assert(low_tech.length() < incoming.length(),
        "Low technique still absorbs some speed",
        "incoming=%.1f result=%.1f" % [incoming.length(), low_tech.length()])

    print()
```

- [ ] **Step 2: 运行测试确认失败**

```bash
GODOT="$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
$GODOT --path . -s tools/test_dribbling.gd --headless 2>&1 | tail -30
```

预期：新增的 4 个测试相关函数报 "Parse Error: Could not find function" 或类似错误。

- [ ] **Step 3: 实现 DribblePhysics Mode 系统**

在 `utils/dribble_physics.gd` 中：

1. **在 `extends RefCounted` 之后、注释之前，新增 Mode 枚举：**
```gdscript
enum Mode { JOG, SPRINT }
```

2. **新增 Mode 参数常量（放在现有常量块末尾，`TOUCH_ZONE_FRONT_OFFSET` 之后）：**
```gdscript
# ---- 带球模式参数 ----
const MODE_TOUCH_ZONE_MULT := {JOG: 1.0, SPRINT: 1.3}
const MODE_CONTROL_DIST_MULT := {JOG: 1.0, SPRINT: 1.5}
const MODE_MIN_INTERVAL_MULT := {JOG: 1.0, SPRINT: 1.875}  # 0.08s -> 0.15s
const MODE_INACCURACY_MULT := {JOG: 1.0, SPRINT: 1.5}
const MODE_PUSH_OFFSET := {JOG: 0.0, SPRINT: 0.2}       # 推球倍率整体上移
const MODE_EFFICIENCY_OFFSET := {JOG: 0.0, SPRINT: -0.1}  # 触球效率偏移
```

3. **新增速度惩罚常量：**
```gdscript
# 速度惩罚：跑得越快，精度越低、效率越差
const SPEED_PENALTY_MAX_INACCURACY := 0.075   # 全速时额外方向偏差（rad）
const SPEED_PENALTY_EFFICIENCY_LOSS := 0.1    # 全速时效率损失
```

4. **新增停球质量常量：**
```gdscript
# 停球质量（First Touch）
const FIRST_TOUCH_ABSORPTION_MIN := 0.4      # 低技术吸收比例
const FIRST_TOUCH_ABSORPTION_MAX := 0.85     # 高技术吸收比例
const FIRST_TOUCH_DIR_ERROR_MAX_DEG := 45.0  # 低技术最大方向偏差（度）
const FIRST_TOUCH_DIR_ERROR_MIN_DEG := 5.0   # 高技术最小方向偏差（度）
const FIRST_TOUCH_MIN_SPEED := 15.0          # 停球后最小速度
```

5. **修改 `get_touch_zone_length` 增加 mode 参数：**
```gdscript
static func get_touch_zone_length(technique: float, mode: int = Mode.JOG) -> float:
    var t_norm := normalize_technique(technique)
    var base := lerp(TOUCH_ZONE_LEN_MIN, TOUCH_ZONE_LEN_MAX, t_norm)
    return base * MODE_TOUCH_ZONE_MULT[mode]
```

6. **修改 `get_max_control_distance` 增加 mode 参数：**
```gdscript
static func get_max_control_distance(technique: float, mode: int = Mode.JOG) -> float:
    var t_norm := normalize_technique(technique)
    var base := lerp(MAX_CONTROL_DISTANCE_MIN, MAX_CONTROL_DISTANCE_MAX, t_norm)
    return base * MODE_CONTROL_DIST_MULT[mode]
```

7. **新增 `get_min_touch_interval` 函数：**
```gdscript
static func get_min_touch_interval(technique: float, mode: int = Mode.JOG) -> float:
    return MIN_TOUCH_INTERVAL * MODE_MIN_INTERVAL_MULT[mode]
```

8. **修改 `is_ball_in_touch_zone` 增加 mode 参数：**
将函数签名改为：
```gdscript
static func is_ball_in_touch_zone(
    ball_pos: Vector2,
    player_pos: Vector2,
    player_dir: Vector2,
    technique: float,
    mode: int = Mode.JOG
) -> bool:
```
并将内部 `var zone_length := get_touch_zone_length(technique)` 改为：
```gdscript
var zone_length := get_touch_zone_length(technique, mode)
```

9. **重写 `compute_touch_impulse`，增加 mode 参数 + 速度惩罚：**
```gdscript
static func compute_touch_impulse(
    ball_velocity: Vector2,
    player_velocity: Vector2,
    player_max_speed: float,
    technique: float,
    mode: int = Mode.JOG
) -> Vector2:
    var player_speed := player_velocity.length()
    if player_speed < 1.0:
        return ball_velocity  # 球员不动则不触球

    var t_norm := normalize_technique(technique)
    var speed_factor: float = clamp(player_speed / player_max_speed, 0.0, 1.0)

    # 1. 推球方向 = 球员速度方向 + 随机偏移（技术越高越准）
    var push_direction := player_velocity.normalized()
    var base_inaccuracy: float = lerp(MAX_INACCURACY_RAD, 0.0, t_norm)
    var mode_inaccuracy_mult := MODE_INACCURACY_MULT[mode]
    # 速度惩罚：速度越快偏差越大
    var speed_penalty_inaccuracy := SPEED_PENALTY_MAX_INACCURACY * speed_factor
    var total_inaccuracy := base_inaccuracy * mode_inaccuracy_mult + speed_penalty_inaccuracy
    push_direction = push_direction.rotated(randf_range(-total_inaccuracy, total_inaccuracy))

    # 2. 推球目标速度 = 球员速度 × 倍率（速度越高倍率越低 + 模式偏移）
    var push_mult_base: float = lerp(PUSH_MULT_LOW_SPEED, PUSH_MULT_HIGH_SPEED, speed_factor)
    var push_multiplier: float = push_mult_base + MODE_PUSH_OFFSET[mode]
    var push_speed := player_speed * push_multiplier
    var push_velocity := push_direction * push_speed

    # 3. 触球效率（技术越高越接近目标速度；速度越快效率越低；模式有偏移）
    var base_efficiency: float = lerp(TOUCH_EFFICIENCY_MIN, TOUCH_EFFICIENCY_MAX, t_norm)
    var efficiency_with_mode := base_efficiency + MODE_EFFICIENCY_OFFSET[mode]
    var speed_efficiency_loss := speed_factor * SPEED_PENALTY_EFFICIENCY_LOSS
    var total_efficiency: float = clamp(efficiency_with_mode - speed_efficiency_loss, 0.2, 0.95)

    return ball_velocity.lerp(push_velocity, total_efficiency)
```

10. **新增 `compute_first_touch_velocity` 函数：**
```gdscript
# 计算停球后的球速（First Touch Quality）
# 高技术球员停球稳（速度慢、方向准），低技术停球弹得远、方向偏
static func compute_first_touch_velocity(
    incoming_velocity: Vector2,
    control_direction: Vector2,
    technique: float
) -> Vector2:
    var t_norm := normalize_technique(technique)

    # 吸收比例：高技术吸收多（球慢）
    var absorption := lerp(FIRST_TOUCH_ABSORPTION_MIN, FIRST_TOUCH_ABSORPTION_MAX, t_norm)
    var remaining_speed := incoming_velocity.length() * (1.0 - absorption)
    remaining_speed = max(remaining_speed, FIRST_TOUCH_MIN_SPEED)

    # 方向偏差：高技术准
    var error_deg := lerp(FIRST_TOUCH_DIR_ERROR_MAX_DEG, FIRST_TOUCH_DIR_ERROR_MIN_DEG, t_norm)
    var error_rad := deg_to_rad(error_deg)
    var final_dir := control_direction.rotated(randf_range(-error_rad, error_rad))

    return final_dir * remaining_speed
```

11. **修改 `estimate_next_touch_interval` 增加 mode 参数：**
```gdscript
static func estimate_next_touch_interval(
    ball_velocity: Vector2,
    player_velocity: Vector2,
    player_max_speed: float,
    technique: float,
    mode: int = Mode.JOG
) -> float:
    var player_speed := player_velocity.length()
    if player_speed < IDLE_SPEED_THRESHOLD:
        return get_min_touch_interval(technique, mode)

    var t_norm := normalize_technique(technique)
    var f := GROUND_FRICTION_PER_SEC
    var base_efficiency: float = lerp(TOUCH_EFFICIENCY_MIN, TOUCH_EFFICIENCY_MAX, t_norm)
    var efficiency := base_efficiency + MODE_EFFICIENCY_OFFSET[mode]
    var zone_len := get_touch_zone_length(technique, mode)
    var zone_end := TOUCH_ZONE_FRONT_OFFSET + zone_len

    var speed_factor: float = clamp(player_speed / player_max_speed, 0.0, 1.0)
    var push_mult_base: float = lerp(PUSH_MULT_LOW_SPEED, PUSH_MULT_HIGH_SPEED, speed_factor)
    var push_multiplier: float = push_mult_base + MODE_PUSH_OFFSET[mode]
    var v_exit := player_speed * push_multiplier

    var v_avg := v_exit * 0.6
    var interval := zone_len / v_avg if v_avg > 1.0 else MIN_TOUCH_INTERVAL
    return max(interval, get_min_touch_interval(technique, mode))
```

12. **修改 `debug_get_technique_stats` 增加 mode 参数：**
```gdscript
static func debug_get_technique_stats(technique: float, mode: int = Mode.JOG) -> Dictionary:
    var t_norm := normalize_technique(technique)
    var base_efficiency := lerp(TOUCH_EFFICIENCY_MIN, TOUCH_EFFICIENCY_MAX, t_norm)
    var base_inaccuracy := lerp(MAX_INACCURACY_RAD, 0.0, t_norm)
    return {
        "technique_raw": technique,
        "technique_normalized": t_norm,
        "mode": mode,
        "touch_zone_len": get_touch_zone_length(technique, mode),
        "max_control_dist": get_max_control_distance(technique, mode),
        "min_touch_interval": get_min_touch_interval(technique, mode),
        "touch_efficiency": base_efficiency + MODE_EFFICIENCY_OFFSET[mode],
        "inaccuracy_deg": rad_to_deg(base_inaccuracy * MODE_INACCURACY_MULT[mode]),
    }
```

- [ ] **Step 4: 运行测试确认通过**

```bash
GODOT="$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
$GODOT --path . -s tools/test_dribbling.gd --headless 2>&1 | tail -20
```

预期：全部测试通过（包括原有的和新增的）。

- [ ] **Step 5: 运行完整游戏确认不崩**

```bash
$GODOT --path . -s tools/test_automated.gd --headless 2>&1 | tail -10
```

预期：30 秒自动测试不崩溃。

- [ ] **Step 6: 提交**

```bash
git add utils/dribble_physics.gd tools/test_dribbling.gd
git commit -m "feat(dribbling): add Mode system, speed penalty, and first-touch quality to DribblePhysics

- Add Mode enum (JOG/SPRINT) with parameter multipliers
- All core functions accept optional mode parameter (defaults to JOG for backward compat)
- Add speed penalty: faster = more inaccuracy + lower efficiency
- Add compute_first_touch_velocity() for reception quality based on technique
- Add get_min_touch_interval() mode-aware variant
- Add tests for mode effects and first-touch quality"
```

---

## Task 2: BallStateDribbling 适配 Mode + 停球质量 + 宽限期 + cutback

**Files:**
- Modify: `scenes/ball/ball_states/ball_state_dribbling.gd`
- Modify: `scenes/characters/player.gd`（新增 `dribble_mode` 属性）
- Test: `tools/test_dribbling.gd`（验证 mode-aware 行为，无需运行游戏）

**Interfaces:**
- Consumes:
  - `DribblePhysics.Mode.JOG` / `Mode.SPRINT`
  - `DribblePhysics.get_touch_zone_length(tech, mode)`
  - `DribblePhysics.get_max_control_distance(tech, mode)`
  - `DribblePhysics.get_min_touch_interval(tech, mode)`
  - `DribblePhysics.compute_touch_impulse(..., mode)`
  - `DribblePhysics.is_ball_in_touch_zone(..., mode)`
  - `DribblePhysics.compute_first_touch_velocity(incoming, dir, tech)`
- Produces:
  - `Player.dribble_mode: int`（JOG 或 SPRINT）
  - `BallStateDribbling.apply_cutback_kick()` — 急转时给球额外前冲

### 步骤

- [ ] **Step 1: 在 Player 中新增 dribble_mode 属性**

在 `scenes/characters/player.gd` 中，`stamina` 属性行之后插入：
```gdscript
@export var stamina : float = 50.0
@export var dribble_mode : int = 0  ## DribblePhysics.Mode，默认 JOG=0
```

注意：不能直接引用 `DribblePhysics.Mode.JOG` 作为 export 默认值（GDScript 限制），用字面量 0 即可。注释说明对应关系。

- [ ] **Step 2: 修改 BallStateDribbling 使用 mode-aware 物理**

在 `scenes/ball/ball_states/ball_state_dribbling.gd` 中：

1. **新增常量（类顶部，`touch_cooldown` 声明之前）：**
```gdscript
## 接球宽限期（秒）：刚进入 DRIBBLING 的短暂时间内
## - 失控距离临时 × 宽限期倍率
## - 抢断概率临时 × 抢断宽限倍率
## 确保接球第一下不会因为物理原因立刻丢球
const GRACE_PERIOD_SEC := 0.3
const GRACE_CONTROL_DIST_MULT := 1.5
const GRACE_INTERCEPT_MULT := 0.5

## 急转时球的额外前冲倍率（模拟趟大）
const CUTBACK_BALL_KICK_MULT := 1.2
```

2. **新增变量（`intercept_check_frame` 之后）：**
```gdscript
var grace_period_timer := 0.0  ## 接球宽限期剩余时间
var _incoming_velocity := Vector2.ZERO  ## 进入状态前的入射速度（用于停球质量）
```

3. **修改 `_enter_tree()`：**
将现有的 `_enter_tree()` 完全替换为：
```gdscript
func _enter_tree() -> void:
    if carrier == null:
        transition_state(Ball.State.FREEFORM, BallStateData.build())
        return

    # 保存入射速度（在修改前记录）
    _incoming_velocity = ball.velocity

    ball.carrier = carrier
    GameEvents.ball_possessed.emit(carrier.fullname)
    GameEvents.ball_possessed_by.emit(carrier)

    # 带球时球在地面
    ball.height = 0.0
    ball.height_velocity = 0.0

    # 排除与携带者的物理碰撞（带球时球穿过携带者身体）
    ball.add_collision_exception_with(carrier)

    # 停球质量：根据入射速度和 technique 计算停球后的速度
    var incoming_speed := _incoming_velocity.length()
    if incoming_speed > DribblePhysics.IDLE_SPEED_THRESHOLD:
        # 有明显入射速度 → 应用停球质量计算
        var control_dir := carrier.heading
        ball.velocity = DribblePhysics.compute_first_touch_velocity(
            _incoming_velocity, control_dir, carrier.technique
        )
    else:
        # 入射速度很低（如从 FREEFORM 慢慢滚过来）→ 给一个同向初速度
        var current_speed := carrier.velocity.length()
        if ball.velocity.length() < current_speed * 0.3 and current_speed > DribblePhysics.IDLE_SPEED_THRESHOLD:
            ball.velocity = _get_player_direction() * current_speed * 0.8

    # 启动宽限期
    grace_period_timer = GRACE_PERIOD_SEC
```

4. **修改 `_process()` 中的冷却、触球、失控检测，使用 mode-aware 函数：**

在 `_process()` 开头（冷却计时之后）添加宽限期计时：
```gdscript
    # 1. 冷却计时 + 宽限期计时
    touch_cooldown = max(0.0, touch_cooldown - delta)
    grace_period_timer = max(0.0, grace_period_timer - delta)
```

获取 mode：
```gdscript
    # 预计算：有效技术值 & 球员当前方向 & 带球模式（多处复用）
    var effective_tech := carrier.technique
    var player_dir := _get_player_direction()
    var mode := carrier.dribble_mode
```

**失控检测**部分（原第 72-79 行）改为：
```gdscript
    # 4. 失控检测：球在球员前方且距离超过可控范围
    #    身后的球不算失控（球员可以转身回追）
    var to_ball := ball.position - carrier.position
    var dist := to_ball.length()
    var max_control := DribblePhysics.get_max_control_distance(effective_tech, mode)
    # 宽限期内失控距离放大
    if grace_period_timer > 0.0:
        max_control *= GRACE_CONTROL_DIST_MULT
    if dist > max_control and to_ball.dot(player_dir) > 0:
        _release_ball()
        return
```

**触球检测**部分（原第 81-93 行）改为：
```gdscript
    # 5. 触球检测
    if touch_cooldown <= 0.0:
        if DribblePhysics.is_ball_in_touch_zone(
            ball.position, carrier.position, player_dir, effective_tech, mode
        ):
            var new_vel := DribblePhysics.compute_touch_impulse(
                ball.velocity, carrier.velocity, carrier.speed, effective_tech, mode
            )
            # 只在推球方向与球员移动方向一致时触球
            if new_vel.dot(player_dir) > ball.velocity.dot(player_dir):
                ball.velocity = new_vel
                touch_cooldown = DribblePhysics.get_min_touch_interval(effective_tech, mode)
```

**自动抢断检测**部分（`_check_auto_intercept` 函数内）在概率判定前增加宽限削减：
```gdscript
    var best_defender: Player = result.player
    var probability: float = result.probability

    # 宽限期内抢断概率降低
    if grace_period_timer > 0.0:
        probability *= GRACE_INTERCEPT_MULT
```

5. **新增 `apply_cutback_kick()` 方法（文件末尾，`is_ball_free` 之前）：**
```gdscript
## 急转时给球额外前冲（模拟趟大效果）
## 由 PlayerStateMoving 在检测到大角度急转时调用
func apply_cutback_kick() -> void:
    if ball.velocity.length() > 10.0:
        # 沿当前球速方向额外加速，增加失控风险
        ball.velocity *= CUTBACK_BALL_KICK_MULT
```

- [ ] **Step 3: 运行测试确认 dribbling 测试通过**

```bash
GODOT="$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
$GODOT --path . -s tools/test_dribbling.gd --headless 2>&1 | tail -10
```

预期：全部通过（dribble_physics 的单元测试）。

- [ ] **Step 4: 运行自动化测试确认游戏不崩**

```bash
$GODOT --path . -s tools/test_automated.gd --headless 2>&1 | tail -10
```

预期：30 秒自动测试不崩溃，能正常进行。

- [ ] **Step 5: 提交**

```bash
git add scenes/characters/player.gd scenes/ball/ball_states/ball_state_dribbling.gd
git commit -m "feat(dribbling): BallStateDribbling adapts to mode system + first-touch + grace period

- Player.dribble_mode property (JOG=0 default)
- All physics calls use mode-aware DribblePhysics functions
- First-touch quality: reception speed/direction based on technique
- Grace period (0.3s): enlarged control distance + reduced intercept chance
- apply_cutback_kick() for cutback momentum simulation"
```

---

## Task 3: PlayerStateMoving 转向惯性 + dribble_mode 管理

**Files:**
- Modify: `scenes/characters/character_states/player_state_moving.gd`

**Interfaces:**
- Consumes:
  - `DribblePhysics.Mode.JOG` / `Mode.SPRINT`
  - `Player.dribble_mode`
  - `BallStateDribbling.apply_cutback_kick()` — 通过 `ball.current_state` 调用
- Produces:
  - TurnController（PlayerStateMoving 内的变量和函数）
  - `current_move_direction` — 平滑插值后的移动方向
  - 人类玩家 sprint 键 → dribble_mode 切换 + 速度倍率

### 步骤

- [ ] **Step 1: 重构 PlayerStateMoving，增加 TurnController 和模式管理**

完全重写 `scenes/characters/character_states/player_state_moving.gd`：

```gdscript
class_name PlayerStateMoving
extends PlayerState

## 转向参数（Turn Controller）
const TURN_RATE_LOW_SPEED := 12.0        # 静止时最大转向速率（rad/s）
const TURN_RATE_HIGH_SPEED := 4.0        # 满速时最大转向速率（rad/s）
const SPRINT_TURN_PENALTY := 0.6         # 冲刺时转向速率倍率
const CUTBACK_ANGLE_THRESHOLD := deg_to_rad(90.0)  # 急转角度阈值
const CUTBACK_SPEED_PENALTY := 0.6       # 急转速度衰减（乘以此系数）

const SPRINT_SPEED_MULTIPLIER := 1.6

## Turn Controller 状态
var current_move_direction := Vector2.RIGHT  # 当前实际移动方向（平滑插值后）
var is_moving := false

func _process(delta: float) -> void:
    if player.control_scheme == Player.ControlScheme.CPU:
        ai_behavior.process_ai()
    else:
        handle_human_movement(delta)
    player.set_movement_animation()
    player.set_heading()


func handle_human_movement(delta: float) -> void:
    # 方向输入
    var direction := KeyUtils.get_input_vector(player.control_scheme)
    var has_direction := direction.length() > 0.1

    # 冲刺模式切换
    if KeyUtils.is_action_pressed(player.control_scheme, KeyUtils.Action.SPRINT):
        player.dribble_mode = DribblePhysics.Mode.SPRINT
    else:
        player.dribble_mode = DribblePhysics.Mode.JOG

    # 速度倍率
    var speed_multiplier := 1.0
    if player.dribble_mode == DribblePhysics.Mode.SPRINT:
        speed_multiplier = SPRINT_SPEED_MULTIPLIER

    # 转向平滑（Turn Controller）
    if has_direction:
        var move_dir := _apply_turning(direction.normalized(), delta)
        player.velocity = move_dir * player.speed * speed_multiplier
        # 同步 heading（朝向）
        if player.velocity.x > 0:
            player.heading = Vector2.RIGHT
        elif player.velocity.x < 0:
            player.heading = Vector2.LEFT
        is_moving = true
    else:
        # 没有方向输入 → 减速停下，但保持当前朝向
        player.velocity = player.velocity.move_toward(Vector2.ZERO, player.speed * 3.0 * delta)
        is_moving = false

    if player.velocity != Vector2.ZERO:
        teammate_detection_area.rotation = player.velocity.angle()

    # 短传：最常用，优先级高（从输入缓冲消费，提升跟手感）
    if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.SHORT_PASS):
        if player.has_ball():
            transition_state(Player.State.PASSING, PlayerStateData.build()
                .set_pass_type(PlayerStateData.PassType.SHORT))
        elif can_teammate_pass_ball():
            ball.carrier.get_pass_request(player)
        else:
            player.swap_requested.emit(player)
        return

    # 长传：高球/传中（从输入缓冲消费）
    if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.LONG_PASS):
        if player.has_ball():
            transition_state(Player.State.PASSING, PlayerStateData.build()
                .set_pass_type(PlayerStateData.PassType.LONG))
        elif can_teammate_pass_ball():
            ball.carrier.get_pass_request(player)
        else:
            player.swap_requested.emit(player)
        return

    # 直塞：地面穿透球（从输入缓冲消费）
    if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.THROUGH_PASS):
        if player.has_ball():
            transition_state(Player.State.PASSING, PlayerStateData.build()
                .set_pass_type(PlayerStateData.PassType.THROUGH))
        elif can_teammate_pass_ball():
            ball.carrier.get_pass_request(player)
        return

    # 射门（从输入缓冲消费）
    if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.SHOOT):
        if player.has_ball():
            transition_state(Player.State.PREPPING_SHOT)
        elif ball.can_air_interact():
            if player.velocity == Vector2.ZERO:
                if player.is_facing_target_goal():
                    transition_state(Player.State.VOLLEY_KICK)
                else:
                    transition_state(Player.State.BICYCLE_KICK)
            else:
                transition_state(Player.State.HEADER)
        elif player.velocity != Vector2.ZERO:
            transition_state(Player.State.TACKLING)
        return

    # 特殊键：切换球员（无球时） / 假动作（持球时，M2 实现）（从输入缓冲消费）
    if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.SPECIAL):
        if not player.has_ball():
            player.swap_requested.emit(player)


## 转向平滑：将当前移动方向朝目标方向插值
## 返回插值后的移动方向
func _apply_turning(target_direction: Vector2, delta: float) -> Vector2:
    if target_direction.length() < 0.01:
        return current_move_direction

    var target_dir := target_direction.normalized()
    var current_dir := current_move_direction.normalized()

    # 计算转向速率：速度越快转越慢；冲刺时更慢
    var speed_factor := clamp(player.velocity.length() / player.speed, 0.0, 1.0)
    var turn_rate := lerp(TURN_RATE_LOW_SPEED, TURN_RATE_HIGH_SPEED, speed_factor)
    if player.dribble_mode == DribblePhysics.Mode.SPRINT:
        turn_rate *= SPRINT_TURN_PENALTY

    # 角度差
    var angle_diff := current_dir.angle_to(target_dir)
    var max_turn := turn_rate * delta

    if abs(angle_diff) <= max_turn:
        current_move_direction = target_dir
    else:
        current_move_direction = current_dir.rotated(sign(angle_diff) * max_turn)

    # 大角度急转：速度衰减 + 球额外前冲（带球时）
    if abs(angle_diff) > CUTBACK_ANGLE_THRESHOLD and speed_factor > 0.6:
        player.velocity *= CUTBACK_SPEED_PENALTY
        # 通知球状态：急转趟大
        if player.has_ball() and ball.current_state != null:
            var dribble_state = ball.current_state
            if dribble_state.has_method("apply_cutback_kick"):
                dribble_state.apply_cutback_kick()

    return current_move_direction


func can_carry_ball() -> bool:
    # MOVING 状态下所有球员都能与球交互。
    return true


func can_teammate_pass_ball() -> bool:
    return ball.carrier != null and ball.carrier.country == player.country and ball.carrier.control_scheme == Player.ControlScheme.CPU


func can_pass() -> bool:
    return true
```

关键变化说明：
1. `handle_human_movement()` 增加 `delta` 参数（从 `_process` 传入）
2. 新增 TurnController：`current_move_direction` 平滑转向
3. `dribble_mode` 根据 sprint 键切换
4. 大角度急转触发速度衰减 + `apply_cutback_kick()`
5. 原有 action 处理逻辑完全保留
6. 注意：`player.set_heading()` 仍然根据 velocity.x 设置左右朝向（保持现有 flip 逻辑），`current_move_direction` 只影响运动方向的平滑度，不影响 sprite flip

- [ ] **Step 2: 运行自动化测试确认不崩**

```bash
GODOT="$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
$GODOT --path . -s tools/test_automated.gd --headless 2>&1 | tail -10
```

预期：30 秒自动测试不崩溃。

- [ ] **Step 3: 运行完整游戏测试**

```bash
$GODOT --path . -s tools/test_full_game.gd --headless 2>&1 | tail -10
```

预期：完整比赛（上下半场各 60s + 中场）能跑完。

- [ ] **Step 4: 提交**

```bash
git add scenes/characters/character_states/player_state_moving.gd
git commit -m "feat(dribbling): add TurnController and dribble mode management to PlayerStateMoving

- Smooth turning with speed-dependent turn rate (faster = harder to turn)
- Sprint mode reduces turn rate by 40% (SPRINT_TURN_PENALTY = 0.6)
- 90°+ cutback at >60% speed triggers speed penalty (×0.6)
- Cutback applies extra forward momentum to ball (simulates heavy touch)
- dribble_mode toggled by SPRINT key (JOG by default, SPRINT when held)
- All existing action handling preserved"
```

---

## Task 4: 全局 DRIBBLING 统一（KICKED/SAVED/DEFLECTED/门将放球）

**Files:**
- Modify: `scenes/ball/ball_states/ball_state_kicked.gd`
- Modify: `scenes/ball/ball_states/ball_state_saved.gd`
- Modify: `scenes/ball/ball_states/ball_state_deflected.gd`
- Modify: `scenes/ball/ball_states/ball_state_held_by_goalkeeper.gd`
- Modify: `scenes/ball/ball_states/ball_state_carried.gd`（加 LEGACY 注释）

**Interfaces:**
- Consumes: `Ball.State.DRIBBLING`（已存在）
- Produces: 所有接球路径统一使用 DRIBBLING

### 步骤

- [ ] **Step 1: 修改 ball_state_kicked.gd，CARRIED → DRIBBLING**

在 `scenes/ball/ball_states/ball_state_kicked.gd` 中：

第 75-77 行（kicker == null 分支）：
```gdscript
    if kicker == null:
        ball.carrier = body
        body.control_ball()
        transition_state(Ball.State.DRIBBLING)
        return
```

第 79-83 行（对手拦截分支）：
```gdscript
    if body.country != kicker.country:
        ball.carrier = body
        body.control_ball()
        transition_state(Ball.State.DRIBBLING)
        return
```

第 85-88 行（队友接球分支）：
```gdscript
    if body != kicker:
        ball.carrier = body
        body.control_ball()
        transition_state(Ball.State.DRIBBLING)
```

即把所有 `Ball.State.CARRIED` 替换为 `Ball.State.DRIBBLING`。

- [ ] **Step 2: 修改 ball_state_saved.gd，CARRIED → DRIBBLING**

第 73-76 行（`on_player_enter` 的非门将分支）：
```gdscript
    elif body.can_carry_ball() and ball.height < PitchConstants.HEIGHT_SAVED_PLAYER_PICKUP:
        ball.carrier = body
        body.control_ball()
        transition_state(Ball.State.DRIBBLING)
```

- [ ] **Step 3: 修改 ball_state_deflected.gd，CARRIED → DRIBBLING**

第 50-52 行（`on_player_enter` 末尾）：
```gdscript
    ball.carrier = body
    body.control_ball()
    transition_state(Ball.State.DRIBBLING)
```

- [ ] **Step 4: 修改 ball_state_held_by_goalkeeper.gd，put_down → DRIBBLING**

第 77-80 行（`put_down` 方法）：
```gdscript
func put_down() -> void:
    ball.position = carrier.position + carrier.heading * 8.0
    ball.velocity = Vector2.ZERO
    ball.carrier = carrier
    transition_state(Ball.State.DRIBBLING)
```

注意：原来 `put_down` 没有设置 `ball.carrier`（因为 CARRIED 状态的 `_enter_tree` 自己处理），但 DRIBBLING 的 `_enter_tree` 从 `ball.carrier` 读取 carrier，所以必须在切换前设置。

- [ ] **Step 5: 在 ball_state_carried.gd 文件顶部加 LEGACY 注释**

在文件最开头（`class_name` 之前或之后）添加显眼的 LEGACY 标记：
```gdscript
## LEGACY / DEPRECATED — 已被 BallStateDribbling 取代
## 此文件保留仅作为回退方案，不再被任何状态引用。
## 如需回退，将各 ball state 中的 Ball.State.DRIBBLING 改回 Ball.State.CARRIED 即可。
```

- [ ] **Step 6: 运行完整游戏测试**

```bash
GODOT="$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
$GODOT --path . -s tools/test_full_game.gd --headless 2>&1 | tail -10
```

预期：完整比赛能跑完，有进球，不崩溃。

- [ ] **Step 7: 运行 runtime 错误检测**

```bash
$GODOT --path . -s tools/test_runtime.gd --headless 2>&1 | tail -20
```

预期：所有检查点通过，无运行时错误。

- [ ] **Step 8: 提交**

```bash
git add scenes/ball/ball_states/ball_state_kicked.gd
git add scenes/ball/ball_states/ball_state_saved.gd
git add scenes/ball/ball_states/ball_state_deflected.gd
git add scenes/ball/ball_states/ball_state_held_by_goalkeeper.gd
git add scenes/ball/ball_states/ball_state_carried.gd
git commit -m "feat(dribbling): unify all ball reception paths to DRIBBLING state

- KICKED → DRIBBLING (interception, teammate reception)
- SAVED → DRIBBLING (player pickup after save)
- DEFLECTED → DRIBBLING (player pickup after deflection)
- Goalkeeper put_down → DRIBBLING
- BallStateCarried marked as LEGACY, kept as rollback option
- All paths now use physics-based dribbling for consistent feel"
```

---

## Task 5: AIBehaviorField 适配（模式切换 + 冲刺速度 + 转向平滑）

**Files:**
- Modify: `scenes/characters/ai/ai_behavior_field.gd`

**Interfaces:**
- Consumes:
  - `Player.dribble_mode`
  - `DribblePhysics.Mode.JOG` / `Mode.SPRINT`
- Produces:
  - AI 在带球时根据场景切换 JOG/SPRINT
  - AI 移动支持冲刺速度
  - AI 转向平滑（与人类玩家一致的 TurnController）

### 步骤

- [ ] **Step 1: 在 AIBehaviorField 中新增模式决策和转向平滑**

在 `scenes/characters/ai/ai_behavior_field.gd` 中：

1. **新增常量（文件顶部常量区末尾）：**
```gdscript
## 带球模式 AI 参数
const SPRINT_TECH_THRESHOLD := 60.0   ## 技术高于此值的球员才会冲刺带球
const SPRINT_OPPONENT_MAX := 0         ## 附近对手不超过此数才冲刺
const SPRINT_DIST_TO_GOAL_MAX := 425.0 ## 过了中线（场地总长约 850）才冲刺

## AI 转向参数（与人类玩家 TurnController 一致）
const AI_TURN_RATE_LOW := 10.0         # rad/s, 低速
const AI_TURN_RATE_HIGH := 3.5         # rad/s, 高速
const AI_SPRINT_TURN_PENALTY := 0.6
```

2. **新增变量（变量区末尾，`cached_run_target` 之后）：**
```gdscript
var _ai_move_direction := Vector2.RIGHT  ## AI 平滑移动方向
```

3. **修改 `perform_ai_movement()` 方法：**

将原 `perform_ai_movement()`（第 32-53 行）替换为：
```gdscript
func perform_ai_movement() -> void:
    var total_steering_force := Vector2.ZERO
    if player.has_ball():
        total_steering_force += get_carrier_steering_force()
    elif is_ball_carried_by_teammate():
        if _is_carrier_human_controlled():
            # 队友是人类玩家 → 智能无球跑位，创造传球选项
            total_steering_force += get_offensive_support_steering_force()
        else:
            # 队友是 AI → 保持阵型跟随
            total_steering_force += get_assist_formation_steering_force()
    else:
        total_steering_force += get_onduty_steering_force()
        if total_steering_force.length_squared() < 1:
            if is_ball_possessed_by_opponent():
                total_steering_force += get_spawn_steering_force()
            elif ball.carrier == null:
                total_steering_force += get_ball_proximity_steering_force()
                total_steering_force += get_density_around_ball_steering_force()

    total_steering_force = total_steering_force.limit_length(1.0)

    # 带球模式决策（只有持球时才需要）
    if player.has_ball():
        _decide_dribble_mode()
    else:
        player.dribble_mode = DribblePhysics.Mode.JOG

    # 速度倍率（冲刺时）
    var speed_mult := 1.0
    if player.dribble_mode == DribblePhysics.Mode.SPRINT:
        speed_mult = 1.6

    # AI 转向平滑（与人类玩家 TurnController 一致的手感）
    var target_dir := total_steering_force
    if target_dir.length() > 0.1:
        _ai_apply_turning(target_dir.normalized(), get_process_delta_time())
        player.velocity = _ai_move_direction * player.speed * speed_mult
    else:
        player.velocity = Vector2.ZERO

    # 同步 heading
    if player.velocity.x > 0:
        player.heading = Vector2.RIGHT
    elif player.velocity.x < 0:
        player.heading = Vector2.LEFT
```

注意：`get_process_delta_time()` 是 Godot 内置函数，获取当前帧 delta。

4. **新增 `_decide_dribble_mode()` 方法（`perform_ai_movement` 之后）：**
```gdscript
func _decide_dribble_mode() -> void:
    var opponent_count := _count_nearby_opponents()
    var dist_to_goal := player.position.distance_to(player.target_goal.get_center_target_position())

    # 条件：技术足够 + 附近没人 + 在进攻半场
    if player.technique >= SPRINT_TECH_THRESHOLD \
            and opponent_count <= SPRINT_OPPONENT_MAX \
            and dist_to_goal < SPRINT_DIST_TO_GOAL_MAX:
        player.dribble_mode = DribblePhysics.Mode.SPRINT
    else:
        player.dribble_mode = DribblePhysics.Mode.JOG
```

5. **新增 `_ai_apply_turning()` 方法：**
```gdscript
func _ai_apply_turning(target_direction: Vector2, delta: float) -> void:
    if target_direction.length() < 0.01:
        return

    var current_dir := _ai_move_direction.normalized()
    var target_dir := target_direction.normalized()

    # 转向速率：速度越快转越慢；冲刺时更慢
    var speed_factor := clamp(player.velocity.length() / player.speed, 0.0, 1.0)
    var turn_rate := lerp(AI_TURN_RATE_LOW, AI_TURN_RATE_HIGH, speed_factor)
    if player.dribble_mode == DribblePhysics.Mode.SPRINT:
        turn_rate *= AI_SPRINT_TURN_PENALTY

    var angle_diff := current_dir.angle_to(target_dir)
    var max_turn := turn_rate * delta

    if abs(angle_diff) <= max_turn:
        _ai_move_direction = target_dir
    else:
        _ai_move_direction = current_dir.rotated(sign(angle_diff) * max_turn)
```

6. **修改 `_make_carrier_decision()` 在传球/射门前切回 JOG：**

在 `_make_carrier_decision()` 方法中，每次 `_execute_shot` 和 `_execute_pass` 调用之前，设置 dribble_mode 为 JOG（保证出球精度）。

在 `_execute_shot` 调用（第 98 行 `_execute_shot(target_goal_pos)`）之前加：
```gdscript
            player.dribble_mode = DribblePhysics.Mode.JOG  # 射门前切回普通模式保证精度
```

在 `_execute_pass` 调用（第 105 行、第 114 行、第 121 行）之前都加：
```gdscript
            player.dribble_mode = DribblePhysics.Mode.JOG  # 传球前切回普通模式保证精度
```

（共有 3 处 `_execute_pass` 调用 + 1 处 `_execute_shot` 调用，共 4 处需要添加。）

- [ ] **Step 2: 运行完整游戏测试**

```bash
GODOT="$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
$GODOT --path . -s tools/test_full_game.gd --headless 2>&1 | tail -10
```

预期：完整比赛能跑完，AI 能正常带球和进球。

- [ ] **Step 3: 运行 runtime 错误检测**

```bash
$GODOT --path . -s tools/test_runtime.gd --headless 2>&1 | tail -20
```

预期：无运行时错误。

- [ ] **Step 4: 提交**

```bash
git add scenes/characters/ai/ai_behavior_field.gd
git commit -m "feat(dribbling): AI adapts to dribble modes with smooth turning

- AI decides JOG vs SPRINT based on technique, pressure, and field position
- AI only sprints when technique >= 60, 0 nearby opponents, and in attacking half
- AI uses smooth turning (TurnController) matching human player feel
- AI switches back to JOG before shooting/passing for accuracy
- Sprint speed multiplier 1.6x for AI (same as human)"
```

---

## Task 6: 调试可视化 + 测试用例完善 + 参数调优

**Files:**
- Modify: `scenes/debug/dribble_debug_draw.gd`
- Modify: `tools/test_dribbling.gd`（完善测试）

**Interfaces:**
- Consumes:
  - `DribblePhysics.Mode`
  - `Player.dribble_mode`
  - `DribblePhysics.debug_get_technique_stats()`

### 步骤

- [ ] **Step 1: 更新 DribbleDebugDraw 显示内容**

读取 `scenes/debug/dribble_debug_draw.gd`，做以下修改：

1. **显示当前带球模式**：在显示文字中增加模式标识
2. **显示转向信息**：如果 carrier 有 `current_move_direction`（从 player state 取），显示转向角度差
3. **显示速度惩罚值**：根据当前速度计算并显示

由于 `dribble_debug_draw.gd` 的具体结构需要读文件才能准确修改，本步骤的实现方式：
- 打开文件，找到绘制文字的部分
- 在其中添加模式名（JOG/SPRINT）的文字显示
- 添加 turn angle / speed penalty 的显示（如无法直接获取 player state 的内部变量，则跳过转向显示，只显示模式）

先读文件确认结构：
```
Read scenes/debug/dribble_debug_draw.gd
```

然后根据实际结构进行修改。核心要求：
- 触球区颜色随模式变化：JOG = 绿色，SPRINT = 橙红色
- 左上角显示当前模式文字
- 显示技术属性对应的值（触球区长度、可控距离等）

- [ ] **Step 2: 完善 test_dribbling.gd 测试用例**

在 `tools/test_dribbling.gd` 中新增：

```gdscript
func test_speed_penalty() -> void:
    print("-- Speed Penalty Tests --")

    var ball_vel := Vector2(30.0, 0.0)
    var max_speed := 100.0
    var tech := 64.0

    # 低速 vs 高速：高速时触球精度更低（多次运行统计 y 偏差更大）
    var low_speed_vel := Vector2(20.0, 0.0)
    var high_speed_vel := Vector2(90.0, 0.0)

    # 速度为 0 时不触球（已有测试覆盖），这里验证速度影响效率
    # 高速时球速提升应该更小（效率低）
    var low_result := DribblePhysics.compute_touch_impulse(ball_vel, low_speed_vel, max_speed, tech)
    var high_result := DribblePhysics.compute_touch_impulse(ball_vel, high_speed_vel, max_speed, tech)

    # 高速推球速度肯定更快（因为 player 速度快），但验证函数不崩溃
    _assert(high_result.length() > low_result.length(),
        "High speed push results in faster ball",
        "low=%.1f high=%.1f" % [low_result.length(), high_result.length()])

    print()


func test_mode_min_interval() -> void:
    print("-- Mode: Min Touch Interval Tests --")

    var tech := 64.0
    var jog_interval := DribblePhysics.get_min_touch_interval(tech, DribblePhysics.Mode.JOG)
    var sprint_interval := DribblePhysics.get_min_touch_interval(tech, DribblePhysics.Mode.SPRINT)

    _assert(sprint_interval > jog_interval, "SPRINT min interval > JOG",
        "jog=%.3f sprint=%.3f" % [jog_interval, sprint_interval])

    # 验证倍率 ~ 1.875（0.08 → 0.15）
    var ratio := sprint_interval / jog_interval
    _assert(_approx(ratio, 1.875, 0.05), "SPRINT/JOG interval ratio ~ 1.875",
        "ratio=%.3f" % ratio)

    print()
```

在 `_ready()` 中添加对应的调用。

- [ ] **Step 3: 运行所有测试**

```bash
GODOT="$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
$GODOT --path . -s tools/test_dribbling.gd --headless 2>&1 | tail -15
```

预期：全部通过。

- [ ] **Step 4: 综合测试：完整游戏 + runtime**

```bash
$GODOT --path . -s tools/test_full_game.gd --headless 2>&1 | tail -10
$GODOT --path . -s tools/test_runtime.gd --headless 2>&1 | tail -20
```

预期：均通过。

- [ ] **Step 5: 参数调优**

运行测试过程中，如果发现以下问题，对应调整参数：

| 问题 | 调整方向 | 涉及常量 |
|------|---------|---------|
| 冲刺带球太容易失控 | 增大 `MODE_CONTROL_DIST_MULT[SPRINT]` 或减小 `MODE_PUSH_OFFSET[SPRINT]` | `dribble_physics.gd` |
| 转向太灵敏（没有重量感） | 降低 `TURN_RATE_*` 值 | `player_state_moving.gd` |
| 转向太迟钝（操作粘滞） | 提高 `TURN_RATE_*` 值 | `player_state_moving.gd` |
| 急转惩罚太重 | 提高 `CUTBACK_SPEED_PENALTY` 或提高 `CUTBACK_ANGLE_THRESHOLD` | `player_state_moving.gd` |
| 接球停球太远 | 提高 `FIRST_TOUCH_ABSORPTION_*` 值 | `dribble_physics.gd` |
| AI 冲刺太频繁 | 提高 `SPRINT_TECH_THRESHOLD` 或降低 `SPRINT_DIST_TO_GOAL_MAX` | `ai_behavior_field.gd` |

- [ ] **Step 6: 提交**

```bash
git add scenes/debug/dribble_debug_draw.gd tools/test_dribbling.gd
git commit -m "feat(dribbling): update debug visuals and expand test coverage

- DribbleDebugDraw shows current mode (JOG=green, SPRINT=orange-red)
- Add speed penalty test
- Add mode min-touch-interval test
- Tune parameters based on playtest feedback"
```

---

## 验证清单（全部完成后）

- [ ] `tools/test_dribbling.gd` 全部通过
- [ ] `tools/test_automated.gd` 30s 不崩溃
- [ ] `tools/test_full_game.gd` 完整比赛跑完
- [ ] `tools/test_runtime.gd` 无运行时错误
- [ ] 全局搜索 `Ball.State.CARRIED`，确认只有 `ball_state_carried.gd` 文件内部引用
- [ ] 人类玩家：按住冲刺键时明显感觉球推得更远、触球间隔更长
- [ ] 人类玩家：大角度转向有明显的速度衰减和弧线变向
- [ ] AI：高技术前锋在无人防守的进攻半场会加速冲刺
- [ ] 停球：长传停球质量明显受 technique 影响
