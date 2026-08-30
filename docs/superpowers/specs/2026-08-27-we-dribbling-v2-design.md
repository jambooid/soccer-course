# WE 风格带球系统 v2 设计文档

> 版本：v2.0  
> 日期：2026-08-27  
> 状态：设计中  
> 参考：`docs/We-dribbling.md`、`docs/dribbling-physics-design.md`

## 1. 背景与目标

### 1.1 现状

v1 带球系统（`BallStateDribbling` + `DribblePhysics`）已经实现了**球球员解耦**的基础物理模型：球有独立速度、指数摩擦、周期性触球推动。但与 `docs/We-dribbling.md` 描述的 WE/PES 风格相比，仍有以下差距：

1. **带球模式单一**：只有一种默认参数，没有普通/冲刺的差异化手感
2. **转向无惯性**：球员瞬间转向，缺少 WE 那种"重量感"和"输入延迟感"
3. **属性影响不够深入**：只有 `technique` 的静态插值，缺少动态速度惩罚
4. **双系统并存**：`KICKED`/`SAVED`/`DEFLECTED`/门将放球 仍走 LEGACY 的 `CARRIED` 状态（lerp 跟随），与 `FREEFORM` 路径的 `DRIBBLING` 物理不一致
5. **AI 不带冲刺**：AI 球员始终以基础速度移动，不会利用冲刺突破

### 1.2 设计目标

- **多模式带球**：普通（JOG）和冲刺（SPRINT）两种模式，物理参数差异明显
- **转向有惯性**：球员身体转向平滑插值，大角度急转有速度惩罚，冲刺时转向更困难
- **属性动态影响**：叠加速度惩罚因子，高速时带球精度下降
- **全局物理统一**：所有接球/控球路径统一到 `DRIBBLING` 状态，淘汰 `CARRIED` 的实际使用
- **AI 适配**：AI 在合适场景使用冲刺带球

### 1.3 非目标（本次不做）

- 精准带球模式（Precision / R2）
- 特技动作（假动作、假射、马赛回旋等）
- 体力系统（stamina 消耗与恢复）
- 动画帧级步伐锁死（用转向平滑替代，即 A+ 方案）
- 背身护球机制

---

## 2. 带球模式系统（Dribble Modes）

### 2.1 DribbleMode 枚举

在 `DribblePhysics` 中新增：

```gdscript
enum Mode { JOG, SPRINT }
```

### 2.2 模式参数表

每个模式对基础物理参数施加一组倍率。基础值沿用 v1 的常量（`TOUCH_ZONE_LEN_*`、`PUSH_MULT_*`、`MAX_INACCURACY_RAD` 等）。

| 参数维度 | JOG（普通） | SPRINT（冲刺） | 说明 |
|---------|------------|---------------|------|
| 触球区长度倍率 | ×1.0 | ×1.3 | 冲刺时触球区更长，大步趟球 |
| 推球倍率偏移 | +0.0 | +0.2 | 在 PUSH_MULT_* 基础上整体上移 |
| 最小触球间隔 | ×1.0 (0.08s) | ×1.875 (0.15s) | 冲刺触球频率降低 |
| 可控距离倍率 | ×1.0 | ×1.5 | 冲刺时球离脚更远才判失控 |
| 方向偏差倍率 | ×1.0 | ×1.5 | 冲刺时方向偏差更大 |
| 触球效率偏移 | +0.0 | -0.1 | 冲刺时触球效率略降 |
| 球员速度倍率 | ×1.0 | ×1.6 | 球员移动速度（现有 sprint 逻辑） |

### 2.3 Mode-aware 物理函数

`DribblePhysics` 的所有核心计算函数增加 `mode: int` 参数（默认 `JOG`），在内部应用对应倍率：

```gdscript
static func get_touch_zone_length(technique: float, mode: int = Mode.JOG) -> float:
    var base := lerp(TOUCH_ZONE_LEN_MIN, TOUCH_ZONE_LEN_MAX, normalize_technique(technique))
    return base * _get_mode_touch_zone_mult(mode)

static func get_max_control_distance(technique: float, mode: int = Mode.JOG) -> float:
    var base := lerp(MAX_CONTROL_DISTANCE_MIN, MAX_CONTROL_DISTANCE_MAX, normalize_technique(technique))
    return base * _get_mode_control_dist_mult(mode)

static func compute_touch_impulse(
    ball_velocity: Vector2,
    player_velocity: Vector2,
    player_max_speed: float,
    technique: float,
    mode: int = Mode.JOG
) -> Vector2:
    # 在现有计算基础上：
    # - 方向偏差 × mode_inaccuracy_mult
    # - 推球倍率 + mode_push_offset
    # - 触球效率 + mode_efficiency_offset
    ...
```

