# 像素无关性分析与重构方案

## 当前状况

### 已有的基础设施

项目已经有 `PitchConstants` (autoload 单例) 集中管理核心尺寸：

```gdscript
const WIDTH := 850.0
const HEIGHT := 360.0
const CENTER_X := WIDTH * 0.5  # 425.0
const CENTER_Y := HEIGHT * 0.5  # 180.0
const GRAVITY := 600.0
```

部分代码已经使用了这些常量（如 `RadarMinimap`、球的传球逻辑）。

### 硬编码问题盘点

#### 1. **距离阈值** (与球场尺寸强相关)

| 位置 | 常量 | 值 | 影响 |
|------|------|-----|------|
| `ai_behavior_field.gd` | `SHOT_DISTANCE` | 150px | 射门判断距离 |
| `ai_behavior_field.gd` | `TACKLE_DISTANCE` | 15px | 铲球触发距离 ⚠️ |
| `ai_behavior_field.gd` | `SUPPORT_RUN_ACTIVATION_DIST` | 200px | 跑位激活距离 |
| `ai_behavior_field.gd` | `SPRINT_DIST_TO_GOAL_MAX` | 425px | 过中线才冲刺 ⚠️⚠️ |
| `ai_behavior_field.gd` | `SUPPORT_CENTRAL_HOLD_DIST` | 80px | 后腰保持距离 |
| `ai_behavior_goalie.gd` | `CATCH_RADIUS` | 20px | 门将抱球范围 ⚠️ |
| `ai_behavior_goalie.gd` | `RUSH_OUT_DISTANCE` | 120px | 最大出击距离 |
| `ai_behavior_goalie.gd` | `RUSH_OUT_TRIGGER_DIST` | 150px | 触发出击距离 |
| `ai_behavior_goalie.gd` | `DISTRIBUTION_KICK_DIST` | 150px | 大脚开球距离 |
| `ai_behavior_goalie.gd` | `DIVING_SAVE_DISTANCE` | 60px | 飞身扑救距离 |
| `player_state_passing.gd` | `ASSIST_MAGNET_RANGE_SHORT` | 180px | 短传吸附范围 |
| `player_state_passing.gd` | `ASSIST_MAGNET_RANGE_LONG` | 300px | 长传吸附范围 |
| `player_state_passing.gd` | `ASSIST_MAGNET_RANGE_THROUGH` | 220px | 直塞吸附范围 |
| `ball_state_freeform.gd` | `AUTO_CAPTURE_DISTANCE` | 15px | 主动接球距离 ⚠️ |
| `ball.gd` | `DISTANCE_HIGH_PASS` | 90px | 高弧度传球阈值 |
| `ball.gd` | `KICKOFF_PASS_DISTANCE` | 30px | 开球传球距离 ⚠️ |

**标记说明：**
- ⚠️ = 可能是绝对距离（身体/物理尺度）
- ⚠️⚠️ = 明确相对距离（场地比例）

#### 2. **速度/摩擦值** (与球场尺寸和帧率相关)

| 位置 | 常量 | 值 | 类型 |
|------|------|-----|------|
| `player_state_moving.gd` | `TURN_RATE_LOW_SPEED` | 12.0 rad/s | 角速度 |
| `player_state_moving.gd` | `TURN_RATE_HIGH_SPEED` | 4.0 rad/s | 角速度 |
| `ball_state_kicked.gd` | `GROUND_FRICTION_BASE` | 60.0 px/s² | 加速度 |
| `ball_state_shot.gd` | `GROUND_FRICTION` | 120.0 px/s² | 加速度 |
| `player_state_hurt.gd` | `BALL_TUMBLE_SPEED` | 100.0 px/s | 速度 |
| `ball.gd` | `TUMBLE_HEIGHT_VELOCITY` | 180.0 px/s | 速度 |
| `ball_state_shot.gd` | `GOALIE_CATCH_SPEED` | 180.0 px/s | 速度阈值 |

#### 3. **高度阈值** (2.5D，可能是绝对的)

这些已经在 `PitchConstants` 中集中管理了：
- `HEIGHT_BALL_CONTROL_MAX` = 10px
- `HEIGHT_HEADER_MIN/MAX` = 5-30px
- `HEIGHT_VOLLEY_MIN/MAX` = 1-25px
- `CROSSBAR_HEIGHT` = 30px

#### 4. **球门位置** (硬编码在 PitchConstants)

```gdscript
const GOAL_HOME_X := 32.0
const GOAL_AWAY_X := 818.0
const GOAL_Y := 220.0
```

这些是**绝对像素位置**，依赖于场景设计。

---

## 问题场景

### 场景 1：球场尺寸翻倍
假设从 850×360 改为 1700×720：

| 问题 | 当前行为 | 期望行为 |
|------|----------|----------|
| AI 射门距离 | 仍然 150px，相对变近 | 应该 300px |
| 过中线判断 | 仍然 425px（已不是中线） | 应该 850px |
| 传球吸附 | 180px 相对变小 | 应该 360px |
| 铲球距离 | 15px（可能合理） | 可能保持 15px |
| 重力 | 600 px/s² 下落变慢 | 需要 1200 px/s²？ |

### 场景 2：改变分辨率但保持比例
从 560×360 viewport 改为 1120×720：

| 问题 | 当前行为 | 期望行为 |
|------|----------|----------|
| 球场物理 | 所有 px 值保持不变 | 应该缩放 |
| UI 缩放 | integer scale 自动处理 | ✓ 正常 |

---

## 解决方案

### 架构设计：绝对尺度 vs 相对尺度

将所有距离/速度分为两类：

