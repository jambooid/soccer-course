# 物理推球式带球系统技术设计文档

> 版本：v1.1（重新适配）  
> 日期：2026-08-23  
> 状态：已实现并集成到 dev 分支

## 实现状态说明

**本设计已完整实现并适配到真实的 dev 分支架构（2026-08-23）：**

- ✅ **Ball.State 枚举**：新增 `DRIBBLING` 作为第 8 个状态（`CARRIED=0 ... HELD_BY_GOALKEEPER=6, DRIBBLING=7`）
- ✅ **Player 属性**：使用真实的 `technique` (30-98) 和 `defense` (24-94) 属性，而非设计初期假设的 `power` 映射
- ✅ **DribblePhysics 工具类**：所有 technique 相关函数已归一化到真实范围（`normalize_technique()` 内部处理）
- ✅ **BallStateDribbling**：核心物理推球逻辑，直接使用 `carrier.technique`
- ✅ **InterceptResolver 双接口**：
  - 旧版二元判定 `check_auto_intercept()` 保留，供 CARRIED 状态使用
  - 新版概率式 `compute_intercept_probability()` + `find_best_interceptor_probability()` 供 DRIBBLING 使用，真实 defense vs technique
- ✅ **AIBehaviorField 适配**：AI 带球时自动施加球位置修正力，保持球在可控范围内
- ✅ **调试工具**：`DribbleDebugDraw` 可视化触球区/速度向量/可控圈，`test_dribbling.gd` 数学验证
- ✅ **入口切换**：`ball_state_freeform.gd` 中拾球切换到 DRIBBLING；其他 7 个入口（断球、KICKED 被接、门将放下等）暂时保持 CARRIED（保守策略）
- ✅ **CARRIED 状态保留**：标记为 LEGACY，作为回退方案和对比参照

**关键差异（设计 vs 实现）：**

| 项 | 设计假设 | 实际实现 |
|----|---------|---------|
| technique 范围 | 0-100 | 30-98（门将 30，顶级前锋 98） |
| defense 范围 | 0-100 | 24-94（前锋 24，顶级后卫 94） |
| Ball 状态数 | 3 (CARRIED/FREEFORM/SHOT) | 8 (增加了 KICKED/SAVED/DEFLECTED/HELD_BY_GOALKEEPER/DRIBBLING) |
| power→technique 映射 | 临时方案 | 已删除，直接用真实属性 |
| InterceptResolver | 单一概率式 | 双接口（旧二元判定 + 新概率式） |
| 摩擦模型一致性 | 假设统一 | DRIBBLING 用指数，FREEFORM 用线性（已知问题，待统一） |

---

## 1. 背景与目标

### 1.1 现状问题

当前 `BallStateCarried` 采用 **"lerp 平滑跟随 + 周期性速度脉冲"** 的混合模式实现带球。核心问题：

1. **跟随阶段用 lerp 拉扯**——球被无形弹簧拉向目标位置，不是真物理，视觉上有"被拽着走"的感觉
2. **触球瞬间硬赋值速度**——方向突变时缺少惯性过渡
3. **静止时球瞬移**——从跑动到急停，球的位置有跳变
4. **变向时位置和速度可能不同步**——两者独立 lerp，极端情况下不一致
5. **断球是二元窗口**——要么能断要么不能断，缺乏层次感

### 1.2 设计目标

- **物理真实**：球的运动完全由动量和摩擦力决定，不做位置硬赋值或 lerp 拉扯
- **手感自然**：变向有弧线、急停有前冲、加速有渐进，球看起来"活"的
- **属性有意义**：`technique`、`speed`、`stamina` 等属性能通过带球手感被玩家感知
- **操作可控**：物理感是加分项，不能让玩家觉得"球控不住"
- **抢断有层次**：球离脚越远越容易被断，而不是简单的"可断/不可断"二元状态

### 1.3 设计原则

- **球永远是独立运动的**——没有任何一帧球的位置被直接设置为"球员前方 X 像素"
- **球员通过触球推动球**——不是携带，是不断地轻推
- **摩擦力是唯一的持续力**——球的速度衰减完全由摩擦决定
- **属性影响物理参数**——球员差异通过物理参数的差异体现，而不是通过"魔法修正"

---

## 2. 核心物理模型

### 2.1 球的运动方程

