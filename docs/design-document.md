# Soccer Course 详细设计文档

> 基于 WE2000 设计哲学的 2D 街机足球游戏技术设计规格
>
> 版本：v1.0 · 日期：2026-08-20
>
> 对应 PRD 版本：v1.2

---

## 1. 设计概述

### 1.1 设计目标

本设计文档以 PRD v1.2 为需求来源，基于现有代码架构（Godot 4.4 + GDScript + 状态机模式），将需求转化为可落地的技术方案。设计遵循以下原则：

1. **保持现有架构一致性**：延续已有的状态机三件套（`*State` / `*StateFactory` / `*StateData`）、`GameEvents` 信号总线、`Autoload` 单例模式。
2. **WE2000 设计哲学**：确定性 > 随机性、手感 > 真实、规则 > 仿真。球物理用解析式弹道，触球用动画帧判定，AI 用分级 LOD。
3. **迭代演进**：按 M1→M2→M3→M4 四个里程碑分阶段交付，每阶段都有可玩的完整游戏循环。

### 1.2 技术选型

| 类别 | 选择 | 说明 |
|------|------|------|
| 引擎 | Godot 4.4 | GL Compatibility 渲染器，2D 像素风 |
| 语言 | GDScript | 引擎原生，迭代快 |
| 内部分辨率 | 560×360 | 原 280×180 的 2 倍，整数缩放至 2800×1800 |
| 物理 | 不使用 Godot 物理引擎 | 球和球员均为 CharacterBody2D / AnimatableBody2D，自写运动逻辑 |
| 碰撞检测 | `move_and_collide` + 距离检测 | 只用于边界反弹和粗略位置判定，触球由动画帧决定 |
| 调色板换色 | ShaderMaterial | `shaders/replace_color.gdshader`，一套精灵图多队色 |

### 1.3 与现有代码的关系

当前代码库已实现：6 人制（1 GK + 5 场上）、4 域状态机、球三态（CARRIED/FREEFORM/SHOT）、15 个球员状态（含 HEADER/VOLLEY_KICK/BICYCLE_KICK/CHEST_CONTROL/HURT 等）、基础 AI（on-duty 权重 + 200ms tick）、hitstop + 屏幕震动、锦标赛模式、主菜单/球队选择/锦标赛/比赛 4 个屏幕、KeyUtils 输入抽象、调色板换色 shader。

本次设计的主要变化：
- **阵容**：6 人 → 11 人，新增位置角色体系和阵型系统
- **操作**：二键（pass/shoot）→ 四键 + 双肩键（WE2000 式），新增短传/长传/空档传球三键分立
- **球物理**：增加带球步点（替换现有简单 oscillation）、解析式落地预测、三种传球变体
- **AI**：从单一 on-duty 权重 + 200ms tick → 三级 LOD + 归位点系统 + 无球跑位状态机
- **UI**：增加雷达小地图、蓄力条、传球目标高亮、半场休息界面、阵型选择
- **属性**：2 维（speed/power）→ 7 维完整属性体系
- **输入**：新增 InputBuffer 输入缓冲系统
- **新增系统**：越位判定、身体对抗、误差系统、换人系统

---

## 2. 系统架构总览

### 2.1 架构分层

```
┌─────────────────────────────────────────────────────┐
│                   UI / HUD Layer                     │
│  主菜单 / 球队选择 / 比赛HUD / 雷达 / 暂停 / 结算     │
├─────────────────────────────────────────────────────┤
│                 Game Flow Layer                      │
│  GameManager(状态机) / Match / Tournament / 屏幕状态机 │
├─────────────────────────────────────────────────────┤
│                  Gameplay Layer                      │
│  Players(状态机) / Ball(状态机) / AI / 动作选择器     │
├─────────────────────────────────────────────────────┤
│               Foundation Layer                       │
│  DataLoader / GameEvents / SoundPlayer / MusicPlayer │
│  InputBuffer / PassAccuracy / Formations             │
└─────────────────────────────────────────────────────┘
```

### 2.2 核心 Autoload（单例）

延续现有 5 个 Autoload，新增 2 个：

| 名称 | 文件 | 职责 | 状态 |
|------|------|------|------|
| `DataLoader` | `utils/data_loader.gd` | 加载 squads.json，球队/球员数据 | 已有，需扩展属性 |
| `GameEvents` | `scenes/screens/world/game_events.gd` | 全局信号总线 | 已有，需新增信号 |
| `GameManager` | `scenes/game_manager/game_manager.gd` | 比赛状态机、计时、hitstop | 已有，需扩展半场/加时/换人 |
| `SoundPlayer` | `scenes/audio/sound_player.gd` | SFX 播放（4 通道池） | 已有，需扩展音效 |
| `MusicPlayer` | `scenes/audio/music_player.gd` | 场景音乐切换 | 已有 |
| `InputBuffer` | `utils/input_buffer.gd` | 输入缓冲队列 | **新增（M1）** |
| `GameSettings` | `utils/game_settings.gd` | 游戏设置存储（难度/时长/辅助等） | **新增（M2）** |

### 2.3 状态机清单

项目统一使用「状态类 + 工厂 + 数据」三件套模式：

| 域 | 所有者 | 状态枚举 | 工厂 | 数据类 |
|----|--------|---------|------|--------|
| 屏幕 | `SoccerGame` | `ScreenType` | `ScreenFactory` | `ScreenData` |
| 比赛 | `GameManager` | `GameState` | `GameStateFactory` | `GameStateData` |
| 球员 | `Player` | `Player.State` | `PlayerStateFactory` | `PlayerStateData` |
| 球 | `Ball` | `Ball.State` | `BallStateFactory` | `BallStateData` |
| 无球跑位 | `AIBehaviorField` | `OffBallRunState` | — | —（AI 内部状态） |

每个状态都是一个 `Node`，通过 `add_child()` 挂载到所有者，通过 `state_transition_requested` 信号请求切换。状态切换时旧状态 `queue_free()`，新状态由工厂 `get_fresh_state()` 创建。

---

## 3. 比赛规则系统设计

### 3.1 GameManager 状态扩展

`GameManager` 当前的状态机需要扩展以支持半场休息、加时、点球等阶段。

**新增/修改的 `GameState` 枚举：**

```
KICKOFF → FIRST_HALF → HALFTIME → SECOND_HALF → FULL_TIME
                                                          ↘
                                                         EXTRA_TIME → PENALTY_SHOOTOUT
                                                          ↗
                                              GOAL → CELEBRATION → KICKOFF
```

| 状态 | 对应现有状态 | 职责 | 优先级 |
|------|------------|------|--------|
| `KICKOFF` | `KICKOFF`（现有） | 开球等待，球员归位 | P0 |
| `FIRST_HALF` | 拆分自 `IN_PLAY` | 上半场比赛 | P0 |
| `SECOND_HALF` | **新增** | 下半场比赛（交换场地） | P0 |
| `GOAL_SCORED` | `SCORED`（现有） | 进球后短暂停顿 + 庆祝 | P0 |
| `TEAM_RESET` | `RESET`（现有） | 球员归位，等待开球就绪 | P0 |
| `HALFTIME` | **新增** | 半场休息界面 + 换人 + 战术调整 | P2 |
| `FULL_TIME` | **新增** | 常规时间结束，判断是否加时 | P0 |
| `EXTRA_TIME` | `OVERTIME`（现有） | 加时赛（金球制） | P2 |
| `PENALTY_SHOOTOUT` | **新增** | 点球大战 | P3 |
| `GAME_OVER` | `GAMEOVER`（现有） | 终场，结算 | P0 |
| `PAUSED` | **新增**（非状态机，由 `get_tree().paused` 实现） | 暂停菜单 | P0 |

> **与现有代码的对应**：当前 `GameManager.State` 有 6 个状态（`IN_PLAY, SCORED, RESET, KICKOFF, OVERTIME, GAMEOVER`）。需要将 `IN_PLAY` 拆分为 `FIRST_HALF` 和 `SECOND_HALF` 两个状态（用于半场统计和交换场地），并新增 `HALFTIME` 和 `FULL_TIME`。暂停不使用状态机实现，复用 `get_tree().paused` 机制（当前 hitstop 已使用此方式）。

### 3.2 比赛时间

- 默认每场 2 分钟（街机节奏），上下半场各 1 分钟
- 时间选项：1min / 2min / 3min / 5min，存储在 `GameSettings.match_duration`
- 计时在活球状态倒计时，死球（进球庆祝、出界处理、暂停）时暂停
- 实现：`GameManager` 维护 `match_time_remaining: float`，在 `_process` 中减去 `delta`

### 3.3 进球判定

已有实现基础（球越过球门线 → `Goal` 区域检测），需完善：
- 球整体越过球门线才算进（当前已通过 `ScoringArea` 物理层实现）
- 进球后触发 `GameEvents.team_scored` → `GameManager` 进入 `GOAL_SCORED` 状态
- 庆祝 2 秒 → 双方球员回到开球位置 → `KICKOFF` 状态

### 3.4 越位判定

**新增 `OffsideJudge` 辅助类（挂在 `ActorsContainer` 上）：**

```gdscript
class_name OffsideJudge
extends RefCounted

# 判断传球瞬间是否越位
# 返回：{is_offside: bool, offender: Player, offside_position: Vector2}
func check_offside_at_pass(passer: Player, pass_direction: Vector2) -> Dictionary:
    var attacking_team := passer.country
    var defending_team := _get_opponent_team(attacking_team)
    var second_last_defender := _find_second_last_defender(defending_team, pass_direction)
    var offside_line_x := second_last_defender.position.x

    var result := {"is_offside": false, "offender": null, "offside_position": Vector2.ZERO}

    # 检查所有进攻方球员是否在越位位置
    for attacker in _get_attackers(attacking_team):
        if attacker == passer:
            continue
        # 越位线：比倒数第二名防守球员更靠近对方球门
        if _is_beyond_offside_line(attacker.position, offside_line_x, pass_direction):
            # 检查是否主动参与比赛（接到球或干扰防守）
            if _is_involved_in_play(attacker, passer, pass_direction):
                result.is_offside = true
                result.offender = attacker
                result.offside_position = attacker.position
                return result

    return result

func _find_second_last_defender(defending_team: Array[Player], attack_dir: Vector2) -> Player:
    # 按攻击方向排序，取倒数第二名防守球员（含门将）
    var sorted := defending_team.duplicate()
    sorted.sort_custom(func(a, b):
        return a.position.dot(attack_dir) > b.position.dot(attack_dir)
    )
    return sorted[1] if sorted.size() >= 2 else sorted[0]
```

- 越位判罚在**传球瞬间**进行（不是球到达时）
- 角球、门球、界外球不触发越位检查
- 越位后：吹哨 → 对方在越位地点罚间接任意球（简化为开球）

### 3.5 出界与球权转换

**新增 `BallBoundaryHandler`（挂在 `WorldScreen` 上）：**

监听球与边界的碰撞，判断出界类型：

| 出界类型 | 判定条件 | 恢复方式 |
|---------|---------|---------|
| 边线球 | 球碰到上下边线 | 在出界点附近由对方掷界外球（简化开球） |
| 角球 | 防守方将球踢出己方底线 | 对方在角球点开球 |
| 门球 | 进攻方将球踢出对方底线 | 守方门将在小禁区内开球 |