### 2.4 模式切换

**人类玩家**：`PlayerStateMoving.handle_human_movement()` 中，根据 SPRINT 键的按下状态设置 `player.dribble_mode`。

**AI 玩家**：`AIBehaviorField._make_carrier_decision()` 中决策是否进入 sprint 模式：
- 前方无防守压力（对手 < 1 人）且在对方半场 → 有概率切换 SPRINT
- 防守压力大 → 切回 JOG
- 即将传球/射门 → 切回 JOG（保证精度）

---

## 3. 转向惯性系统（Turn Controller）

### 3.1 设计思路（A+ 方案）

WE 文档的步伐锁死需要动画帧配合，在像素动画资源有限的情况下，用**转向平滑插值 + 速度惩罚**来近似实现重量感：

- 球员不瞬间转向，而是每帧向输入方向渐变
- 速度越快、转向速率越慢（惯性越大）
- 冲刺模式下转向速率额外降低
- 大角度急转（>90°）触发速度衰减
- 球因为物理惯性，自然落后于球员方向变化，等到下一次触球才修正 → 弧线变向

### 3.2 TurnController 实现

在 `PlayerStateMoving` 中以变量形式维护（独立函数即可，不必单独成类）：

```gdscript
# 转向参数
const TURN_RATE_LOW_SPEED := 12.0   # 静止时最大转向速率（rad/s）
const TURN_RATE_HIGH_SPEED := 4.0   # 满速时最大转向速率（rad/s）
const SPRINT_TURN_PENALTY := 0.6    # 冲刺时转向速率倍率
const CUTBACK_ANGLE_THRESHOLD := deg_to_rad(90.0)  # 急转角度阈值
const CUTBACK_SPEED_PENALTY := 0.6  # 急转速度衰减（乘以此系数）
const CUTBACK_BALL_KICK := 1.2      # 急转时球的额外前冲倍率

var current_move_direction := Vector2.RIGHT  # 当前实际移动方向
var is_moving := false
```

**每帧转向逻辑**：

```gdscript
func _apply_turning(direction_input: Vector2, delta: float) -> Vector2:
    if direction_input.length() < 0.1:
        is_moving = false
        return current_move_direction  # 保持当前朝向

    is_moving = true
    var target_dir := direction_input.normalized()
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

    # 大角度急转：速度衰减 + 球额外前冲
    if abs(angle_diff) > CUTBACK_ANGLE_THRESHOLD and speed_factor > 0.6:
        player.velocity *= CUTBACK_SPEED_PENALTY
        # 通知 BallStateDribbling 给球一个额外的前冲动量
        if player.has_ball():
            _notify_cutback()

    return current_move_direction
```

### 3.3 球员速度方向与球触球方向

- **球员移动方向**：`velocity` 的大小（速度标量）× `current_move_direction`（方向）= 最终 `player.velocity`
- **触球区方向**：使用 `current_move_direction`（球员实际移动方向），而非输入方向
- **效果**：球员先转，球因为惯性继续沿旧方向滚，直到下一次触球才被推向新方向 → 自然的弧线变向

### 3.4 急转的球物理处理

`BallStateDribbling` 暴露一个 `apply_cutback_kick()` 方法：

```gdscript
func apply_cutback_kick() -> void:
    # 急转时，球因为惯性前冲：沿当前球速方向加速
    if ball.velocity.length() > 10.0:
        ball.velocity *= CUTBACK_BALL_KICK
```

由 `PlayerStateMoving` 在检测到大角度急转时调用。这模拟 WE 文档中"冲刺时大角度变向导致趟大"的效果。

---

## 4. 属性动态影响深化

### 4.1 速度惩罚（Speed Penalty）

在 `compute_touch_impulse()` 中，除了现有的 technique 影响，叠加速度惩罚因子：

```gdscript
# 速度惩罚：跑得越快，精度越低、效率越差
var speed_penalty := clamp(player_speed / player_max_speed, 0.0, 1.0)

# 额外方向偏差（叠加在 technique 偏差之上）
var speed_inaccuracy := MAX_INACCURACY_RAD * speed_penalty * 0.5
var total_inaccuracy := inaccuracy + speed_inaccuracy

# 额外效率损失
var speed_efficiency_loss := speed_penalty * 0.1
var total_efficiency := clamp(efficiency - speed_efficiency_loss, 0.2, 0.95)
```

效果：
- 静止/低速带球：最精准（只有 technique 影响）
- 中速带球：精度略降
- 全速冲刺带球：精度最差（technique 影响 + 速度惩罚 + sprint 模式倍率 三重叠加）

### 4.2 停球质量（First Touch）