球在任何状态下都有独立的 `velocity` 和 `position`。带球时，球的速度只受两种作用：

#### 2.1.1 地面摩擦力

采用指数衰减模型（比线性 `move_toward` 更真实）：

```
ball.velocity *= pow(GROUND_FRICTION_PER_SEC, delta)
```

- `GROUND_FRICTION_PER_SEC := 0.35`——每秒速度衰减到原来的 35%（停止距离 ≈ 初速 × 0.95）

> ⚠️ **已知问题**：带球状态使用指数摩擦，而 FREEFORM 自由状态使用线性摩擦（`move_toward + friction_ground`）。两者衰减曲线不同，球从带球释放时会有摩擦力突变的感觉。后续建议统一为指数模型。
- 高速时减速快，低速时减速慢，符合真实滚动摩擦

#### 2.1.2 位置积分

```
ball.position += ball.velocity * delta
```

使用 `move_and_slide` 还是直接位置更新？**使用 `move_and_slide`**——球作为 `AnimatableBody2D`，需要与场景中的碰撞体（墙、球员身体）交互。在 `_physics_process` 中设置 `velocity` 后调用 `move_and_slide()`。

> 注：带球时球和球员身体之间需要有碰撞层处理——球员身体不能把自己带的球挡飞。方案：带球时球暂时不与携带者产生碰撞（通过物理层 mask 调整），但仍与其他球员和墙壁碰撞。

### 2.2 触球机制

#### 2.2.1 触球区（Touch Zone）

球员前方有一个**胶囊形/椭圆形的触球区**，代表球员的脚能够到球的范围：

- **方向**：与球员移动方向（`velocity.normalized()`）一致；静止时为球员面朝方向（`heading`）
- **长度**：`lerp(12px, 28px, technique / 100)`——技术越高，触球区越长（控球范围大）
- **宽度**：`8px`（固定值，或也随 technique 微调）
- **位置**：触球区的后端在球员身体前方约 6px 处

```
         ╭─────────────╮
 球员身体 │  触球区       │ → 移动方向
         ╰─────────────╯
      <- 长度 ->
```

#### 2.2.2 触球触发条件

全部满足时触发一次触球：

1. **球在触球区内**（位置检测）
2. **最小间隔已过**：距上次触球超过 `MIN_TOUCH_INTERVAL`（0.08s），防止连续触球导致球速无限叠加
3. **方向有效**：球员在向球的方向移动，或球向球员滚来（两者接近中）

第 3 条防止球从身后滚过球员时被"反脚勾回来"的不真实情况。

#### 2.2.3 触球冲量

触球不是直接替换球速，而是**叠加一个冲量**（保留球原有速度的惯性分量）：

```gdscript
# 推球方向 = 球员移动方向 + 随机偏移（偏移大小由 technique 决定，技术越高越准）
var push_direction := player_velocity.normalized()
var accuracy := lerp(MAX_INACCURACY, 0.0, technique / 100.0)
push_direction = push_direction.rotated(randf_range(-accuracy, accuracy))

# 推球速度 = 球员当前速度 × 推球倍率
# 倍率随速度变化：低速时倍率高（把球"拨"出去），高速时倍率低（顺势推）
var speed_factor := clamp(player_speed / player.max_speed, 0.0, 1.0)
var push_multiplier := lerp(PUSH_MULT_LOW_SPEED, PUSH_MULT_HIGH_SPEED, speed_factor)
var push_speed := player_speed * push_multiplier

# 触球效率：技术越高，球速越接近理想推球方向和速度
var efficiency := lerp(TOUCH_EFFICIENCY_MIN, TOUCH_EFFICIENCY_MAX, technique / 100.0)
ball.velocity = ball.velocity.lerp(push_direction * push_speed, efficiency)
```

关键常量（已校准）：