实现方式：球碰撞边界时，`Ball` 发出 `ball_out_of_bounds(side: int)` 信号 → `BallBoundaryHandler` 根据最后触球方和出界边决定恢复方式。

---

## 4. 操作与控制系统设计

### 4.1 输入映射（Input Map）

**修改 `project.godot` 的 `[input]` 节，从当前的 方向+pass+shoot（6 动作）扩展为 WE2000 式六动作键布局：**

| 动作 | P1 键位 | P2 键位 | 说明 | 现有/新增 |
|------|---------|---------|------|----------|
| 移动（上下左右） | 方向键 | WASD | 方向控制 | 现有 |
| 短传（×） | Z | 1 | 地面短传 / 逼抢 | 现有（改名 pass → short_pass） |
| 长传（○） | X | 2 | 高空长传 / 滑铲 | **新增** |
| 空档传球（△） | C | 3 | 直塞球 / 切换球员 | **新增** |
| 射门（□） | V | 4 | 射门 / 门将出击 | 现有 |
| 加速（R1） | Shift（左） | Q | 冲刺 / 带球加速 | **新增** |
| 特殊动作（L1） | Tab | E | 护球 / 手动切换 | **新增** |

**KeyUtils 扩展**：
- 现有 `KeyUtils.Action` 枚举（`LEFT/RIGHT/UP/DOWN/SHOOT/PASS`）扩展为：`SHORT_PASS, LONG_PASS, THROUGH_PASS, SHOOT, SPRINT, SPECIAL`
- 新增 `is_action_just_pressed_any()` 用于输入缓冲的多动作检测

### 4.2 InputBuffer（输入缓冲）

**新增 `utils/input_buffer.gd`，作为 Autoload（M1 优先级）：**

```gdscript
class_name InputBuffer
extends Node

const BUFFER_WINDOW_MS := 200

# action_name → timestamp_ms
var buffer := {}

func press(action: String) -> void:
    buffer[action] = Time.get_ticks_msec()

func consume(action: String) -> bool:
    if buffer.has(action):
        if Time.get_ticks_msec() - buffer[action] < BUFFER_WINDOW_MS:
            buffer.erase(action)
            return true
        buffer.erase(action)
    return false

func consume_any(actions: Array) -> String:
    for action in actions:
        if consume(action):
            return action
    return ""

func clear() -> void:
    buffer.clear()
```

**集成方式：**
- `Player._input()` 中，按键不直接触发动作，而是调用 `InputBuffer.press()`
- 各 `PlayerState` 在「可接受输入帧」中调用 `InputBuffer.consume()` 检查
- 控球权切换时不清除缓冲（保持输入延续性）

### 4.3 控球权自动切换系统

**新增 `PossessionManager`（挂在 `ActorsContainer` 上）：**

```gdscript
class_name PossessionManager
extends Node

signal player_control_changed(new_player: Player)

var current_controlled: Player = null
var player_side: String  # "home" or "away"

func _ready() -> void:
    GameEvents.ball_possessed.connect(_on_ball_possessed.bind())
    GameEvents.ball_released.connect(_on_ball_released.bind())

func _on_ball_possessed(player: Player) -> void:
    if player.country == _get_player_country():
        # 己方获得球权 → 切换到持球球员
        _switch_control_to(player)

func _on_ball_released() -> void:
    # 球被踢出 → 控制权暂留最后触球球员
    pass  # 不切换

func manual_switch() -> void:
    # 防守时手动切换到离球最近的队友
    var squad := _get_player_squad()
    var closest := _find_closest_to_ball(squad)
    if closest and closest != current_controlled:
        _switch_control_to(closest)

func _switch_control_to(player: Player) -> void:
    if current_controlled:
        current_controlled.set_control_scheme(Player.ControlScheme.CPU)
    player.set_control_scheme(_get_player_control_scheme())
    current_controlled = player
    player_control_changed.emit(player)
```

**切换规则（与 PRD 3.2 对齐）：**
- 己方获得球权 → 控制权自动切到接球球员
- 传球/射门后 → 控制权留在出球队员，直到新的己方球员控球
- 球在空中时 → 控制权留在最后触球的己方球员
- 防守时 → 默认控制离球最近的球员，可手动切换
- 切换时玩家方向输入延续到新球员（通过不清除 `InputBuffer` 和移动状态）

### 4.4 辅助瞄准（磁性传球）

**在 `Ball` 中新增辅助瞄准方法，供传球状态调用：**

```gdscript
# ball.gd — 新增
const SHORT_PASS_ASSIST_ANGLE := 40.0  # 短传吸附角度
const LONG_PASS_ASSIST_ANGLE := 60.0   # 长传吸附角度
const THROUGH_ASSIST_ANGLE := 30.0     # 直塞吸附角度

func assisted_short_pass(direction: Vector2, passer_country: String) -> Vector2:
    # 找到方向上最近的队友，吸附到其脚下
    var target := _find_teammate_in_cone(direction, passer_country, SHORT_PASS_ASSIST_ANGLE, 120.0)
    if target:
        return target.position
    return position + direction * 80.0  # 无目标则向前传一段

func assisted_long_pass(direction: Vector2, power: float, passer_country: String) -> Vector2:
    # 找到远端空位队友
    var max_dist := lerp(60.0, 250.0, power)
    var target := _find_teammate_in_cone(direction, passer_country, LONG_PASS_ASSIST_ANGLE, max_dist)
    if target:
        return target.position
    return position + direction * max_dist

func assisted_through_pass(direction: Vector2, power: float, passer_country: String) -> Vector2:
    # 送到队友跑动路线前方（空档位置）
    var target := _find_teammate_in_cone(direction, passer_country, THROUGH_ASSIST_ANGLE, 200.0)
    if target:
        var run_ahead := lerp(20.0, 80.0, power)
        return target.position + target.velocity.normalized() * run_ahead
    return position + direction * lerp(60.0, 180.0, power)
```

辅助强度受 `GameSettings.pass_assist_level`（低/中/高）影响，对应吸附角度的缩放系数（0.6 / 1.0 / 1.4）。

### 4.5 力度蓄力系统

**复用现有 `PREPPING_SHOT` 状态的蓄力机制，扩展为多动作蓄力：**

当前 `PlayerStatePreppingShot` 已有蓄力逻辑（按住射击键蓄力，瞄准，松开发射）。扩展为支持三种蓄力动作：

| 蓄力动作 | 触发 | 蓄力时长上限 | 释放后进入状态 |
|---------|------|------------|--------------|
| 射门蓄力 | 按住射门键 | 1.5s | `SHOOTING` |
| 长传蓄力 | 按住长传键 | 1.5s | `LONG_PASSING` |
| 直塞蓄力 | 按住空档键 | 1.2s | `THROUGH_PASSING` |

**蓄力 UI 由 HUD 读取 `Player` 上的公开变量：**

```gdscript
# Player 新增（当前 charge_power 已存在于 PREPPING_SHOT 状态中，需提升到 Player 层）
var charge_display := 0.0  # 0.0 - 1.0，供 HUD 读取
var is_charging := false
var charge_action: int = CHARGE_NONE  # CHARGE_SHOOT / CHARGE_LONG_PASS / CHARGE_THROUGH
```

- 蓄力时显示球员脚下的力量条（HUD 层）
- 蓄力满后保持最大值，不再增加
- 蓄力过满（>0.9）时，射门精度略微下降（误差 +15%）
- 蓄力使用 ease 曲线（现有 `ease(charge, 0.7)` 的 power bonus 模式可复用）

### 4.6 可取消窗口

在 `PlayerStateShooting`、`PlayerStatePassing`、`PlayerStateLongPass` 等起手类状态中实现：

```gdscript
# player_state_shooting.gd
const CANCEL_WINDOW_FRAMES := 6  # 前6帧可取消

var frame_count := 0

func _physics_process(_delta: float) -> void:
    frame_count += 1

    # 起手窗口内可取消
    if frame_count <= CANCEL_WINDOW_FRAMES:
        if InputBuffer.consume("short_pass"):
            transition_state(Player.State.PASSING,
                PlayerStateData.build().set_pass_direction(player.heading))
            return
        if InputBuffer.consume("long_pass"):
            transition_state(Player.State.LONG_PASS, ...)
            return
```

- 高风险动作（铲球 `TACKLING`、倒钩 `BICYCLE_KICK`）无取消窗口
- 取消窗口很短（~100ms），需要快速反应

---

## 5. 球物理系统设计

### 5.1 球的状态机（九态）

当前 `Ball` 有 3 个状态（CARRIED / FREEFORM / SHOT）。对于一个完整规则的足球游戏，球在不同场景下的运动规律、交互方式、可捕获性完全不同，需要更多状态来精确建模。扩展为 **9 个状态**：

| 状态 | 所属类别 | 说明 | 运动规则 | 可被捕获 | 优先级 |
|------|---------|------|---------|---------|--------|
| **`CARRIED`** | 持球类 | 被场上球员携带 | 按带球步点节奏跟随，两次触球间自由滚动 | 否（正在控球） | P0 |
| **`HELD_BY_GOALKEEPER`** | 持球类 | 被守门员抱在手中 | 完全跟随门将，无独立运动 | 否 | P0 |
| **`KICKED`** | 飞行类 | 被踢出（传球/解围） | 解析式弹道，水平方向微摩擦，空中无摩擦 | 是（锁定时间后） | P0 |
| **`SHOT`** | 飞行类 | 射门 | 高速飞行，粒子特效，得分判定优先 | 是（门将可扑） | P0 |
| **`SAVED`** | 反弹类 | 被守门员扑出 | 速度衰减，方向被门将改变，短暂自由运动 | 是 | P1 |
| **`DEFLECTED`** | 反弹类 | 被球员身体挡到/碰到 | 速度方向改变，能量衰减 | 是 | P1 |
| **`FREEFORM`** | 自由类 | 无人控制的自由球 | 地面摩擦减速，空中重力抛物线，边界反弹 | 是 | P0 |
| **`SET_PIECE`** | 死球类 | 定位球（开球/角球/任意球/门球/界外球） | 静止在发球点，等待开球动作 | 否（死球状态） | P1 |
| **`OUT_OF_PLAY`** | 死球类 | 球出界/比赛暂停 | 冻结运动，等待恢复 | 否 | P1 |

> **分类逻辑**：9 个状态按性质分为四类——持球类（2 种）、飞行类（2 种）、反弹类（2 种）、自由类（1 种）、死球类（2 种）。同类状态有相似的运动规则，区别在于触发条件和过渡方式。

#### 状态转换图