进入 `DRIBBLING` 状态时的初始球速，不再是简单的 `current_speed * 0.8`，而是根据球的入射速度和球员 `technique` 计算停球质量：

```gdscript
# 在 BallStateDribbling._enter_tree() 中
func _compute_first_touch_velocity(incoming_vel: Vector2, technique: float) -> Vector2:
    var t_norm := DribblePhysics.normalize_technique(technique)
    # 停球吸收系数：高技术吸收多（球慢下来），低技术吸收少（球弹远）
    var absorption := lerp(0.4, 0.85, t_norm)  # 低技术 40% 吸收 → 高技术 85% 吸收
    var slowed_speed := incoming_vel.length() * (1.0 - absorption)

    # 停球方向：高技术停向球员前方，低技术有随机偏移
    var control_dir := carrier.heading
    var direction_error := lerp(deg_to_rad(45), deg_to_rad(5), t_norm)
    var final_dir := control_dir.rotated(randf_range(-direction_error, direction_error))

    return final_dir * max(slowed_speed, 15.0)
```

**适用场景**：
- `KICKED` → `DRIBBLING`（接传球）
- `DEFLECTED` → `DRIBBLING`（接挡球）
- `SAVED` → `DRIBBLING`（接门将球）
- 门将 `put_down()` → `DRIBBLING`（门将放球）

`FREEFORM` → `DRIBBLING`（拾球）因为球速已经很自由，用现有初始化逻辑即可，但也可以叠加 technique 修正。

---

## 5. 全局 DRIBBLING 统一

### 5.1 状态迁移清单

将以下所有路径从 `CARRIED` 改为 `DRIBBLING`：

| 源状态 | 迁移点 | 当前目标 | 新目标 |
|--------|--------|---------|--------|
| `BallStateKicked` | 球员接住传球 | `Ball.State.CARRIED` | `Ball.State.DRIBBLING` |
| `BallStateSaved` | 门将扑球后控制 | `Ball.State.CARRIED` | `Ball.State.DRIBBLING` |
| `BallStateDeflected` | 球员接挡球 | `Ball.State.CARRIED` | `Ball.State.DRIBBLING` |
| `BallStateHeldByGoalkeeper` | `put_down()` 放球 | `Ball.State.CARRIED` | `Ball.State.DRIBBLING` |
| `BallStateCarried` | 抢断拦截 → 新 CARRIED | `Ball.State.CARRIED` | 直接废弃（拦截由 DRIBBLING 自己处理） |

### 5.2 BallStateCarried 的去留

- **代码保留**：文件不删除，作为回退方案
- **引用清零**：所有其他文件不再引用 `Ball.State.CARRIED`
- **注释标记**：明确标注为 LEGACY / 仅供回退
- **回退方式**：如需回退，将各状态中的 `DRIBBLING` 改回 `CARRIED` 即可

### 5.3 风险缓解

接球从 lerp 跟随切换到物理推球，第一下停球可能失控。缓解措施：
- `停球质量` 机制确保高技术球员停球稳
- 进入 `DRIBBLING` 的前 0.3 秒设置一个 **grace period**（宽限期）：
  - 宽限期内失控距离临时 ×1.5
  - 宽限期内抢断概率 ×0.5
- 如果停球质量调参后仍不稳定，可以增加"主动控球修正"：宽限期内球速向球员前方微调

---

## 6. AI 适配

### 6.1 AI 带球模式切换

`AIBehaviorField` 新增 `_decide_dribble_mode()` 方法，在 `_make_carrier_decision()` 中调用：

```gdscript
func _decide_dribble_mode() -> void:
    var opponent_count := _count_nearby_opponents()
    var dist_to_goal := player.position.distance_to(player.target_goal.get_center_target_position())
    var in_attacking_half := dist_to_goal < 425.0  # 过了中线

    if opponent_count == 0 and in_attacking_half and player.technique > 60:
        # 前方没人 + 进攻半场 + 技术好 → 冲刺突破
        player.dribble_mode = DribblePhysics.Mode.SPRINT
    elif opponent_count >= 2:
        # 防守压力大 → 普通带球保证控球
        player.dribble_mode = DribblePhysics.Mode.JOG
    else:
        # 默认普通带球
        player.dribble_mode = DribblePhysics.Mode.JOG
```

### 6.2 AI 移动速度

`perform_ai_movement()` 中根据 `player.dribble_mode` 调整最大速度：
- SPRINT 模式：速度 ×1.6（与人类玩家一致）
- JOG 模式：基础速度

### 6.3 转向平滑

AI 也使用 `TurnController` 的转向平滑（AI 的方向输入是 steering force 的方向），保证人机转向手感一致。

---

## 7. 文件改动清单

### 新增 / 修改文件