| 常量 | 值 | 含义 |
|------|-----|------|
| `GROUND_FRICTION_PER_SEC` | 0.35 | 每秒摩擦衰减系数（停止距离 ≈ 初速 × 0.95） |
| `TOUCH_ZONE_LEN_MIN` | 12px | 触球区最小长度（低技术） |
| `TOUCH_ZONE_LEN_MAX` | 28px | 触球区最大长度（technique=100 时） |
| `TOUCH_ZONE_WIDTH` | 8px | 触球区宽度 |
| `TOUCH_ZONE_FRONT_OFFSET` | 6px | 触球区前端距球员身体偏移 |
| `MIN_TOUCH_INTERVAL` | 0.08s | 两次触球的最小间隔 |
| `PUSH_MULT_LOW_SPEED` | 1.6 | 低速（0%）时的推球倍率 |
| `PUSH_MULT_HIGH_SPEED` | 1.35 | 高速（100%）时的推球倍率 |
| `TOUCH_EFFICIENCY_MIN` | 0.5 | 最低触球效率（technique=0） |
| `TOUCH_EFFICIENCY_MAX` | 0.9 | 最高触球效率（technique=100） |
| `MAX_INACCURACY_RAD` | 0.15 rad (~8.5°) | 最大触球方向偏差 |
| `MAX_CONTROL_DISTANCE_MIN` | 50px | 最小可控距离（低技术） |
| `MAX_CONTROL_DISTANCE_MAX` | 80px | 最大可控距离（满技术） |
| `IDLE_SPEED_THRESHOLD` | 20px/s | 静止/慢速带球阈值 |

> 为什么低速倍率反而高？因为低速时球员需要把球"拨"出去才能让球滚起来，球速需要比球员快一点才能拉开距离。高速时球员已经在快速移动，顺势一推就行，倍率太高会把球推得太远失控。

### 2.3 失控判定

如果球离球员太远（超过最大可控距离）且仍在远离球员 → 球员失去控球，球进入 `FREEFORM` 状态。

```
最大可控距离 = lerp(40px, 70px, technique / 100.0)
```

触发条件：
- 球与球员距离 > 最大可控距离
- 且 `ball.velocity.dot(ball_to_player) < 0`（球速方向背离球员）

这条规则保证了：球被推出去向前滚的正常情况不会判失控（因为球员在追），只有当球偏离了球员的控制范围且还在远离时才算丢球。

### 2.4 静止/低速带球

球员速度 < `IDLE_SPEED_THRESHOLD`（约 20px/s）时进入低速模式：

- 触球力度很小（球在脚边小幅度滚动）
- 触球频率高（因为触球区短，球很快滚回来）
- 球的整体位置稳定在球员前方约 12-14px 处

视觉效果：球员在原地"控球"，球在脚边微微来回滚动。

---

## 3. 关键场景表现

### 3.1 直线带球

球员沿直线匀速跑动时：

1. 触球 → 球被推向前方，速度略快于球员
2. 球逐渐减速（摩擦），球员追上球
3. 球再次进入触球区 → 下一次触球
4. 循环

球的运动轨迹是**波浪形速度曲线**（每次触球加速，然后减速），平均速度与球员速度匹配。视觉上球稳定地在球员前方"跳动"前进。

速度越快，每次触球推得越远，触球间隔越长（大步趟球感）；速度越慢，触球间隔越短，球越贴身。

### 3.2 变向带球

球员从向右跑突然改为向右上 45° 跑时：

1. **惯性阶段**：球继续沿原方向（右）滚动，受摩擦减速
2. **调整阶段**：球员身体已转向新方向，但球还在旧方向上，球员暂时"追着球跑"，触球区方向已经是新方向
3. **触球修正**：当球的位置滚入新方向的触球区（或球员斜向追上球），触发一次触球，把球推向新方向
4. **稳定阶段**：球沿新方向稳定滚动，恢复正常触球节奏

效果：球的运动轨迹画出一条**自然的弧线**，弧线宽度 = 球速 × 调整时间。变向角度越大、速度越快，弧线越宽。

**technique 的影响**：
- 高技术：触球区大，调整阶段短，弧线收得快，变向"利落"
- 低技术：触球区小，调整阶段长，弧线宽，容易把球"带大了"

### 3.3 急停

球员从全速跑动突然停下（松开方向键）：

1. **前冲阶段**：球继续沿原方向前冲，摩擦力逐渐减速
2. **回拉阶段**：球员停下后，如果球还在前方可控距离内，球减速滚回来或球员自动调整身体位置（通过微调用脚把球"捞"回来）
3. **静止控球**：球停在球员前方，进入低速触球模式

急停前冲距离完全由物理计算决定：`初速度² / (2 × 减速率)`。

**technique 的影响**：高技术球员球平时离脚更近、速度更匹配，急停前冲距离更短；低技术球员球前冲远，可能需要追一步。