```
                    ┌───────────────────────────┐
                    │       持球类              │
                    │  CARRIED  HELD_BY_GK      │
                    └───────┬───────────────────┘
                            │ 传球/解围/开大脚
                            ▼
                    ┌───────────────────────────┐
                    │       飞行类              │
                    │  KICKED          SHOT     │
                    └──┬─────────────┬──────────┘
                       │             │
         被门将扑出    │             │ 被门将扑出
            ┌─────────┘             └──────────┐
            ▼                                  ▼
    ┌──────────────────┐         ┌───────────────────┐
    │    反弹类        │         │    反弹类         │
    │   DEFLECTED      │         │     SAVED         │
    └────────┬─────────┘         └─────────┬─────────┘
             │ 落地/减速                    │ 落地/减速
             ▼                              ▼
    ┌──────────────────────────────────────────────┐
    │              自由类                           │
    │              FREEFORM                         │
    └──────┬───────────────────────────┬───────────┘
           │ 球员拿到球                │ 出界
           ▼                           ▼
    ┌──────────────┐        ┌──────────────────────┐
    │  CARRIED     │        │     死球类           │
    └──────────────┘        │ OUT_OF_PLAY → SET_PIECE │
                            └──────────────────────┘
                                        │ 开球动作
                                        ▼
                                   KICKED / SHOT
```

#### 各状态详细设计

**CARRIED（已在 5.4 带球步点详述）**
- 进入：球员在 FREEFORM/KICKED 状态下成功触球
- 退出：传球/射门 → KICKED/SHOT；被抢断 → FREEFORM
- 特殊规则：球有步点节奏，两次触球间是抢断窗口

**HELD_BY_GOALKEEPER（新增）**
- 进入：门将在禁区内接住来球（SHOT/KICKED/FREEFORM 均可）
- 退出：手抛球 → KICKED；开大脚 → KICKED；放下球 → CARRIED（门将带球）
- 特殊规则：有 6 秒持球时间限制（街机简化为 3 秒，超时自动开大脚）；持球时对方球员不能冲撞
- 与 CARRIED 的区别：门将抱球不是"带球"，球完全静止在手中，没有步点，不能被抢断

**KICKED（新增，从 FREEFORM 中拆分）**
- 进入：球员短传/长传/直塞/解围
- 退出：被球员接住 → CARRIED/HELD_BY_GK；落地滚动 → FREEFORM；出界 → OUT_OF_PLAY
- 与 FREEFORM 的区别：(1) 有 `lock_duration` 捕获锁定（传球后短时间内不能被出球方自己接回），(2) 飞行中不减速（保持传球初速度的弹道感），(3) 有明确的传球目标和辅助瞄准吸附

**SHOT（已有，需完善）**
- 进入：球员射门
- 退出：进球 → （比分 + SCORED）；被扑 → SAVED；打门柱/偏出 → DEFLECTED → FREEFORM
- 特殊规则：得分判定优先；高速飞行带粒子；触发 hitstop
- 当前实现：1 秒持续时间后落回 FREEFORM。需要改为主动判定进球/扑救，而不是计时。

**SAVED（新增）**
- 进入：门将扑到射门
- 运动规则：球速衰减 50-70%，方向由门将扑救方向决定
- 退出：落地 → FREEFORM；门将二次抱住 → HELD_BY_GK；弹出禁区 → 自由球
- 与 DEFLECTED 的区别：SAVED 是门将主动扑救，能量衰减更多，球方向更可控（门将能往安全区域扑）

**DEFLECTED（新增）**
- 进入：球碰到非主动触球的球员身体（肩膀、后背、腿等）
- 运动规则：根据碰撞角度反射，能量衰减 30-50%
- 退出：落地 → FREEFORM；被其他球员碰到 → 继续 DEFLECTED（链式反弹）
- 设计目的：区别于"主动传球/射门"的有意出球，模拟比赛中球"乱弹"的场景

**FREEFORM（已有，需收窄定义）**
- 进入：KICKED/SHOT/SAVED/DEFLECTED 落地后；被抢断后
- 退出：球员触球 → CARRIED；出界 → OUT_OF_PLAY
- 收窄后定位：只表示"球在地面自由滚动"和"无人控制的空中球"两种自由运动状态

**OUT_OF_PLAY（新增）**
- 进入：球出边线/底线；进球后；裁判吹停（越位/犯规）
- 运动规则：完全冻结，位置不变
- 退出：定位球 → SET_PIECE；直接开球 → KICKED
- 作用：明确的"死球"状态标记，用于计时暂停、AI 行为切换等

**SET_PIECE（新增）**
- 进入：出界后球被摆到发球点；中圈开球；角球；任意球；门球
- 子类型：`KICKOFF`, `CORNER`, `FREE_KICK`, `GOAL_KICK`, `THROW_IN`
- 运动规则：球静止，等待发球球员执行开球动作
- 退出：开球 → KICKED 或 SHOT（直接射门）
- 特殊规则：开球前对方球员需退到规定距离外；越位在此状态不生效

#### 设计原则

1. **一个状态 = 一套运动规则 + 一套交互规则**。不是每种场景都要独立状态，但运动或交互规则不同就必须拆分。
2. **状态之间的区别是"球能做什么/别人能对球做什么"**，而不是"球怎么到这里的"。
3. **死球类状态（OUT_OF_PLAY/SET_PIECE）是规则状态，不是物理状态**——球不动，但比赛规则在变化。
4. **反弹类（SAVED/DEFLECTED）持续时间很短**，通常 0.3-0.8 秒就落回 FREEFORM，但它们有独立的物理参数和音效反馈，值得独立成态。

### 5.2 解析式弹道

球的位置计算使用闭式公式，不是逐帧积分：

```gdscript
# ball.gd — 位置更新
var velocity: Vector2      # 水平速度
var height: float = 0.0    # 高度（2.5D）
var height_velocity: float = 0.0  # 竖直速度

const GRAVITY := 600.0
const FRICTION_GROUND := 120.0
const BOUNCINESS := 0.6

func _physics_process(delta: float) -> void:
    match current_state:
        Ball.State.FREEFORM:
            _update_freeform(delta)
        Ball.State.KICKED:
            _update_kicked(delta)
        Ball.State.SHOT:
            _update_shot(delta)

func _update_freeform(delta: float) -> void:
    # 竖直方向：重力抛物线
    height_velocity -= GRAVITY * delta
    height += height_velocity * delta

    # 地面时高度归零 + 弹跳
    if height <= 0.0 and height_velocity < 0.0:
        height = 0.0
        if abs(height_velocity) > 30.0:
            height_velocity = -height_velocity * BOUNCINESS
            # 落地时水平摩擦增加
            velocity *= 0.85
        else:
            height_velocity = 0.0

    # 水平方向：摩擦减速（地面时）
    if height == 0.0:
        var speed := velocity.length()
        if speed > 0.0:
            var new_speed := max(0.0, speed - FRICTION_GROUND * delta)
            velocity = velocity.normalized() * new_speed

    # 移动 + 碰撞反弹
    var collision := move_and_collide(velocity * delta)
    if collision:
        velocity = velocity.bounce(collision.get_normal()) * 0.7
```

### 5.3 落地预测

**`Ball` 新增预测方法，供 AI 和 UI 使用：**

```gdscript
func predict_landing_position() -> Vector2:
    if height <= 0.0 or height_velocity >= 0.0:
        return position  # 已在地面或上升中

    # 解二次方程：h + v*t - 0.5*g*t² = 0
    # t = (v + sqrt(v² + 2gh)) / g
    var t_land := (height_velocity + sqrt(height_velocity * height_velocity + 2.0 * GRAVITY * height)) / GRAVITY

    # 水平方向匀速（简化）
    return position + velocity * t_land

func predict_position_at_time(t: float) -> Vector2:
    # 预测 t 秒后的位置（用于 AI 预判截球）
    return position + velocity * t
```

### 5.4 带球步点系统（Dribble Touch）

**在 `BallStateCarried` 中实现：**

```gdscript
class_name BallStateCarried
extends BallState

var touch_timer := 0.0
var touch_interval := 0.25  # 两次触球间隔（秒），由球员技术属性决定
var is_ball_free := false   # 球是否处于"离脚"状态

func setup(carrier: Player) -> void:
    self.carrier = carrier
    touch_interval = lerp(0.35, 0.15, carrier.technique / 100.0)

func _physics_process(delta: float) -> void:
    touch_timer += delta

    if touch_timer >= touch_interval:
        touch_timer = 0.0
        _perform_touch()
    elif is_ball_free:
        # 两次触球之间，球自由滚动
        ball.position += ball.velocity * delta

func _perform_touch() -> void:
    # 球员触球：将球调整到前方合适位置
    var foot_pos := carrier.position + carrier.heading * 8.0
    var speed := carrier.velocity.length()
    var touch_distance := lerp(6.0, 16.0, speed / carrier.max_speed)

    ball.position = foot_pos + carrier.heading * touch_distance
    ball.velocity = carrier.heading * speed * 1.1
    is_ball_free = true
    # 短暂延迟后球"回到"控制中
    get_tree().create_timer(0.1).timeout.connect(func(): is_ball_free = false)
```

**抢断窗口**：防守球员只能在球处于 `is_ball_free` 状态时才能成功抢断。这是带球-抢断博弈的核心机制。

### 5.5 三种传球物理

| 传球类型 | 触发 | 球状态 | 轨迹 | 速度 |
|---------|------|--------|------|------|
| 短传 | 短传键 | `KICKED` | 地面直线 | 中等，刚好滚到目标 |
| 长传 | 长传键（蓄力） | `KICKED` | 高空抛物线 | 蓄力决定距离 |
| 空档传球 | 空档键（蓄力） | `KICKED` | 地面快速直线 | 快，穿透力强 |

```gdscript
# ball.gd — 三种传球方法
func short_pass(target: Vector2, power: float) -> void:
    var direction := position.direction_to(target)
    var distance := position.distance_to(target)
    # 短传速度：刚好滚到目标位置停下
    var intensity := sqrt(2.0 * distance * FRICTION_GROUND)
    velocity = direction * intensity * power
    height = 0.0
    height_velocity = 0.0
    switch_state(Ball.State.KICKED)

func long_pass(target: Vector2, power: float) -> void:
    var direction := position.direction_to(target)
    var distance := position.distance_to(target)
    var intensity := sqrt(2.0 * distance * FRICTION_GROUND * 0.7) * lerp(0.5, 1.3, power)
    velocity = direction * intensity
    # 高空球：竖直初速度
    height = 0.0
    height_velocity = GRAVITY * distance / (1.5 * intensity)  # 抛物线公式
    switch_state(Ball.State.KICKED)

func through_pass(target: Vector2, power: float) -> void:
    var direction := position.direction_to(target)
    var distance := position.distance_to(target)
    # 直塞球：速度快、贴地
    var intensity := lerp(180.0, 300.0, power)
    velocity = direction * intensity
    height = 0.0
    height_velocity = 0.0
    switch_state(Ball.State.KICKED)
```

### 5.6 射门物理

```gdscript
# ball.gd
func shoot(direction: Vector2, power: float, player_power: float) -> void:
    var shot_speed := lerp(200.0, 400.0, power) * lerp(0.85, 1.15, player_power / 100.0)
    velocity = direction.normalized() * shot_speed
    # 射门略带高度（根据蓄力和距离）
    height = 0.0
    height_velocity = lerp(0.0, 120.0, power)
    switch_state(Ball.State.SHOT)
```

---

## 6. 球员系统设计

### 6.1 球员属性扩展

**`PlayerResource` 从 2 个属性扩展到 7 维：**