| 文件 | 改动类型 | 说明 |
|------|---------|------|
| `utils/dribble_physics.gd` | 修改 | 新增 Mode 枚举；核心函数增加 mode 参数；速度惩罚；停球质量计算 |
| `scenes/ball/ball_states/ball_state_dribbling.gd` | 修改 | 使用 mode-aware 物理；停球质量初始化；宽限期机制；`apply_cutback_kick()` |
| `scenes/characters/character_states/player_state_moving.gd` | 修改 | TurnController 转向平滑；dribble_mode 管理；急转减速 |
| `scenes/characters/player.gd` | 修改 | 新增 `dribble_mode` 属性 |
| `scenes/ball/ball_states/ball_state_kicked.gd` | 修改 | 接球改为 DRIBBLING |
| `scenes/ball/ball_states/ball_state_saved.gd` | 修改 | 接球改为 DRIBBLING |
| `scenes/ball/ball_states/ball_state_deflected.gd` | 修改 | 接球改为 DRIBBLING |
| `scenes/ball/ball_states/ball_state_held_by_goalkeeper.gd` | 修改 | 放球改为 DRIBBLING |
| `scenes/ball/ball_states/ball_state_carried.gd` | 标注 | 加 LEGACY 注释，不改逻辑 |
| `scenes/characters/ai/ai_behavior_field.gd` | 修改 | AI 带球模式切换；冲刺速度；转向平滑 |
| `scenes/debug/dribble_debug_draw.gd` | 修改 | 增加模式显示、转向角度、速度惩罚显示 |
| `tools/test_dribbling.gd` | 修改 | 增加模式对比测试、转向测试、停球质量测试 |

### 不变的文件

- `utils/intercept_resolver.gd` — 概率式抢断已适用于 DRIBBLING，无需改动
- `scenes/ball/ball_state_factory.gd` — DRIBBLING 已注册
- `scenes/characters/player_state_factory.gd` — 不新增 player state

---

## 8. 调试与测试

### 8.1 调试可视化

`DribbleDebugDraw` 增加：
- 当前带球模式标识（JOG = 绿色文字，SPRINT = 红色文字）
- 转向角度差指示（当前方向 → 目标方向 的弧线）
- 速度惩罚数值显示
- 停球质量数值（接球瞬间的 absorption 系数）

### 8.2 测试场景

`tools/test_dribbling.gd` 新增：

1. **模式对比测试** — 同一球员 JOG vs SPRINT 直线带球 3 秒，记录触球频率和球平均距离
2. **转向弧线测试** — 90° / 180° 转向，记录球的轨迹弧线宽度和调整时间
3. **急转失控测试** — 全速冲刺 90° 急转，验证是否会失控（应该大概率失控或球趟大）
4. **停球质量测试** — 不同 technique 球员接同速度传球，测量停球距离
5. **AI 模式切换测试** — AI 在有/无防守压力时的模式选择
6. **全局迁移测试** — KICKED/SAVED/DEFLECTED/门将放球 各路径都能正常进入 DRIBBLING 并持续带球

---

## 9. 风险与回退

### 9.1 主要风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 停球质量差导致接球频繁失控 | 高 | 宽限期机制 + 高技术球员停球稳 + 可调参 |
| 转向平滑导致操作"粘滞"，玩家不适应 | 中 | 转向速率参数可调，先取保守值（偏灵敏） |
| AI 冲刺带球容易丢球 | 中 | AI 默认保守，只在无压力时冲刺 |
| 全局迁移后进球率大幅变化 | 中 | 用 test_full_game / test_runtime 对比数据 |
| CARRIED 残留引用导致 bug | 低 | 全局搜索 `State.CARRIED`，逐一确认 |

### 9.2 回退方案

- **单路径回退**：某个状态迁移出问题，单独改回 `CARRIED`
- **全局回退**：将所有 `DRIBBLING` 改回 `CARRIED`，BallStateCarried 文件完整保留
- **模式系统回退**：如果模式切换出问题，强制锁定为 JOG 模式即可

---

## 10. 实施里程碑

| 里程碑 | 内容 |
|--------|------|
| M1 | DribblePhysics 模式系统 + 速度惩罚 + 停球质量 |
| M2 | BallStateDribbling 适配（mode-aware + 停球质量 + 宽限期 + cutback） |
| M3 | PlayerStateMoving 转向惯性（TurnController）+ dribble_mode 管理 |
| M4 | 全局 DRIBBLING 统一（KICKED/SAVED/DEFLECTED/门将放球） |
| M5 | AIBehaviorField 适配（模式切换 + 冲刺速度 + 转向平滑） |
| M6 | 调试可视化 + 测试用例 + 参数调优 |