### 3.4 加速启动

球员从静止开始加速：

1. 前几次触球力度小（球员速度低），球在脚边慢慢滚动
2. 球员速度提升 → 推球力度逐渐增大 → 球越推越远
3. 达到最高速度后，进入稳定的大步趟球节奏

自然呈现"由慢到快、步幅由小到大"的感觉，与真实带球一致。

### 3.5 背身护球（新增机制）

当球员速度很低、且附近有对方防守球员时，触发护球模式：

- 球的位置偏移：球始终保持在**远离防守者的一侧**
- 触球区调整：变小但更精准（球员用脚底拉球、脚底踩球等小动作）
- 抢断难度提升：防守者从护球侧抢断的成功率大幅降低

触发条件：
- 球员速度 < `PROTECT_SPEED_THRESHOLD`
- 防守者距离 < `PROTECT_TRIGGER_DISTANCE`
- 防守者在球员身后或侧后方

`technique` 和 `strength`（用 `power` 代替）共同决定护球稳定性。

---

## 4. 属性影响总结

| 属性 | 影响的物理参数 | 手感表现 |
|------|--------------|---------|
| **speed** | 推球基准速度、大步趟球距离 | 最高带球速度、球离脚最远距离 |
| **technique** | 触球区大小、触球效率/精度、最大可控距离、方向偏差 | 球是否贴身、变向是否利落、控球稳定性、传球/射门摆腿速度 |
| **stamina** | 体力低时触球效率下降、方向偏差增大 | 疲劳时球控不住、容易传丢射偏 |
| **power** | 推球力度上限、护球身体对抗 | 推球更有力（球滚得更远更快）、护球更稳 |
| **defense**（对方） | 抢断概率计算 | — |

---

## 5. 抢断系统改造

### 5.1 从二元窗口到连续概率

当前系统：离脚窗口（70% 时间）可断，跟随阶段（30% 时间）不可断。

新系统：**任何时候都可能被断**，但抢断成功率是连续变化的：

- 球离带球者越远 → 越容易断（防守者更容易够到球）
- 球速越慢（滚动后期） → 越容易断（球的位置更"确定"）
- 防守者从正面/侧面接近 → 比从身后更容易断
- 防守者 `defense` 越高、带球者 `technique` 越低 → 越容易断

### 5.2 抢断概率公式

```gdscript
static func compute_intercept_probability(
    defender: Player,
    dribbler: Player,
    ball_pos: Vector2,
    ball_vel: Vector2
) -> float:
    # 基础距离分：球离防守者越近分越高
    var dist_to_ball := defender.position.distance_to(ball_pos)
    var dist_score := clamp(1.0 - dist_to_ball / INTERCEPT_MAX_DISTANCE, 0.0, 1.0)

    # 角度分：防守者是否正对球的运动方向（正面拦截）
    var ball_to_defender := (defender.position - ball_pos).normalized()
    var angle_diff := abs(ball_vel.angle_to(ball_to_defender))
    var angle_score := clamp(1.0 - angle_diff / INTERCEPT_ANGLE_MAX, 0.0, 1.0)
    # 身后也能断但概率低（侧后方铲球）
    if angle_diff > PI / 2.0:
        angle_score *= 0.3

    # 相对速度分：接近速度越快，断球越突然
    var approach_speed := ball_vel.length() + defender.velocity.length()  # 简化估算
    var speed_score := clamp(approach_speed / INTERCEPT_SPEED_REF, 0.0, 1.0)

    # 属性对抗：defense vs technique
    var stat_diff := defender.defense - dribbler.technique
    var stat_factor := clamp(0.5 + stat_diff / 100.0, 0.2, 0.9)  # 范围 0.2~0.9

    # 综合概率（每秒的抢断概率，需要 × delta）
    var per_second_prob := dist_score * angle_score * speed_score * stat_factor * BASE_INTERCEPT_RATE
    return per_second_prob
```

每帧用概率判定是否抢断成功（类似射击游戏的"命中检测"）。

### 5.3 手动铲球（TACKLING）

保持现有 TACKLING 状态机制，但判定逻辑修改：

- 铲球区域基于球员实际朝向和铲球动画帧
- 命中判定基于球的实际位置和速度（不再假设球在脚边）
- 铲球失败后球员进入 HURT/RECOVERING 状态，球继续滚动