```gdscript
# resources/player_resource.gd
class_name PlayerResource
extends Resource

@export var name: String = "Player"
@export var skin: int = 0  # SkinColor 枚举索引
@export var role: int = 0  # Role 枚举索引
@export var number: int = 0  # 球衣号码

# 七维属性（0-100）
@export var speed: int = 50       # 速度
@export var power: int = 50       # 力量
@export var technique: int = 50   # 技术
@export var shooting: int = 50    # 射门
@export var defense: int = 50     # 防守
@export var jump: int = 50        # 弹跳
@export var stamina: int = 50     # 体力

# 动作风格参数（行为差异层，M3）
@export var shot_power_mult: float = 1.0
@export var dribble_step_mult: float = 1.0
@export var pass_curve_mult: float = 0.0
@export var shot_hit_frame_offset: int = 0
```

`squads.json` 相应扩展每个球员的字段。

### 6.2 球员位置与角色体系

**从 4 个角色扩展到更细的位置体系：**

```gdscript
# Player.gd 中
enum Role {
    GOALKEEPER,     # 0 - 门将
    RIGHT_BACK,     # 1 - 右后卫
    LEFT_BACK,      # 2 - 左后卫
    CENTER_BACK,    # 3 - 中后卫
    CENTER_BACK_2,  # 4 - 中后卫2
    RIGHT_MID,      # 5 - 右前卫
    LEFT_MID,       # 6 - 左前卫
    CENTER_MID,     # 7 - 中前卫
    CENTER_MID_2,   # 8 - 中前卫2
    STRIKER,        # 9 - 前锋
    STRIKER_2       # 10 - 前锋2
}
```

### 6.3 阵型系统

**新增 `Formation` 资源类（M2）：**

```gdscript
# resources/formation_resource.gd
class_name FormationResource
extends Resource

@export var name: String = "4-4-2"
@export var positions: Array[Vector2] = []  # 11个归位点（相对球场坐标）
@export var roles: Array[int] = []          # 11个角色枚举
```

**预设阵型（4 种）：**

| 阵型 | 后卫 | 中场 | 前锋 | 风格倾向 |
|------|------|------|------|---------|
| 4-4-2 | 4 | 4 | 2 | 平衡 |
| 4-3-3 | 4 | 3 | 3 | 进攻 |
| 3-5-2 | 3 | 5 | 2 | 控球 |
| 5-3-2 | 5 | 3 | 2 | 防守 |

阵型选择在赛前阵容界面进行，影响球员的 `spawn_position`（归位点）和 AI 行为参数。

### 6.4 球员动作状态机

**`Player.State` 枚举对照（现有 15 个状态 + 新增）：**

| 状态 | 现有/新增 | 说明 | 优先级 | 取消窗口 | 判定帧 | 收招硬直 |
|------|----------|------|--------|---------|--------|---------|
| `MOVING` | 现有 | 移动（走/跑/带球统一在此状态） | P0 | — | — | — |
| `PREPPING_SHOT` | 现有 | 射门蓄力瞄准 | P0 | 有 | — | — |
| `SHOOTING` | 现有 | 射门起手 + 触球 | P0 | 有（8帧） | 第12帧 | 15帧 |
| `PASSING` | 现有 | 短传（当前唯一传球类型） | P0 | 有（6帧） | 第8帧 | 6帧 |
| `LONG_PASSING` | **新增** | 长传起手（蓄力释放） | P0 | 有（8帧） | 第12帧 | 10帧 |
| `THROUGH_PASSING` | **新增** | 直塞起手（蓄力释放） | P0 | 有（6帧） | 第8帧 | 6帧 |
| `TACKLING` | 现有 | 滑铲（主动断球，高风险高回报） | P0 | 无（高风险） | 4-8帧 | 15帧 |
| *(自动断球)* | 机制而非状态 | 防守者站在带球路线上自动断球（见 6.5 节） | P0 | — | 实时判定 | — |
| `RECOVERING` | 现有 | 动作后硬直恢复 | P0 | 无 | — | 可变 |
| `HEADER` | 现有 | 头球攻门/摆渡 | P1 | 无 | 第6帧 | 8帧 |
| `VOLLEY_KICK` | 现有 | 凌空射门 | P2 | 无 | 第5帧 | 12帧 |
| `BICYCLE_KICK` | 现有 | 倒钩 | P3 | 无 | 第10帧 | 20帧 |
| `CHEST_CONTROL` | 现有 | 胸部停球 | P0 | 无 | 第3帧 | 5帧 |
| `HURT` | 现有 | 被铲倒/硬直（即 KNOCKED_DOWN） | P2 | 无 | — | ~60帧 |
| `DIVING` | 现有 | 门将扑救 | P0 | 无 | 第3帧 | 12帧 |
| `PROTECTING_BALL` | **新增** | 护球（按住 L1） | P1 | 有 | — | 松开即恢复 |
| `PRESSING` | **(状态内)** | 逼抢（MOVING 内的行为模式） | P0 | — | — | — |
| `SPRINTING` | **(状态内)** | 加速冲刺（MOVING + R1 标志位） | P0 | — | — | — |
| `CELEBRATING` | 现有 | 进球庆祝 | P1 | 无 | — | 持续 |
| `MOURNING` | 现有 | 失球失落 | P1 | 无 | — | 持续 |
| `RESETING` | 现有 | 归位/开球准备 | P0 | 无 | — | — |

> **设计说明**：冲刺和逼抢不作为独立状态，而是 `MOVING` 状态内的行为模式（通过标志位 `is_sprinting`、`is_pressing` 切换）。这是因为它们本质上是移动的变体，不涉及触球判定，独立成状态会增加状态转换的复杂度。护球作为独立状态是因为它改变了碰撞判定和抢断规则。

### 6.5 断球与过人机制

> **这是足球游戏攻防博弈的核心底层机制**。WE 系列的防守不是"按铲球键才能断球"——站在带球路线上本身就能断球。过人也不是"按一个假动作键就过去"——而是在防守者断球窗口的一瞬间变向。

#### 6.5.1 自动断球（Auto-intercept）

防守球员**不需要按任何键**，只要满足以下条件就会自动断球：

1. **球处于"离脚"状态**：带球步点中两次触球之间的窗口（球在自由滚动的那几帧）
2. **防守者在球的路径上**：防守者身体位置与球的运动方向相交
3. **距离足够近**：球离防守者脚的距离 < 断球阈值

```gdscript
# utils/intercept_resolver.gd
class_name InterceptResolver
extends RefCounted

const AUTO_INTERCEPT_RADIUS := 10.0      # 自动断球距离
const INTERCEPT_ANGLE_TOLERANCE := 35.0  # 断球角度容差（度）

# 检测防守球员是否能自动断下带球队员的球
static func check_auto_intercept(defender: Player, attacker: Player, ball: Ball) -> Dictionary:
    # 只有球处于"离脚"状态时才能被断
    if ball.current_state != Ball.State.CARRIED:
        return {"success": false, "reason": "ball_not_carried"}
    if not ball.is_ball_free:  # 带球步点中的自由滚动窗口
        return {"success": false, "reason": "ball_not_in_window"}

    var ball_pos := ball.position
    var ball_vel := ball.velocity
    var dist := defender.position.distance_to(ball_pos)

    if dist > AUTO_INTERCEPT_RADIUS:
        return {"success": false, "reason": "too_far"}

    # 球是否朝防守者方向来（带球人直线冲向防守者 = 最容易被断）
    var ball_to_defender := defender.position - ball_pos
    var angle_diff := rad_to_deg(abs(ball_vel.angle_to(ball_to_defender)))

    if angle_diff > INTERCEPT_ANGLE_TOLERANCE:
        # 球不是冲着防守者来的 → 断不到
        return {"success": false, "reason": "bad_angle"}

    # 防守属性加成：高防守的球员断球半径更大
    var defense_bonus := defender.defense / 100.0 * 3.0
    var effective_radius := AUTO_INTERCEPT_RADIUS + defense_bonus

    if dist <= effective_radius:
        return {"success": true, "quality": 1.0 - dist / effective_radius}

    return {"success": false, "reason": "distance_margin"}
```

**核心设计要点：**

| 要点 | 说明 |
|------|------|
| **直直带球必被断** | 正面冲向防守者，球直接滚到防守者脚下 → 自动断球。这迫使玩家必须变向。 |
| **变向过人的原理** | 在球即将进入防守者断球范围的瞬间，球员变向 → 球的运动方向改变 → 不再朝向防守者 → 角度判定不通过 → 断球失败 → 过人成功 |
| **时机是关键** | 变向太早，防守者也会调整位置；变向太晚，球已经被断。玩家需要把握"最后一刻"的时机。 |
| **防守属性影响范围** | 防守好的球员断球半径更大（更难被过），防守差的更容易被过。 |

#### 6.5.2 带球变向与过人

**过人不是"按一个键就过去"，而是操作移动方向的时机判断。** 原理如下：

```
防守者站在原地
     ↓
带球人直线冲过来 → 球正对防守者 → 自动断球 → 丢球
     ↓
带球人在最后一刻变向 → 球的运动方向偏转 → 角度判定 > 35° → 断球失败 → 过人
```

**影响过人难度的因素：**

| 因素 | 效果 |
|------|------|
| **带球人技术** | 技术高 → 变向响应更快、球离脚更近（断球窗口更小） |
| **带球人速度** | 速度越快 → 留给防守者的反应时间越短，但变向惯性也越大 |
| **防守者防守属性** | 防守高 → 断球半径大、角度容差宽，更难被过 |
| **防守者是否在移动** | 站着不动的防守者比移动中的更好过（移动中可以调整位置封堵） |
| **变向角度大小** | 变向角度越大越容易过人，但也可能把自己晃出有利位置 |

#### 6.5.3 手动铲球（TACKLING）

手动铲球是"加大范围 + 高风险"的主动断球：

| 维度 | 自动断球 | 手动铲球 |
|------|---------|---------|
| 触发 | 自动（站位置就行） | 按长传键（○） |
| 断球范围 | ~10px（小） | ~25px（大，铲出去的距离） |
| 角度容差 | 35°（窄，必须正对） | 90°（宽，侧面也能铲到） |
| 风险 | 无（没断到就继续跑） | 高（铲空有 15 帧硬直） |
| 球状态要求 | 仅步点窗口 | 步点窗口 + 自由球 + 部分持球状态 |
| 防守属性加成 | 有 | 有（铲球成功率 = 防守属性 / 100） |

**铲球判定逻辑：**

```gdscript
# player_state_tackling.gd 中 active 帧的判定
func _check_tackle_hit() -> void:
    var targets := _get_nearby_opponents(TACKLE_RADIUS)
    for target in targets:
        if not _is_in_tackle_cone(target):
            continue

        var ball := target.ball
        var can_intercept := false

        if ball.current_state == Ball.State.CARRIED and ball.is_ball_free:
            # 球在步点窗口 → 可以断
            can_intercept = true
        elif ball.current_state in [Ball.State.FREEFORM, Ball.State.KICKED]:
            # 自由球/传球 → 可以铲
            can_intercept = true

        if can_intercept:
            var success_chance := _calc_tackle_success(target, ball)
            if randf() < success_chance:
                _win_tackle(target, ball)
                return

    # 没铲到 → 继续硬直
```