#### A. **绝对尺度** (不随场地缩放)
- 球员身体尺度：铲球距离 15px、接球距离 15px
- 门将抱球半径 20px
- 球的物理尺寸相关

#### B. **相对尺度** (与场地成比例)
- AI 判断距离：射门、传球、跑位
- 场地区域判断：中线、禁区
- 球速、摩擦力、重力（保持物理感需要同步缩放）

### 实现方案

#### 1. 扩展 `PitchConstants`

```gdscript
extends Node

# ===== 基准尺寸（设计时的参考值）=====
const REFERENCE_WIDTH := 850.0
const REFERENCE_HEIGHT := 360.0

# ===== 当前尺寸（可配置）=====
const WIDTH := 850.0
const HEIGHT := 360.0

# ===== 缩放因子（自动计算）=====
const SCALE_FACTOR := WIDTH / REFERENCE_WIDTH  # 1.0 for default
const SCALE_FACTOR_Y := HEIGHT / REFERENCE_HEIGHT

# ===== 辅助函数 =====
## 将基于参考尺寸设计的"相对距离"缩放到当前场地
static func scaled(reference_value: float) -> float:
    return reference_value * SCALE_FACTOR

## 将基于参考尺寸设计的"相对速度"缩放到当前场地
static func scaled_speed(reference_speed: float) -> float:
    return reference_speed * SCALE_FACTOR

## 将基于参考尺寸设计的"相对加速度"缩放到当前场地
static func scaled_accel(reference_accel: float) -> float:
    return reference_accel * SCALE_FACTOR

## 绝对距离，不缩放（用于标记语义）
static func absolute(value: float) -> float:
    return value

# ===== 常用相对距离（基于 850×360 设计）=====
const HALFPITCH_X := CENTER_X  # 中线位置，相对的
```

#### 2. 重构所有硬编码常量

**示例：AI 行为**

```gdscript
# 原来（硬编码）
const SHOT_DISTANCE := 150
const TACKLE_DISTANCE := 15
const SPRINT_DIST_TO_GOAL_MAX := 425.0

# 重构后（语义明确）
const SHOT_DISTANCE := PitchConstants.scaled(150.0)  # 相对距离
const TACKLE_DISTANCE := PitchConstants.absolute(15.0)  # 绝对距离（身体接触）
const SPRINT_DIST_TO_GOAL_MAX := PitchConstants.HALFPITCH_X  # 使用语义常量
```

**示例：球物理**

```gdscript
# 原来
const GROUND_FRICTION_BASE := 60.0

# 重构后
const GROUND_FRICTION_BASE := PitchConstants.scaled_accel(60.0)
```

#### 3. 球门位置配置化

球门位置是场景设计的一部分，应该：
- 在场景中用节点位置定义（已有 `Goal` 节点）
- `PitchConstants` 中的 `GOAL_*_X/Y` 仅作参考或从场景读取

#### 4. 重力和垂直物理

重力是个特殊情况：
- **选项 A**：重力也缩放 → 保持抛物线形状相似
- **选项 B**：重力不缩放 → 物理感不同，但跳跃高度保持

**推荐选项 A**：
```gdscript
const GRAVITY := 600.0 * SCALE_FACTOR  # 与水平物理同步缩放
```

---

## 迁移策略

### 阶段 1：增强 `PitchConstants`（✓ 不破坏现有代码）
- 添加 `SCALE_FACTOR`、`scaled()`、`absolute()` 辅助函数
- 添加语义常量（`HALFPITCH_X` 等）

### 阶段 2：渐进式重构
按优先级逐个文件重构：

**高优先级**（影响游戏性）：
1. `ai_behavior_field.gd` - AI 判断距离
2. `ai_behavior_goalie.gd` - 门将行为
3. `player_state_passing.gd` - 传球吸附
4. `ball_state_kicked.gd` - 球物理

**中优先级**：
5. `ball.gd` - 球基础参数
6. `ball_state_shot.gd` - 射门物理
7. 其他状态文件

**低优先级**（UI/视觉）：
8. 粒子效果参数
9. 动画偏移量

### 阶段 3：验证测试
- 修改 `PitchConstants.WIDTH/HEIGHT` 为 1700×720
- 运行所有测试，检查：
  - AI 行为是否合理
  - 传球/射门是否正常
  - 碰撞检测是否准确

---

## 注意事项

### 1. 不要过度抽象
- 有些"魔法数字"是调试出来的手感参数
- 如 `SPRINT_SPEED_MULTIPLIER := 1.6` 是比例，本身就是无量纲的
- 不需要把所有常量都套 `scaled()`

### 2. 碰撞体尺寸
Godot 的 `CollisionShape2D` 是在编辑器中手动调整的，代码中的距离阈值改了，碰撞体也要同步调整（或用代码设置 `shape.radius`）。

### 3. 动画和精灵
- 精灵尺寸是固定的（16×16 像素艺术）
- 如果场地变大，可能需要调整 `sprite.scale`
- 但这会影响像素艺术的锐利度

### 4. viewport vs world 坐标
- `project.godot` 中 `viewport_width=560, viewport_height=360` 是**屏幕分辨率**
- `PitchConstants.WIDTH=850` 是**世界坐标**，超出 viewport 的部分会被裁切
- 改变 viewport 不影响世界坐标，但改变世界坐标会影响摄像机视野

---

## 推荐实施顺序

1. **立即做**：扩展 `PitchConstants` 添加 scaling 系统
2. **渐进做**：重构 AI 和物理常量（可分多次提交）
3. **最后验证**：在不同尺寸下测试游戏

---

## 示例：完整的 PitchConstants 重构

见下一个文件...