### 5.4 手动断球（切换球员后按断球键）

新增或完善手动断球：玩家控制防守球员按断球键（如短传键在防守时变为断球），触发伸脚断球动作。判定逻辑与自动抢断类似，但：
- 触发时机由玩家控制（更精准）
- 断球范围稍大（主动伸脚）
- 失败有惩罚（可能被过掉）

---

## 6. 架构与文件改动

### 6.1 文件清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `utils/dribble_physics.gd` | **新增** | 静态工具类：所有带球物理计算的集中地 |
| `scenes/ball/ball_states/ball_state_dribbling.gd` | **新增** | 新的带球状态，替换 ball_state_carried.gd |
| `scenes/ball/ball.gd` | 修改 | 增加 `apply_impulse()` 方法；增加 `ground_friction` 导出参数；State 枚举新增 DRIBBLING |
| `scenes/ball/ball_states/ball_state_carried.gd` | 删除/保留 | 功能迁移到 DRIBBLING。如保留，仅用于门将双手抱球后的短暂过渡 |
| `scenes/ball/ball_state_factory.gd` | 修改 | 注册 DRIBBLING 状态 |
| `utils/intercept_resolver.gd` | 修改 | 重写为基于概率的连续判定 |
| `scenes/characters/player.gd` | 修改 | 增加触球区相关导出参数；适配新状态名 |
| `scenes/characters/character_states/player_state_moving.gd` | 微调 | 带球相关查询适配新状态名；护球模式触发 |
| `scenes/characters/ai/ai_behavior_field.gd` | 修改 | AI 带球决策适配新物理模型 |
| `scenes/ball/ball_states/ball_state_freeform.gd` | 微调 | 球员接球时进入 DRIBBLING 而非 CARRIED |
| `scenes/ball/ball_states/ball_state_kicked.gd` | 微调 | 接球进入 DRIBBLING |
| `scenes/ball/ball_states/ball_state_saved.gd` | 微调 | 接球进入 DRIBBLING |
| `scenes/ball/ball_states/ball_state_deflected.gd` | 微调 | 接球进入 DRIBBLING |
| `scenes/ball/ball_states/ball_state_held_by_goalkeeper.gd` | 微调 | 门将放球后进入 DRIBBLING |

### 6.2 DribblePhysics 工具类（核心）