#### 6.5.4 身体护球与背身过人

`PROTECTING_BALL`（护球）状态下，断球规则改变：

- **自动断球难度 × 2**：球在身体另一侧，防守者更难够到
- **正面铲球成功率 -50%**：背身护住球，正面铲球容易踢到人
- **但移动速度 -60%**：护球时移动很慢，不能快速推进
- **从后面接近的防守者仍有断球可能**：护球只能防正面

背身过人（马赛回旋式）：按住护球 + 方向键 180° 转身 → 球从身体一侧换到另一侧 → 正好避开防守者的断球方向。

#### 6.5.5 防守 AI 的拦截走位

防守 AI 的核心不是"冲上去抢"，而是：

1. **预测带球路线**：根据带球者的速度和方向，预测球的下一步位置
2. **站在路线上**：把自己放在球的运动路径上 → 自动断球
3. **引诱变向**：假装给一侧空间，等对方变向后再封堵另一侧

```gdscript
# ai/ai_behavior_field.gd — 防守时的走位逻辑
func _intercept_position(ball_pos: Vector2, ball_vel: Vector2) -> Vector2:
    # 预测球在 T 秒后的位置
    var t := 0.3  # 预判提前量
    var future_ball_pos := ball_pos + ball_vel * t

    # 站在球与自己球门之间的路线上
    var goal_center := player.own_goal.get_center_target_position()
    var ball_to_goal := goal_center - ball_pos
    var intercept_line := ball_to_goal.normalized()

    # 站位：球的正前方（靠近球门一侧）
    return ball_pos + intercept_line * 8.0
```

> **WE 设计精髓**：防守的本质是"位置博弈"，不是"按键抢球"。玩家防守时 80% 的时间在判断站位和移动方向，只有 20% 的时间在按铲球键。好的防守者不靠铲球——让对方自己把球送到你脚下。

#### 6.5.6 与带球步点的联动

带球步点系统（见 5.4 节）是断球机制的基础：

- **球离脚的时间窗口 = 可被断的窗口**
- 技术好的球员触球更频繁 → 球"离脚"的时间更短 → 更难被断
- 跑得越快，每步球离身体越远 → 断球窗口更大 → 更容易被断
- 这就是为什么"高速带球更容易丢球"是自然结果，不是人为规则

**总结公式：**

```
断球成功率 =
    距离因子（越近越高）
  × 角度因子（越正对越高）
  × 窗口因子（球离脚时 = 1.0，球在脚上时 = 0.0）
  × 属性因子（防守者防守 / 带球者技术）
  × 状态因子（护球 × 0.5，冲刺 × 1.3）
```

### 6.7 ContactFrameData（触球帧数据）

**新增资源类，统一所有触球类动作的帧数据定义：**

```gdscript
# resources/contact_frame_data.gd
class_name ContactFrameData
extends Resource

@export var startup_frames: int = 8      # 起手帧（可取消）
@export var hit_frame: int = 12          # 触球判定帧
@export var recovery_frames: int = 10    # 收招硬直
@export var contact_radius: float = 12.0 # 触球距离阈值
@export var launch_velocity_mult: float = 1.0  # 出球速度倍率
@export var is_cancelable: bool = true   # 起手是否可取消
```

每个触球类状态（`SHOOTING`、`PASSING` 等）持有一个 `ContactFrameData` 实例，驱动动画和判定节奏。

### 6.8 多因子动作选择

**新增 `ActionSelector` 类（M2）：**

```gdscript
# utils/action_selector.gd
class_name ActionSelector
extends RefCounted

enum ShotVariant {
    FULL_LACE,       # 正脚背抽射
    OUTSIDE_FOOT,    # 外脚背
    HASTY_SHOT,      # 匆忙射门
    TOE_POKE,        # 脚尖捅射
    INSTep_DRIVE     # 推射
}

func select_shot_variant(player: Player, ball: Ball, goal_pos: Vector2) -> ShotVariant:
    var body_angle := abs(player.heading.angle_to(
        player.position.direction_to(goal_pos)
    ))
    var defensive_pressure := _calc_defensive_pressure(player)
    var ball_speed := ball.velocity.length()
    var balance := _calc_balance(player)

    # 身体朝向偏差大 → 外脚背或捅射
    if body_angle > deg_to_rad(45):
        if defensive_pressure > 0.6:
            return ShotVariant.TOE_POKE
        return ShotVariant.OUTSIDE_FOOT

    # 防守紧逼 → 匆忙射门
    if defensive_pressure > 0.7:
        return ShotVariant.HASTY_SHOT

    # 来球快 → 不停球直接射（凌空 / 第一时间）
    if ball_speed > 100.0 and player.technique > 60:
        return ShotVariant.FULL_LACE  # 高质量第一时间射门

    # 技术好 + 站稳 → 正脚背抽射
    if player.technique > 70 and balance > 0.7:
        return ShotVariant.FULL_LACE

    return ShotVariant.INSTEP_DRIVE

func get_contact_data(variant: ShotVariant, player: Player) -> ContactFrameData:
    var template := _get_template(variant)
    var personalized := template.duplicate()
    # 叠加球员个人参数
    personalized.hit_frame += player.shot_hit_frame_offset
    personalized.launch_velocity_mult *= player.shot_power_mult
    return personalized
```

### 6.9 身体对抗系统（M2）

**新增 `PhysicalContestResolver`：**

```gdscript
# utils/physical_contest_resolver.gd
class_name PhysicalContestResolver
extends RefCounted

enum Result {
    ATTACKER_WINS,   # 进攻方护住球/突破
    DEFENDER_WINS,   # 防守方断球
    STALEMATE,       # 互相推搡，球弹开
    ATTACKER_FALLS,  # 进攻方被撞倒
    DEFENDER_FALLS   # 防守方被撞倒
}

func resolve(attacker: Player, defender: Player, contest_type: int) -> Result:
    var power_diff := attacker.power - defender.power
    var speed_diff := attacker.velocity.length() - defender.velocity.length()
    var technique_diff := attacker.technique - defender.technique

    var score := 0.0
    match contest_type:
        CONTEST_BALL_PROTECTION:  # 背身护球
            score = power_diff * 0.5 + technique_diff * 0.3
        CONTEST_RACE:             # 速度拼抢
            score = speed_diff * 0.6 + power_diff * 0.2
        CONTEST_TACKLE:           # 正面铲球
            score = -power_diff * 0.4 - defender.defense * 0.01 * 6.0 + ...

    if score > 0.3:
        return Result.ATTACKER_WINS
    elif score > 0.1:
        return Result.STALEMATE
    elif score > -0.2:
        return Result.DEFENDER_WINS
    else:
        return Result.DEFENDER_FALLS  # 被撞飞
```

---

## 7. 人工智能系统设计

### 7.1 AI 分级架构（LOD）

在现有 `weight_on_duty_steering` 基础上，扩展为三级更新机制：

```gdscript
# ai_behavior.gd — 基类中添加
const UPDATE_CORE_EVERY := 3       # 核心层每3帧
const UPDATE_MID_EVERY := 15       # 中间层每15帧
const UPDATE_FAR_EVERY := 60       # 远端层每60帧

var ai_lod_level: int = 2  # 0=核心, 1=中间, 2=远端

func _physics_process(delta: float) -> void:
    var frame := Engine.get_physics_frames()

    match ai_lod_level:
        0:  # 核心层
            if frame % UPDATE_CORE_EVERY == 0:
                run_full_decision()
            run_movement(delta)
        1:  # 中间层
            if frame % UPDATE_MID_EVERY == 0:
                run_position_update()
            run_movement(delta)
        2:  # 远端层
            if frame % UPDATE_FAR_EVERY == 0:
                run_idle_update()
            run_movement(delta)
```

**LOD 级别分配**（由 `ActorsContainer.set_on_duty_weights()` 每 200ms 重新计算）：

| 级别 | 球员数量 | 分配规则 |
|------|---------|---------|
| 核心层 | 2-3 人 | 持球人 + 最近的防守者 + 最近的接应队友 |
| 中间层 | 6-8 人 | 距离球中等距离的球员 |
| 远端层 | 10+ 人 | 远离球的球员 |

### 7.2 归位点系统

**新增阵型管理器 `FormationManager`（M2）：**

```gdscript
# ai/formation_manager.gd
class_name FormationManager
extends RefCounted

var formation: FormationResource
var pitch_center: Vector2
var ball_position: Vector2

# 球队整体偏移（球移动时阵型平移）
const FORMATION_COMPRESSION_X := 0.15  # 横向压缩系数
const FORMATION_COMPRESSION_Y := 0.1   # 纵向压缩系数
const DEFENSIVE_LINE_OFFSET := 20.0    # 防线整体偏移
const ATTACKING_LINE_OFFSET := -30.0   # 进攻线整体偏移

func get_home_position(player_index: int, match_phase: int) -> Vector2:
    var base := formation.positions[player_index] + pitch_center

    # 根据球的位置整体平移和压缩
    var ball_offset_x := (ball_position.x - pitch_center.x) * FORMATION_COMPRESSION_X
    var ball_offset_y := (ball_position.y - pitch_center.y) * FORMATION_COMPRESSION_Y

    base.x += ball_offset_x
    base.y += ball_offset_y

    # 攻防阶段偏移
    match match_phase:
        MATCH_PHASE_ATTACKING:
            base.x += ATTACKING_LINE_OFFSET
        MATCH_PHASE_DEFENDING:
            base.x += DEFENSIVE_LINE_OFFSET

    return base
```

### 7.3 玩家方无球跑位 AI（M1 核心）

**在 `AIBehaviorField` 中实现无球跑位状态机：**

```gdscript
# ai/ai_behavior_field.gd
enum OffBallRunState {
    HOLD_POSITION,     # 保持位置
    BREAK_OFFSIDE,     # 反越位前插
    REVERSE_RUN,       # 反跑
    PULL_WIDE,         # 拉边
    DROP_DEEP,         # 回撤接应
    OVERLAP_RUN,       # 套边助攻
    SECOND_BALL        # 二点跟进
}

var current_run_state: int = OffBallRunState.HOLD_POSITION
var state_cooldown := 0.0  # 状态切换冷却，避免抖动
const STATE_COOLDOWN_TIME := 0.8

func run_off_ball_decision(delta: float) -> void:
    state_cooldown -= delta
    if state_cooldown > 0.0:
        _execute_run_state()
        return

    var new_state := _select_run_state()
    if new_state != current_run_state:
        current_run_state = new_state
        state_cooldown = STATE_COOLDOWN_TIME
    _execute_run_state()

func _select_run_state() -> int:
    var carrier := ball.carrier
    if not carrier or carrier.country != player.country:
        return OffBallRunState.HOLD_POSITION  # 对方控球，不归这里管

    var my_role := player.role
    var dist_to_ball := player.position.distance_to(ball.position)
    var offside_line := _get_offside_line()

    # 前锋：在防线附近伺机前插
    if my_role in [Player.Role.STRIKER, Player.Role.STRIKER_2]:
        if dist_to_ball > 40.0 and dist_to_ball < 100.0:
            if _is_near_offside_line(offside_line):
                if randf() < 0.3:  # 30%概率前插（模拟决策时机）
                    return OffBallRunState.BREAK_OFFSIDE
        if dist_to_ball > 120.0:
            return OffBallRunState.DROP_DEEP

    # 边后卫：套边助攻
    if my_role in [Player.Role.RIGHT_BACK, Player.Role.LEFT_BACK]:
        if _is_winger_inside():
            return OffBallRunState.OVERLAP_RUN

    # 中路拥挤时拉边
    if _teammates_in_center() > 3:
        return OffBallRunState.PULL_WIDE

    # 离持球人远 → 回撤
    if dist_to_ball > 150.0:
        return OffBallRunState.DROP_DEEP

    return OffBallRunState.HOLD_POSITION
```