```gdscript
class_name DribblePhysics
extends RefCounted

# ---- 常量（可调参） ----
const GROUND_FRICTION_PER_SEC := 0.35
const TOUCH_ZONE_LEN_MIN := 12.0
const TOUCH_ZONE_LEN_MAX := 28.0
const TOUCH_ZONE_WIDTH := 8.0
const TOUCH_ZONE_FRONT_OFFSET := 6.0
const MIN_TOUCH_INTERVAL := 0.08
const PUSH_MULT_LOW_SPEED := 1.6
const PUSH_MULT_HIGH_SPEED := 1.35
const TOUCH_EFFICIENCY_MIN := 0.5
const TOUCH_EFFICIENCY_MAX := 0.9
const MAX_INACCURACY_RAD := 0.15
const MAX_CONTROL_DISTANCE_MIN := 50.0
const MAX_CONTROL_DISTANCE_MAX := 80.0
const IDLE_SPEED_THRESHOLD := 20.0

# ---- 纯函数方法 ----

static func apply_friction(velocity: Vector2, delta: float) -> Vector2:
    return velocity * pow(GROUND_FRICTION_PER_SEC, delta)

static func get_touch_zone_length(technique: float) -> float:
    return lerp(TOUCH_ZONE_LEN_MIN, TOUCH_ZONE_LEN_MAX, technique / 100.0)

static func get_max_control_distance(technique: float) -> float:
    return lerp(MAX_CONTROL_DISTANCE_MIN, MAX_CONTROL_DISTANCE_MAX, technique / 100.0)

static func is_ball_in_touch_zone(
    ball_pos: Vector2,
    player_pos: Vector2,
    player_dir: Vector2,
    technique: float
) -> bool:
    # 将球位置转换到球员局部坐标系（球员朝向为 +x 轴）
    var to_ball := ball_pos - player_pos
    var local_x := to_ball.dot(player_dir)
    var local_y := abs(to_ball.dot(player_dir.rotated(PI / 2.0)))

    var zone_length := get_touch_zone_length(technique)
    var zone_front_offset := 6.0  # 触球区前端在身体前 6px

    # 胶囊形检测：在长度范围内，且宽度在范围内
    if local_x < 0 or local_x > zone_front_offset + zone_length:
        return false
    return local_y <= TOUCH_ZONE_WIDTH / 2.0

static func compute_touch_impulse(
    ball_velocity: Vector2,
    player_velocity: Vector2,
    player_max_speed: float,
    technique: float
) -> Vector2:
    var player_speed := player_velocity.length()
    if player_speed < 1.0:
        return Vector2.ZERO

    var player_dir := player_velocity.normalized()

    # 方向精度（随机偏移）
    var accuracy_angle := lerp(MAX_INACCURACY_RAD, 0.0, technique / 100.0)
    var push_dir := player_dir.rotated(randf_range(-accuracy_angle, accuracy_angle))

    # 推球倍率：低速高、高速低
    var speed_factor := clamp(player_speed / player_max_speed, 0.0, 1.0)
    var push_multiplier := lerp(PUSH_MULT_LOW_SPEED, PUSH_MULT_HIGH_SPEED, speed_factor)
    var push_speed := player_speed * push_multiplier

    # 触球效率：lerp 向目标速度
    var efficiency := lerp(TOUCH_EFFICIENCY_MIN, TOUCH_EFFICIENCY_MAX, technique / 100.0)
    return ball_velocity.lerp(push_dir * push_speed, efficiency)

static func predict_ball_position(
    ball_pos: Vector2,
    ball_vel: Vector2,
    t: float
) -> Vector2:
    # 预测 t 秒后球的位置（考虑摩擦）
    # 积分：v(t) = v0 * f^t, x(t) = x0 + v0 * (f^t - 1) / ln(f)
    var friction_pow := pow(GROUND_FRICTION_PER_SEC, t)
    if abs(GROUND_FRICTION_PER_SEC - 1.0) < 0.001:
        return ball_pos + ball_vel * t
    var displacement := ball_vel * (friction_pow - 1.0) / log(GROUND_FRICTION_PER_SEC)
    return ball_pos + displacement

static func compute_stop_distance(ball_speed: float) -> float:
    # 计算球从当前速度到完全停下的距离
    if abs(GROUND_FRICTION_PER_SEC - 1.0) < 0.001:
        return INF
    return ball_speed / -log(GROUND_FRICTION_PER_SEC)
```

### 6.3 BallStateDribbling 状态结构

```gdscript
class_name BallStateDribbling
extends BallState

signal state_transition_requested(new_state, data)

@onready var ball := get_parent() as Ball
var carrier: Player
var touch_cooldown := 0.0

func setup(carrier_arg: Player) -> void:
    carrier = carrier_arg

func _enter_tree() -> void:
    # 初始化：确保球有速度（如果刚接球，给一个与球员同向的初速度）
    if ball.velocity.length() < 10.0 and carrier:
        ball.velocity = carrier.velocity.normalized() * carrier.speed * 0.5

func _physics_process(delta: float) -> void:
    if not carrier or not is_instance_valid(carrier):
        _release_ball()
        return

    touch_cooldown = max(0.0, touch_cooldown - delta)

    # 1. 应用摩擦力
    ball.velocity = DribblePhysics.apply_friction(ball.velocity, delta)

    # 2. 移动球（move_and_slide 由 ball.gd 的 _physics_process 处理？）
    # 这里只需更新速度，物理移动在 ball 节点的 _physics_process 中进行
    # 需确认：ball 状态是否每帧控制 ball.velocity，ball.gd 统一 move_and_slide

    # 3. 失控检测
    var to_ball := ball.position - carrier.position
    var dist := to_ball.length()
    var max_control := DribblePhysics.get_max_control_distance(carrier.technique)
    if dist > max_control and ball.velocity.dot(to_ball) > 0:
        _release_ball()
        return

    # 4. 触球检测
    if touch_cooldown <= 0.0:
        var player_dir := _get_player_direction()
        if DribblePhysics.is_ball_in_touch_zone(ball.position, carrier.position, player_dir, carrier.technique):
            var new_vel := DribblePhysics.compute_touch_impulse(
                ball.velocity, carrier.velocity, carrier.speed, carrier.technique
            )
            if new_vel.length() > ball.velocity.length():
                ball.velocity = new_vel
                touch_cooldown = DribblePhysics.MIN_TOUCH_INTERVAL

    # 5. 自动抢断检测
    _check_auto_intercept(delta)

func _get_player_direction() -> Vector2:
    if carrier.velocity.length() > 5.0:
        return carrier.velocity.normalized()
    return carrier.heading

func _release_ball() -> void:
    state_transition_requested.emit(Ball.State.FREEFORM, BallStateData.build())

func _check_auto_intercept(delta: float) -> void:
    # 遍历球附近的对方球员，计算抢断概率
    # 使用 ball.player_proximity_area 的监测
    pass
```