### 7.4 CPU 持球 AI（M1）

**持球 CPU 球员的决策树：**

```gdscript
# ai/ai_behavior_field.gd
func run_ball_carrier_decision() -> void:
    var goal_pos := player.target_goal.get_center_target_position()
    var dist_to_goal := player.position.distance_to(goal_pos)
    var defensive_pressure := _calc_defensive_pressure()

    # 1. 在射门范围内 → 射门
    if dist_to_goal < 100.0 and defensive_pressure < 0.6:
        if randf() < _get_shot_tendency():
            var shot_dir := _aim_at_goal()
            player.switch_state(Player.State.SHOOTING,
                PlayerStateData.build()
                    .set_shot_direction(shot_dir)
                    .set_shot_power(lerp(0.5, 1.0, player.shooting / 100.0)))
            return

    # 2. 有队友前插 + 路线通透 → 直塞
    var through_target := _find_through_pass_option()
    if through_target and player.technique > 40:
        player.switch_state(Player.State.THROUGH_PASSING,
            PlayerStateData.build()
                .set_pass_direction(player.position.direction_to(through_target.position))
                .set_pass_power(0.8))
        return

    # 3. 附近队友位置更好 → 短传
    var short_target := _find_short_pass_option()
    if short_target and defensive_pressure > 0.5:
        player.switch_state(Player.State.SHORT_PASSING,
            PlayerStateData.build()
                .set_pass_direction(player.position.direction_to(short_target.position)))
        return

    # 4. 前方有空当 → 带球推进
    if _has_space_ahead():
        player.velocity = player.heading * player.speed * 0.8
        return

    # 5. 被紧逼 → 护球
    if defensive_pressure > 0.7:
        player.switch_state(Player.State.PROTECTING_BALL)
        return

    # 6. 默认短传倒脚
    if short_target:
        player.switch_state(Player.State.SHORT_PASSING, ...)
```

### 7.5 防守 AI（M2）

**防守原则：不追球，追路线。**

```gdscript
# ai/ai_behavior_field.gd
func run_defensive_decision() -> void:
    var carrier := ball.carrier
    if not carrier:
        _move_to_ball()
        return

    var my_role := player.role
    var danger_level := _calc_danger_level()
    var is_closest_defender := _am_i_closest_to_ball()

    if is_closest_defender:
        # 最近的防守者：上抢施压
        _press_carrier(carrier)
        if _tackle_window_open(carrier):
            _attempt_tackle(carrier)
    else:
        # 其他防守者：保持站位 + 盯人
        var mark_target := _get_mark_target()
        if mark_target:
            _move_to_mark_position(mark_target)
        else:
            _return_to_home_position()

func _calc_danger_level() -> float:
    # 计算这个防守位置的危险度
    var angle_to_goal := player.position.angle_to_point(player.target_goal.position)
    var ball_angle_to_goal := ball.position.angle_to_point(player.target_goal.position)
    var angle_covered := abs(angle_to_goal - ball_angle_to_goal)
    return clamp(angle_covered / PI, 0.0, 1.0)
```

**防守 AI 协作**（整条防线的整体行为）：
- 造越位：防线同步前压
- 协防补位：队友被过掉时补位
- 区域+盯人混合：防守时以区域为主，进攻方球员进入区域时贴身

### 7.6 门将 AI 扩展

**`AIBehaviorGoalie` 增加出击和更精细的扑救判断：**

```gdscript
# ai/ai_behavior_goalie.gd
const RUSH_OUT_DISTANCE := 50.0  # 出击距离阈值
const RUSH_OUT_CHANCE := 0.3     # 出击概率（受门将属性影响）

func perform_ai_decisions() -> void:
    var ball_state := ball.current_state

    # 射门状态：判断扑救
    if ball_state == Ball.State.SHOT:
        if ball.is_headed_for_scoring_area(player.own_goal.get_scoring_area()):
            _dive_to_save()
            return

    # 单刀：出击
    var carrier := ball.carrier
    if carrier and carrier.country != player.country:
        var dist_to_ball := player.position.distance_to(ball.position)
        if dist_to_ball < RUSH_OUT_DISTANCE and _is_one_on_one(carrier):
            if randf() < RUSH_OUT_CHANCE * (player.gk_rushing / 100.0):
                _rush_out()
                return

    # 持球时：开球
    if ball.carrier == player:
        _distribute_ball()
```

### 7.7 难度系统

**新增 `DifficultySettings` 资源（M2）：**

```gdscript
# resources/difficulty_settings.gd
class_name DifficultySettings
extends Resource

enum Level { EASY, NORMAL, HARD }

@export var level: int = Level.NORMAL

# 各难度的参数倍率
static func get_params(level: int) -> Dictionary:
    match level:
        Level.EASY:
            return {
                "shot_accuracy_mult": 0.7,
                "pass_accuracy_mult": 0.75,
                "reaction_delay": 0.2,
                "defense_pressure_mult": 0.6,
                "mistake_chance": 0.25,
                "offside_trap_quality": 0.5
            }
        Level.NORMAL:
            return {
                "shot_accuracy_mult": 1.0,
                "pass_accuracy_mult": 1.0,
                "reaction_delay": 0.08,
                "defense_pressure_mult": 1.0,
                "mistake_chance": 0.08,
                "offside_trap_quality": 0.8
            }
        Level.HARD:
            return {
                "shot_accuracy_mult": 1.2,
                "pass_accuracy_mult": 1.15,
                "reaction_delay": 0.02,
                "defense_pressure_mult": 1.3,
                "mistake_chance": 0.02,
                "offside_trap_quality": 0.95
            }
```

---

## 8. 误差系统设计（M2）

### 8.1 设计原则

- 误差是**刻意设计**的系统，不是 bug
- 误差大小**有原因**：玩家能理解"为什么传偏了"
- 使用**种子随机数**：可复现，但不可预测
- 误差 = 基础误差 × 能力因子 × 压力因子

### 8.2 PassAccuracy 工具类

```gdscript
# utils/pass_accuracy.gd
class_name PassAccuracy
extends RefCounted

const BASE_PASS_ERROR := 15.0  # 基础误差（像素）
const MAX_PASS_ERROR := 60.0

static func calculate_pass_error(player: Player, pass_distance: float,
                                  pressure: float, is_moving: bool) -> float:
    var error := BASE_PASS_ERROR

    # 球员技术降低误差
    var technique_factor := 1.0 - clamp(player.technique / 120.0, 0.0, 0.7)
    error *= technique_factor

    # 距离增大误差
    var distance_factor := lerp(0.8, 1.8, clamp(pass_distance / 200.0, 0.0, 1.0))
    error *= distance_factor

    # 防守压力增大误差
    error *= (1.0 + pressure * 1.5)

    # 跑动中传球误差更大
    if is_moving:
        error *= 1.3

    return min(error, MAX_PASS_ERROR)

static func calculate_shot_deviation(player: Player, dist_to_goal: float,
                                       pressure: float, charge_fullness: float) -> float:
    var deviation := 3.0  # 基础偏差角度（度）

    # 射门精度
    var accuracy_factor := 1.0 - clamp(player.shooting / 120.0, 0.0, 0.65)
    deviation *= accuracy_factor

    # 距离越远偏差越大
    deviation *= lerp(0.8, 2.5, clamp(dist_to_goal / 150.0, 0.0, 1.0))

    # 防守压力
    deviation *= (1.0 + pressure * 1.2)

    # 蓄力过满精度下降
    if charge_fullness > 0.9:
        deviation *= 1.15

    return deviation

static func calculate_first_touch_error(player: Player, incoming_speed: float) -> float:
    var error := lerp(3.0, 20.0, clamp(incoming_speed / 250.0, 0.0, 1.0))
    error *= (1.0 - clamp(player.technique / 120.0, 0.0, 0.7))
    return error
```

### 8.3 种子随机数

```gdscript
# utils/seeded_random.gd
class_name SeededRandom
extends RefCounted

var seed: int = 0
var rng := RandomNumberGenerator.new()

func set_seed(new_seed: int) -> void:
    seed = new_seed
    rng.seed = new_seed

func randf_range(min_val: float, max_val: float) -> float:
    return rng.randf_range(min_val, max_val)

# 每局比赛使用同一个种子 → 同样的局势下误差可复现
```

---

## 9. 反馈与手感系统

### 9.1 冲击停顿（Hitstop）— 已有，扩展分档

**`GameManager` 中扩展 `impact_received` 处理：**

```gdscript
# game_manager.gd — 扩展
const HITSTOP_LIGHT := 50     # 轻碰撞
const HITSTOP_NORMAL := 100   # 普通
const HITSTOP_HEAVY := 150    # 重铲球/大力射门

func on_impact_received(pos: Vector2, impact_level: int) -> void:
    var duration := match impact_level:
        IMPACT_LIGHT: HITSTOP_LIGHT
        IMPACT_NORMAL: HITSTOP_NORMAL
        IMPACT_HEAVY: HITSTOP_HEAVY

    get_tree().paused = true
    hitstop_duration = duration
    hitstop_timer = Time.get_ticks_msec()
```

`GameEvents.impact_received` 信号签名从 `(position, is_high_impact: bool)` 改为 `(position, level: int)` 以支持三档。

### 9.2 屏幕震动 — 已有，增强

当前 `Camera` 已实现基础震动。扩展参数：

```gdscript
# camera.gd
const SHAKE_LIGHT := 2
const SHAKE_NORMAL := 5
const SHAKE_HEAVY := 10

func shake(intensity: int, duration_ms: int) -> void:
    shake_intensity = intensity
    shake_duration = duration_ms
    is_shaking = true
    time_start_shake = Time.get_ticks_msec()
```

### 9.3 粒子特效（M2）

**新增粒子效果管理器：**

| 效果 | 触发 | 位置 |
|------|------|------|
| 射门火花 | 射门触球帧 | 球员脚下 |
| 铲球尘土 | 铲球着地 | 球员脚下 |
| 进球爆发 | 进球瞬间 | 球门内 |
| 弹跳尘点 | 球落地 | 球落点 |

使用 Godot `GPUParticles2D` 或简单的 `Sprite2D` 动画预制体，通过 `SPARK_PREFAB` 模式实例化。

### 9.4 UI 提示

**HUD 层元素（`world_hud.tscn`）：**

| 元素 | 节点类型 | 位置 | 数据源 |
|------|---------|------|--------|
| 比分板 | `HBoxContainer` | 顶部中央 | `GameManager.current_match` |
| 比赛时间 | `Label` | 比分板旁 | `GameManager.match_time_remaining` |
| 蓄力条 | `TextureProgressBar` | 当前控制球员脚下 | `Player.charge_power` |
| 控球箭头 | `Sprite2D` | 当前控制球员头顶 | `PossessionManager.current_controlled` |
| 传球目标高亮 | `Sprite2D`（环形） | 目标队友脚下/前方 | 传球辅助瞄准结果 |
| 体力条 | `TextureProgressBar` | 球员脚下或侧边 | `Player.stamina_current` |
| 雷达小地图 | `RadarMinimap`（自定义） | 左下角 | 所有球员 + 球位置 |
| 比赛阶段提示 | `Label`（动画） | 顶部居中 | `GameManager.current_phase` |

### 9.5 雷达小地图（M1）

**新增 `RadarMinimap` 控件：**

```gdscript
# ui/radar_minimap.gd
class_name RadarMinimap
extends Control

const MAP_WIDTH := 80.0
const MAP_HEIGHT := 50.0
const PITCH_WIDTH := 420.0
const PITCH_HEIGHT := 260.0

@export var actors_container: ActorsContainer

func _draw() -> void:
    # 绘制球场轮廓
    draw_rect(Rect2(Vector2.ZERO, Vector2(MAP_WIDTH, MAP_HEIGHT)),
        Color(0.2, 0.3, 0.2), false, 1.0)

    # 绘制中线和禁区
    draw_line(Vector2(MAP_WIDTH/2, 0), Vector2(MAP_WIDTH/2, MAP_HEIGHT), Color(1, 1, 1, 0.3))

    # 绘制球员点
    for player in actors_container.squad_home:
        var pos := _world_to_map(player.position)
        draw_circle(pos, 2.0, Color(0.2, 0.6, 1.0))  # 己方蓝色

    for player in actors_container.squad_away:
        var pos := _world_to_map(player.position)
        draw_circle(pos, 2.0, Color(1.0, 0.3, 0.3))  # 对方红色

    # 绘制球
    if actors_container.ball:
        var ball_pos := _world_to_map(actors_container.ball.position)
        draw_circle(ball_pos, 1.5, Color(1, 1, 1))

    # 高亮当前控制球员
    var controlled := _get_controlled_player()
    if controlled:
        var pos := _world_to_map(controlled.position)
        draw_circle(pos, 3.5, Color(1, 1, 0.4), false)  # 黄色环

func _world_to_map(world_pos: Vector2) -> Vector2:
    var x := (world_pos.x + PITCH_WIDTH/2) / PITCH_WIDTH * MAP_WIDTH
    var y := (world_pos.y + PITCH_HEIGHT/2) / PITCH_HEIGHT * MAP_HEIGHT
    return Vector2(x, y)
```

---

## 10. 比赛流程系统

### 10.1 赛前流程

```
主菜单 → 模式选择 → 球队选择 → 阵型/阵容选择 → 3-2-1 倒计时 → 比赛
```

涉及屏幕：`MainMenuScreen`（已有）、`TeamSelectionScreen`（已有）、`FormationSelectScreen`（新增，M2）、`WorldScreen`（已有）。

### 10.2 半场休息（M2）

**新增 `HalftimeScreen`（作为 `WorldScreen` 上的覆盖层，不是独立屏幕）：**

功能：
- 显示上半场统计（比分、控球率、射门数）
- 换人面板（最多换 3 人，全场累计）
- 战术调整（进攻/防守档位）
- 「继续下半场」按钮
- 双方交换场地（通过 `Actors_container.swap_sides()` 实现）

### 10.3 换人系统（M2）

**`GameManager` 中维护换人状态：**

```gdscript
var substitutions_left_home := 3
var substitutions_left_away := 3

func can_substitute(country: String) -> bool:
    var subs_left := substitutions_left_home if country == current_match.country_home else substitutions_left_away
    return subs_left > 0 and current_state == GameState.HALFTIME

func substitute_player(country: String, off_index: int, on_index: int) -> bool:
    if not can_substitute(country):
        return false
    # 执行换人
    var squad := actors_container.get_squad(country)
    squad[off_index].set_active(false)
    squad[on_index].set_active(true)
    # 扣减名额
    if country == current_match.country_home:
        substitutions_left_home -= 1
    else:
        substitutions_left_away -= 1
    return true
```

### 10.4 赛后结算（M1）

**扩展 `WorldScreen` 的游戏结束流程：**

- 显示最终比分（大字）
- 比赛统计：进球、控球率、射门次数
- MVP 评选（进球最多 / 评分最高的球员）
- 操作按钮：重赛 / 选队重赛 / 返回主菜单

---

## 11. UI / HUD 系统

### 11.1 屏幕状态机

当前 4 个屏幕，扩展为：

| ScreenType | 场景 | 说明 | 优先级 |
|-----------|------|------|--------|
| `MAIN_MENU` | `main_menu_screen.tscn` | 主菜单 | P0 |
| `TEAM_SELECTION` | `team_selection_screen.tscn` | 球队选择 | P0 |
| `FORMATION_SELECT` | `formation_select_screen.tscn` | 阵型/阵容选择 | P2 |
| `TOURNAMENT` | `tournament_screen.tscn` | 锦标赛 | P0（已有） |
| `IN_GAME` | `world_screen.tscn` | 比赛画面 | P0 |
| `SETTINGS` | `settings_screen.tscn` | 设置界面 | P1 |

### 11.2 球队选择界面

当前已有，需扩展：
- 8 支国家队（从 6 队扩展？需要确认）
- 左右滚动选择，显示国旗、队名、球队实力
- 双人模式 P1/P2 各自选择

### 11.3 阵型选择界面（M2）

**新增 `FormationSelectScreen`：**

- 可选阵型：4-4-2 / 4-3-3 / 3-5-2 / 5-3-2
- 阵型示意图：用球员头像在球场上标注位置
- 可拖动调整首发位置（简单的位置交换）
- 球队能力雷达图（速度/力量/技术/防守/进攻五维）

### 11.4 暂停菜单

在 `WorldScreen` 上叠加 `PauseMenu` 控件：
- 继续比赛
- 战术调整（进攻/平衡/防守）
- 换人（半场时才可用）
- 重新开始
- 退出到主菜单
- 设置

### 11.5 设置界面（M2）

**新增 `SettingsScreen`：**

| 分类 | 设置项 | 选项 |
|------|--------|------|
| 游戏 | 比赛时长 | 1/2/3/5 分钟 |
| 游戏 | 难度 | 简单/普通/困难 |
| 游戏 | 传球辅助强度 | 低/中/高 |
| 游戏 | 球路预测 | 开/关 |
| 游戏 | 自动切换球员 | 开/关 |
| 音频 | 音效音量 | 0-100 |
| 音频 | 音乐音量 | 0-100 |

设置存储在 `GameSettings` Autoload 中，使用 `ConfigFile` 持久化到用户目录。

---

## 12. 音频系统

### 12.1 音效扩展

`SoundPlayer` 已有 4 通道池。新增音效：

| 音效 | 触发时机 | 优先级 |
|------|---------|--------|
| 短传声 | 短传触球帧 | P0 |
| 长传声 | 长传触球帧 | P0 |
| 射门声 | 射门触球帧 | P0 |
| 接球声 | 停球判定帧 | P0 |
| 铲球声 | 铲球命中 | P0 |
| 弹跳声 | 球落地 | P1 |
| 哨声 | 进球/越位/终场 | P0 |
| 观众欢呼 | 进球后 | P0 |
| 观众叹息 | 错失良机 | P2 |
| 菜单确认 | UI 操作 | P0 |

### 12.2 音乐

`MusicPlayer` 已有。各场景音乐：

| 场景 | 音乐风格 | 优先级 |
|------|---------|--------|
| 主菜单 | 轻快主题 | P0 |
| 球队选择 | 紧张期待 | P1 |
| 比赛中 | 节奏鼓点 | P0 |
| 进球庆祝 | 激昂高潮 | P1 |
| 胜利 | 凯旋 | P1 |
| 失败 | 低沉 | P2 |

---

## 13. 数据与配置

### 13.1 squads.json 扩展

每支球队从 6 名球员扩展到 11 名首发 + 3-5 名替补（M2）：

```json
{
  "country": "BRAZIL",
  "team_style": "attacking",
  "formation": "4-4-2",
  "players": [
    {
      "name": "Taffarel",
      "skin": 2,
      "role": "GOALKEEPER",
      "number": 1,
      "speed": 60,
      "power": 55,
      "technique": 50,
      "shooting": 30,
      "defense": 40,
      "jump": 75,
      "stamina": 65
    },
    // ... 10 名场上球员
  ],
  "substitutes": [
    // 3-5 名替补球员
  ]
}
```

### 13.2 球队风格

`team_style` 影响 AI 全局参数：

| 风格 | 防线位置 | 逼抢强度 | 传球偏好 | 射门倾向 |
|------|---------|---------|---------|---------|
| `attacking` | 靠前 +20 | 1.3x | 短传 | 高 +20% |
| `defensive` | 靠后 -20 | 0.7x | 长传反击 | 低 -20% |
| `possession` | 中等 | 1.0x | 短传倒脚 | 中 |
| `direct` | 中等 | 1.1x | 长传冲吊 | 中高 |

---

## 14. 性能设计

### 14.1 帧率目标

- 稳定 60 FPS
- 22 名球员 + 球 + UI 同时运行不掉帧

### 14.2 性能预算

| 系统 | 每帧耗时预算 | 优化手段 |
|------|------------|---------|
| AI（22 人） | < 2ms | LOD 三级更新（核心3帧/中端15帧/远端60帧） |
| 球物理 | < 0.5ms | 解析式计算，无物理引擎 |
| 球员移动 | < 1ms | CharacterBody2D move_and_slide |
| 渲染 | < 8ms | 像素艺术 + 调色板 shader，draw call 少 |
| UI/HUD | < 1ms | CanvasLayer，低复杂度 |

### 14.3 关键优化点

1. **AI LOD**：22 人中只有 2-3 人每 3 帧做完整决策，其余每 15 或 60 帧更新
2. **球路预测缓存**：`predict_landing_position()` 结果缓存，球状态不变时复用
3. **距离检测优化**：使用 `distance_squared_to` 避免开方
4. **粒子控制**：同时活跃粒子数不超过 50 个
5. **雷达绘制**：每 3 帧重绘一次即可（不需要 60fps）

---

## 15. 里程碑实施计划

### M1: 手感跃迁（P0 全部 + 部分 P1）

**目标**：操作跟手、传球准确、动作连贯，11 人制比赛可玩