### 6.4 与现有系统的集成点

#### Ball 状态枚举

在 `Ball.State` 中新增 `DRIBBLING`，逐步替换 `CARRIED` 的使用场景。

#### 接球进入带球

所有从其他状态进入带球的路径（FREEFORM、KICKED、SAVED、DEFLECTED、HELD_BY_GOALKEEPER）改为进入 `DRIBBLING` 而非 `CARRIED`。

#### Player.control_ball()

保持接口不变，内部触发 `Ball.State.DRIBBLING`。

#### GameEvents 信号

`ball_possessed`、`ball_possessed_by`、`ball_released` 信号保持不变，由新的 DRIBBLING 状态在进入/退出时发射。

---

## 7. AI 适配

### 7.1 AI 带球决策调整

`AIBehaviorField` 的带球决策需要适配新模型：

- **推进时机**：AI 需要判断当前球的位置是否适合继续带球（球在可控范围内）
- **变向过人**：高技术 AI 会利用变向弧线过人；低技术 AI 更倾向传球
- **传球时机**：当球刚被触球（球速最高、位置最靠前）时是出球的最佳时机
- **护球决策**：面对紧逼防守时，选择背身护球还是传球摆脱

### 7.2 AI 跑动路线

AI 带球时的跑动方向需要考虑球的实际位置：
- 球在左前方 → 稍微向左跑以便回到球后
- 球偏离方向 → AI 自动修正路线追球

这部分可以通过"朝球的前方跑"的简单策略实现：AI 的目标点 = 球的位置 + 理想方向 × 触球距离。

---

## 8. 调试与测试策略

### 8.1 分阶段调试

| 阶段 | 目标 | 调试参数 | 验证标准 |
|------|------|---------|---------|
| 1. 基础物理 | 球滚动自然 | `GROUND_FRICTION_PER_SEC` | 踢一脚球，滚动距离合理，停球自然 |
| 2. 直线带球 | 球稳定在身前 | `PUSH_MULT_*`、`TOUCH_ZONE_LEN_*`、`MIN_TOUCH_INTERVAL` | 匀速带球时球不远离也不撞脚 |
| 3. 变向手感 | 弧线自然、响应够用 | `TOUCH_EFFICIENCY_*`、`TOUCH_ZONE_WIDTH` | 90°变向时弧线圆滑，不会失控 |
| 4. 属性差异 | 高低技术球员手感明显不同 | 所有 technique 插值 | 用 technique=20 和 technique=90 的球员对比测试 |
| 5. 抢断平衡 | 攻防平衡 | `InterceptResolver` 参数 | 平均每场抢断次数在合理范围 |
| 6. AI 适配 | AI 带球正常 | AI 决策参数 | CPU vs CPU 比赛能正常进球 |

### 8.2 测试场景

新增 `tools/test_dribbling.gd`：

1. **直线带球稳定性测试** — 球员带球直线跑 5 秒，球是否始终在可控范围内
2. **变向弧线测试** — 90° 变向，记录球的轨迹，验证弧线形状
3. **急停距离测试** — 全速急停，测量球前冲距离
4. **属性对比测试** — 不同 technique 球员的带球差异量化
5. **抢断概率测试** — 不同距离/角度下的抢断触发频率
6. **长时间带球测试** — AI 带球 30 秒不丢球（验证稳定性）

### 8.3 调试可视化

建议增加一个 debug 绘制模式（通过 `--debug-dribble` 或调试按键切换）：
- 绘制触球区（绿色半透明胶囊）
- 绘制球的速度向量（黄色箭头）
- 绘制最大可控距离圈（白色虚线圆）
- 显示触球计数器、当前球速、距上次触球时间等数值

---

## 9. 风险与回退

### 9.1 主要风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 物理参数调崩，带球完全失控 | 高 | 保留 `ball_state_carried.gd` 作为回退方案，通过配置切换 |
| AI 不适应新物理，带球频繁丢球 | 中 | AI 带球决策增加"安全阈值"，AI 球员默认 technique 稍高 |
| 抢断概率失衡，进球率大幅变化 | 中 | 分阶段调参，用自动化测试监控进球率变化 |
| 性能开销增加（每帧物理计算更多） | 低 | 所有计算都是简单的向量运算，开销极小 |
| 玩家操作手感变化太大，不适应 | 中 | 提供"操作模式"选项（物理模式/经典模式），或通过 difficulty 调整 |

### 9.2 回退方案

实现过程中保留 `Ball.State.CARRIED` 状态不删除，通过项目设置或全局常量切换使用 CARRIED 还是 DRIBBLING。如果新系统调不好，可以快速回退。

---

## 10. 实施里程碑

| 里程碑 | 内容 | 预计工作量 |
|--------|------|-----------|
| M1 | DribblePhysics 工具类 + 单元测试 | 基础框架 |
| M2 | BallStateDribbling 基本带球（直线+摩擦+触球） | 核心物理 |
| M3 | 失控检测 + 所有状态切换到 DRIBBLING | 集成替换 |
| M4 | 抢断系统改造（概率化） | 攻防交互 |
| M5 | 护球机制 + 属性精细调参 | 深度优化 |
| M6 | AI 适配 + 整体平衡调试 | 游戏性完善 |
| M7 | 测试 + 调试可视化 + 文档 | 收尾 |

---

## 附录 A：实现状态说明（v1 实际实现）

当前 v1 实现与设计文档的几点差异说明：

### A.1 Player 属性简化

Player 类目前只有 `speed` 和 `power` 两个属性，**没有** `technique`、`defense`、`stamina`、`jump` 属性。

- 带球物理中的 `technique` 暂时由 `power` 属性映射替代：`power` 范围约 100~188 → technique ≈ 17~90
- 抢断系统中的 `defense vs technique` 对抗暂时用 `power vs power` 代替
- 后续添加完整球员属性后，可直接替换映射，无需改动物理核心逻辑

### A.2 抢断系统为新建

设计文档第 4 章描述的"抢断系统改造"实际是从零创建 `InterceptResolver`（原代码中不存在）。当前实现为基础版本：
- 四维因子：距离、角度、速度、属性
- 概率式判定（连续值，非二元窗口）
- 每 3 帧检测一次（性能优化）
- 自动从 `player_proximity_area` 筛选候选防守者

### A.3 已知问题：摩擦模型不一致

- 带球状态（DRIBBLING）使用**指数衰减**摩擦（`DribblePhysics.apply_friction`，f=0.35）
- 自由状态（FREEFORM）使用**线性衰减**摩擦（`move_toward + ball.friction_ground`）
- 两者衰减曲线不同，球从带球释放时会有"突兀的摩擦力变化"
- 建议后续统一为同一种摩擦模型（推荐统一为指数模型）

### A.4 回退方案（已就绪）

- `Ball.State.CARRIED` 状态完整保留（标记为 LEGACY）
- `BallStateCarried` 类文件未删除
- 如需回退，只需将 `ball_state_freeform.gd` 中的 `Ball.State.DRIBBLING` 改回 `Ball.State.CARRIED`

### A.5 未实现的设计功能

以下设计功能在 v1 中暂未实现，留待后续迭代：

- **背身护球机制**（第 3.5 节）：需要新增护球状态和 AI 决策
- **stamina 体力影响**：Player 暂无 stamina 属性
- **手动断球键**：防守时按断球键主动伸脚
- **球的视觉滚动/弹跳**：带球时球的高度变化（纯视觉）

---

## 附录 B：参考资料

- 实况足球（WE2000/PES）带球机制研究：`docs/we2000-core-techniques.md`、`docs/we2000-implementation-research.md`
- 现有带球状态：`scenes/ball/ball_states/ball_state_carried.gd`
- 抢断系统：`utils/intercept_resolver.gd`
- 球员状态：`scenes/characters/player.gd`