| 任务 | 主要改动文件 | 预估工作量 |
|------|-------------|-----------|
| 1. 视窗扩大到 560×360 | `project.godot` + 场景缩放调整 | 小 |
| 2. 输入缓冲系统 | `utils/input_buffer.gd` + `Player.gd` | 中 |
| 3. 四键 + 双肩键操作映射 | `project.godot` + `Player` 各状态 | 中 |
| 4. 控球权自动切换 | `PossessionManager` + `ActorsContainer` | 中 |
| 5. 辅助磁性传球（三种） | `Ball.gd` + 传球状态 | 中 |
| 6. 11 人制阵容 | `squads.json` + `ActorsContainer` + 场景 spawn 点 | 中 |
| 7. 位置角色体系扩展 | `Player.Role` 枚举 + 球员数据 | 小 |
| 8. 带球步点系统 | `BallStateCarried` | 中 |
| 9. 自动断球与过人机制 | `InterceptResolver` + 步点联动 | 大 |
| 10. 玩家方无球跑位 AI | `AIBehaviorField` 跑位状态机 | 大 |
| 11. CPU 持球 AI 决策树 | `AIBehaviorField` 持球决策 | 大 |
| 12. 门将 AI 基础 | `AIBehaviorGoalie` | 中 |
| 13. 雷达小地图 | `RadarMinimap` + HUD | 中 |
| 14. 比赛 HUD 完善 | `world_hud.tscn` + 比分/计时/控球指示 | 中 |
| 15. 上下半场制 | `GameManager` 状态扩展 | 中 |
| 16. 越位判定 | `OffsideJudge` | 大 |

### M2: 玩法深度（P1 全部 + 部分 P2）

**目标**：动作有变体、对抗有博弈、球员有差异

| 任务 | 主要改动文件 | 预估工作量 |
|------|-------------|-----------|
| 1. 力度蓄力系统 | Player + HUD 蓄力条 | 中 |
| 2. 可取消窗口 | 各触球状态 | 中 |
| 3. 出界与球权转换 | `BallBoundaryHandler` | 中 |
| 4. 完整 7 维属性 | `PlayerResource` + `squads.json` | 小 |
| 5. 动作帧数据规范 | `ContactFrameData` 资源 | 大 |
| 6. 多因子动作选择 | `ActionSelector` | 大 |
| 7. 头球动作 | `PlayerStateHeading` | 中 |
| 8. 护球动作 | `PlayerStateProtectingBall` | 中 |
| 9. AI 分级 LOD | `AIBehavior` 基类 | 中 |
| 10. 归位点 + 阵型系统 | `FormationManager` + 阵型资源 | 大 |
| 11. AI 难度等级 | `DifficultySettings` | 小 |
| 12. 门将出击 | `AIBehaviorGoalie` 扩展 | 中 |
| 13. 阵型选择界面 | `FormationSelectScreen` | 中 |
| 14. 赛后结算 + MVP | `ResultScreen` | 中 |
| 15. 设置系统 | `GameSettings` + `SettingsScreen` | 中 |

### M3: AI 升级（P2 全部）

**目标**：跑位聪明、防守合理、球队像整体

| 任务 | 主要改动文件 | 预估工作量 |
|------|-------------|-----------|
| 1. 加时赛（金球制） | `GameManager` + 加时状态 | 小 |
| 2. 球落地预测 API | `Ball.gd` + AI 使用 | 中 |
| 3. 身体对抗系统 | `PhysicalContestResolver` | 大 |
| 4. 防守 AI（站位/协防/造越位） | `AIBehaviorField` 防守逻辑 | 大 |
| 5. 误差系统 | `PassAccuracy` + 种子随机 | 中 |
| 6. 屏幕震动增强 | `Camera` | 小 |
| 7. 粒子特效 | 粒子预制体 + 触发逻辑 | 中 |
| 8. 球员状态指示 | HUD 扩展 | 中 |
| 9. 半场休息 + 换人系统 | `HalftimeScreen` + 换人逻辑 | 大 |
| 10. 球员动作风格参数 | `PlayerResource` 扩展 | 中 |
| 11. 球队风格与战术 | 球队级 AI 参数 | 中 |

### M4: 完整度提升（P3 全部）

**目标**：误差、节奏、反馈的全面打磨

| 任务 | 主要改动文件 | 预估工作量 |
|------|-------------|-----------|
| 1. 点球大战 | 点球状态 + UI | 大 |
| 2. 弧线球 | Ball 轨迹 + 球员参数 | 中 |
| 3. 倒钩、凌空射门 | 新 PlayerState | 中 |
| 4. 假动作系统 | 假动作状态 + 输入组合 | 大 |
| 5. 体力系统 | Player stamina + AI 调整 | 中 |
| 6. 犯规和红黄牌 | 犯规判定 + 红牌系统 | 大（可选） |
| 7. 按键映射设置 | 设置界面扩展 | 小 |

---

## 16. 设计约束与反模式

### 16.1 必须遵守的约束

1. **确定性优先**：球轨迹、AI 行为必须可复现。不使用未经种子化的随机数影响核心玩法。
2. **手感 > 真实**：参数调整以"玩家觉得对不对"为准，不是"物理上对不对"。
3. **帧数据驱动动画**：硬直时长决定动画时长，不由美术资源决定。
4. **动画帧判定触球**：不靠碰撞事件判断"踢到球没"，靠 `hit_frame` + 距离检测。
5. **状态机一致性**：所有新增状态遵循 `*State` + `*StateFactory` + `*StateData` 模式。
6. **信号总线通信**：跨系统通信走 `GameEvents`，不直接引用深层节点。
7. **像素风格保真**：保持 nearest-neighbor 滤波，不做平滑/模糊。

### 16.2 明确不做的事

| 反模式 | 原因 |
|--------|------|
| 用 RigidBody2D 做球物理 | 失去确定性，AI 无法预判 |
| 用物理碰撞做触球判定 | 结果不可预测、不可调试 |
| AI 每帧为所有球员做完整决策 | 性能浪费 + 设计问题 |
| 追求物理真实的参数值 | 手感差就 overrule 真实值 |
| 让动画时长定义硬直 | 美术不应绑架手感 |
| 追求 100% 传球准确率 | 完美传球没有足球味 |
| 所有球员同一套动作参数 | 同质化是大敌 |
| 为"更好看"牺牲"更好判定" | 优先级：AI > 球物理 > 判定 > 手感 > 动画 > 细节 |

---

## 附录 A：文件结构变更清单

### 新增文件

```
# 工具类（utils/）
utils/input_buffer.gd                  # M1: 输入缓冲
utils/game_settings.gd                 # M2: 游戏设置
utils/action_selector.gd               # M2: 动作选择器
utils/pass_accuracy.gd                 # M2: 传球精度计算
utils/seeded_random.gd                 # M2: 种子随机数
utils/intercept_resolver.gd            # M1: 断球判定（自动断球 + 铲球）
utils/physical_contest_resolver.gd     # M3: 身体对抗判定
utils/offside_judge.gd                 # M1: 越位判定

# 球状态（scenes/ball/ball_states/）
scenes/ball/ball_states/ball_state_kicked.gd       # M1: 被踢出（传球状态）
scenes/ball/ball_states/ball_state_saved.gd        # M1: 门将扑出
scenes/ball/ball_states/ball_state_deflected.gd    # M1: 身体反弹
scenes/ball/ball_states/ball_state_held_by_gk.gd   # M1: 门将持球
scenes/ball/ball_states/ball_state_set_piece.gd    # M2: 定位球
scenes/ball/ball_states/ball_state_out_of_play.gd  # M2: 死球/出界

# AI 扩展（scenes/characters/ai/）
scenes/characters/ai/formation_manager.gd    # M2: 阵型归位
scenes/characters/ai/possession_manager.gd   # M1: 控球权管理

# 资源类
resources/contact_frame_data.gd         # M2: 触球帧数据
resources/formation_resource.gd         # M2: 阵型资源
resources/difficulty_settings.gd        # M2: 难度设置
resources/player_resource.gd            # M1: 扩展属性

# UI
ui/radar_minimap.gd                     # M1: 雷达小地图
ui/world_hud.tscn                       # M1: 比赛 HUD 场景
ui/formation_select_screen.tscn         # M2: 阵型选择
ui/halftime_overlay.tscn                # M2: 半场休息
ui/result_screen.tscn                   # M1: 结算画面
ui/settings_screen.tscn                 # M2: 设置界面

# 数据
assets/json/formations.json             # M2: 阵型配置
```

### 修改文件

```
project.godot                            # 输入映射 + 视窗 + autoload
scenes/game_manager/game_manager.gd      # 状态扩展 + 换人 + 半场
scenes/characters/player.gd              # 新属性 + 蓄力 + 新状态
scenes/characters/ball.gd                # 九态 + 辅助瞄准 + 落地预测 + 定位球
scenes/characters/ai/ai_behavior.gd     # LOD 分级
scenes/characters/ai/ai_behavior_field.gd  # 跑位 + 持球 + 防守决策
scenes/characters/ai/ai_behavior_goalie.gd # 出击 + 扑救判断
scenes/screens/world/actors_container.gd   # 11人 + 换人 + LOD分配
scenes/screens/world/world_screen.gd       # HUD + 暂停 + 半场叠加
scenes/screens/world/game_events.gd        # 新增信号
scenes/screens/soccer_game.gd              # 新增屏幕类型
utils/data_loader.gd                       # 加载新数据格式
assets/json/squads.json                    # 11人 + 新属性
```

---

## 附录 B：状态转换速查表

### 球员状态转换（进攻侧）

```
MOVING/SPRINTING
    ↓ 获得球权
DRIBBLING/DRIBBLE_SPRINT
    ├─ 短传键 → SHORT_PASSING → (球踢出) → MOVING
    ├─ 长传键(蓄力) → LONG_PASSING → (球踢出) → MOVING
    ├─ 空档键(蓄力) → THROUGH_PASSING → (球踢出) → MOVING
    ├─ 射门键(蓄力) → SHOOTING → (球射出) → MOVING
    ├─ L1 → PROTECTING_BALL → (松开L1) → DRIBBLING
    └─ 被断球 → (对方获得球权) → MOVING
```

### 球状态转换（九态）

```
持球类：
  CARRIED           — 场上球员带球（有步点）
  HELD_BY_GOALKEEPER — 门将手中抱球（静止）

飞行类：
  KICKED   — 传球/解围（有锁定时间，解析式弹道）
  SHOT     — 射门（高速，得分判定优先）

反弹类：
  SAVED     — 门将扑出（大衰减，方向可控）
  DEFLECTED — 身体挡到/反弹（中衰减，方向随机）

自由类：
  FREEFORM  — 自由滚动/弹跳

死球类：
  OUT_OF_PLAY  — 出界/吹停（冻结）
  SET_PIECE    — 定位球（静止等待开球）

关键转换：
  CARRIED ──短传/长传/直塞──→ KICKED
  CARRIED ──射门──→ SHOT
  KICKED ──球员接住──→ CARRIED
  KICKED ──门将接住──→ HELD_BY_GOALKEEPER
  SHOT ──门将扑到──→ SAVED
  SHOT ──打在门柱/后卫身上──→ DEFLECTED
  SAVED/DEFLECTED ──落地──→ FREEFORM
  KICKED/SHOT ──出界──→ OUT_OF_PLAY
  OUT_OF_PLAY ──摆球──→ SET_PIECE
  SET_PIECE ──开球──→ KICKED / SHOT
  HELD_BY_GOALKEEPER ──手抛/开大脚──→ KICKED
  FREEFORM ──球员拿到──→ CARRIED
```

---

> **设计文档版本**：v1.0
>
> **最后更新**：2026-08-20
>
> **对应 PRD**：v1.2
