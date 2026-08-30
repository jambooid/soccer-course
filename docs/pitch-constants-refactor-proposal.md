# PitchConstants 重构提案

## 目标

实现像素无关性，使游戏能够在不同球场尺寸下保持一致的游戏性。

## 新的 PitchConstants 设计

```gdscript
extends Node

## 统一的球场坐标常量（Autoload 单例）
## 
## 设计哲学：
## - 定义一个"参考尺寸"（850×360），所有游戏参数基于此调试
## - 提供缩放系统，当改变实际尺寸时，相对距离/速度自动缩放
## - 区分"绝对尺度"（身体接触）和"相对尺度"（场地比例）

# ========================================
# 基准尺寸（参考设计值）
# ========================================
const REFERENCE_WIDTH := 850.0
const REFERENCE_HEIGHT := 360.0

# ========================================
# 实际尺寸（可配置）
# ========================================
## 修改这两个值即可缩放整个游戏世界
const WIDTH := 850.0
const HEIGHT := 360.0

# ========================================
# 缩放因子（自动计算）
# ========================================
const SCALE_FACTOR := WIDTH / REFERENCE_WIDTH
const SCALE_FACTOR_Y := HEIGHT / REFERENCE_HEIGHT

# ========================================
# 基础几何
# ========================================
const CENTER_X := WIDTH * 0.5
const CENTER_Y := HEIGHT * 0.5
const MIN_X := 0.0
const MAX_X := WIDTH
const MIN_Y := 0.0
const MAX_Y := HEIGHT

# ========================================
# 语义化位置（相对）
# ========================================
const HALFPITCH_X := CENTER_X  ## 中线位置

# ========================================
# 球门相关（TODO: 应该从场景节点读取，而非硬编码）
# ========================================
## 这些值是基于 850×360 设计的，如果改变尺寸需要同步调整
## 更好的做法是在场景中放置 Goal 节点，代码从节点读取位置
const GOAL_HOME_X := 32.0 * SCALE_FACTOR
const GOAL_AWAY_X := 818.0 * SCALE_FACTOR
const GOAL_Y := 220.0 * SCALE_FACTOR_Y
const CROSSBAR_HEIGHT := 30.0  ## 这是 2.5D 高度，可能是绝对值

# ========================================
# 2.5D 物理（竖直方向）
# ========================================
## 重力缩放策略：与水平尺度同步缩放，保持抛物线形状相似
const GRAVITY := 600.0 * SCALE_FACTOR

## 高度阈值（这些可能是绝对值，因为是基于球员身高/视觉设计）
## 如果球员精灵大小不变，这些值可能也不应该缩放
const MAX_BALL_HEIGHT := 50.0

const HEIGHT_BALL_CONTROL_MAX := 10.0
const HEIGHT_KICKED_PICKUP_MAX := 12.0
const HEIGHT_FREEFORM_PICKUP_MAX := 25.0
const HEIGHT_SAVED_GOALIE_CATCH := 15.0
const HEIGHT_SAVED_PLAYER_PICKUP := 8.0
const HEIGHT_DEFLECTED_PICKUP_MAX := 10.0
const HEIGHT_GOALIE_CATCH_MAX := 25.0
const HEIGHT_HEADER_MIN := 5.0
const HEIGHT_HEADER_MAX := 30.0
const HEIGHT_VOLLEY_MIN := 1.0
const HEIGHT_VOLLEY_MAX := 25.0

# ========================================
# 辅助函数
# ========================================

## 将基于参考尺寸设计的"相对距离"缩放到当前场地
## 用法：const SHOT_DISTANCE := PitchConstants.scaled(150.0)
static func scaled(reference_distance: float) -> float:
	return reference_distance * SCALE_FACTOR

## 将基于参考尺寸设计的"相对速度"（px/s）缩放到当前场地
## 物理一致性：速度和距离应同步缩放
static func scaled_speed(reference_speed: float) -> float:
	return reference_speed * SCALE_FACTOR

## 将基于参考尺寸设计的"相对加速度"（px/s²）缩放到当前场地
## 物理一致性：加速度、摩擦力应同步缩放
static func scaled_accel(reference_accel: float) -> float:
	return reference_accel * SCALE_FACTOR

## 标记为绝对距离，不缩放（语义化，增强代码可读性）
## 用于：球员身体接触范围、碰撞检测等与物理尺寸相关的值
## 用法：const TACKLE_DISTANCE := PitchConstants.absolute(15.0)
static func absolute(value: float) -> float:
	return value

## 从世界坐标到小地图坐标的缩放因子
static func get_minimap_scale(minimap_size: Vector2) -> Vector2:
	return Vector2(
		minimap_size.x / WIDTH,
		minimap_size.y / HEIGHT
	)
```

## 重构清单

### 文件：`scenes/characters/ai/ai_behavior_field.gd`

```gdscript
# 【重构前】
const SHOT_DISTANCE := 150
const TACKLE_DISTANCE := 15
const SUPPORT_CENTRAL_HOLD_DIST := 80.0
const SUPPORT_RUN_ACTIVATION_DIST := 200.0
const SPRINT_TECH_THRESHOLD := 60.0  # 这是属性值，不需要缩放
const SPRINT_DIST_TO_GOAL_MAX := 425.0

# 【重构后】
const SHOT_DISTANCE := PitchConstants.scaled(150.0)  # 相对：射门判断区域
const TACKLE_DISTANCE := PitchConstants.absolute(15.0)  # 绝对：身体接触范围
const SUPPORT_CENTRAL_HOLD_DIST := PitchConstants.scaled(80.0)  # 相对：战术位置
const SUPPORT_RUN_ACTIVATION_DIST := PitchConstants.scaled(200.0)  # 相对：跑位触发
const SPRINT_TECH_THRESHOLD := 60.0  # 无量纲，属性阈值
const SPRINT_DIST_TO_GOAL_MAX := PitchConstants.HALFPITCH_X  # 语义：过中线
```

### 文件：`scenes/characters/ai/ai_behavior_goalie.gd`

```gdscript
# 【重构前】
const CATCH_RADIUS := 20.0
const RUSH_OUT_DISTANCE := 120.0
const RUSH_OUT_TRIGGER_DIST := 150.0
const DISTRIBUTION_KICK_DIST := 150.0
const DIVING_SAVE_DISTANCE := 60.0

# 【重构后】
const CATCH_RADIUS := PitchConstants.absolute(20.0)  # 绝对：手臂范围
const RUSH_OUT_DISTANCE := PitchConstants.scaled(120.0)  # 相对：战术距离
const RUSH_OUT_TRIGGER_DIST := PitchConstants.scaled(150.0)  # 相对：判断距离
const DISTRIBUTION_KICK_DIST := PitchConstants.scaled(150.0)  # 相对：开球距离
const DIVING_SAVE_DISTANCE := PitchConstants.scaled(60.0)  # 相对：扑救触发
```

### 文件：`scenes/characters/character_states/player_state_moving.gd`

```gdscript
# 【重构前】
const TURN_RATE_LOW_SPEED := 12.0  # rad/s
const TURN_RATE_HIGH_SPEED := 4.0  # rad/s
const CUTBACK_ANGLE_THRESHOLD := deg_to_rad(90.0)
const CUTBACK_SPEED_PENALTY := 0.6
const SPRINT_SPEED_MULTIPLIER := 1.6

# 【重构后】
# 角速度和比例系数都是无量纲的，不需要缩放
const TURN_RATE_LOW_SPEED := 12.0
const TURN_RATE_HIGH_SPEED := 4.0
const CUTBACK_ANGLE_THRESHOLD := deg_to_rad(90.0)
const CUTBACK_SPEED_PENALTY := 0.6
const SPRINT_SPEED_MULTIPLIER := 1.6
```

### 文件：`scenes/characters/character_states/player_state_passing.gd`

```gdscript
# 【重构前】
const ASSIST_MAGNET_RANGE_SHORT := 180.0
const ASSIST_MAGNET_RANGE_LONG := 300.0
const ASSIST_MAGNET_RANGE_THROUGH := 220.0

# 【重构后】
const ASSIST_MAGNET_RANGE_SHORT := PitchConstants.scaled(180.0)
const ASSIST_MAGNET_RANGE_LONG := PitchConstants.scaled(300.0)
const ASSIST_MAGNET_RANGE_THROUGH := PitchConstants.scaled(220.0)
```

### 文件：`scenes/characters/character_states/player_state_hurt.gd`

```gdscript
# 【重构前】
const BALL_TUMBLE_SPEED := 100.0

# 【重构后】
const BALL_TUMBLE_SPEED := PitchConstants.scaled_speed(100.0)
```

### 文件：`scenes/ball/ball.gd`

```gdscript
# 【重构前】
const BOUNCINESS := 0.8  # 无量纲
const DISTANCE_HIGH_PASS := 90
const DURATION_TUMBLE_LOCK := 200  # ms，时间不需缩放
const DURATION_PASS_LOCK := 500
const KICKOFF_PASS_DISTANCE := 30.0
const TUMBLE_HEIGHT_VELOCITY := 180.0

# 【重构后】
const BOUNCINESS := 0.8
const DISTANCE_HIGH_PASS := PitchConstants.scaled(90.0)
const DURATION_TUMBLE_LOCK := 200
const DURATION_PASS_LOCK := 500
const KICKOFF_PASS_DISTANCE := PitchConstants.absolute(30.0)  # 开球短传，绝对距离
const TUMBLE_HEIGHT_VELOCITY := PitchConstants.scaled_speed(180.0)  # 垂直速度
```

### 文件：`scenes/ball/ball_states/ball_state_kicked.gd`

```gdscript
# 【重构前】
const AIR_FRICTION_MULTIPLIER := 0.3  # 无量纲
const GROUND_FRICTION_BASE := 60.0
const TRANSITION_TO_FREEFORM_SPEED := 20.0
const MAX_BOUNCES_BEFORE_FREEFORM := 3  # 整数计数

# 【重构后】
const AIR_FRICTION_MULTIPLIER := 0.3
const GROUND_FRICTION_BASE := PitchConstants.scaled_accel(60.0)
const TRANSITION_TO_FREEFORM_SPEED := PitchConstants.scaled_speed(20.0)
const MAX_BOUNCES_BEFORE_FREEFORM := 3
```

### 文件：`scenes/ball/ball_states/ball_state_shot.gd`

```gdscript
# 【重构前】
const DURATION_SHOT := 1500  # ms
const SHOT_HEIGHT := 8.0
const SHOT_SPRITE_SCALE := 0.8  # 无量纲
const AIR_FRICTION_MULTIPLIER := 0.2
const GROUND_FRICTION := 120.0
const SHOT_DROP_MS := 600
const GOALIE_CATCH_SPEED := 180.0

# 【重构后】
const DURATION_SHOT := 1500
const SHOT_HEIGHT := 8.0  # 可能是绝对的（视觉设计）
const SHOT_SPRITE_SCALE := 0.8
const AIR_FRICTION_MULTIPLIER := 0.2
const GROUND_FRICTION := PitchConstants.scaled_accel(120.0)
const SHOT_DROP_MS := 600
const GOALIE_CATCH_SPEED := PitchConstants.scaled_speed(180.0)
```

### 文件：`scenes/ball/ball_states/ball_state_freeform.gd`

```gdscript
# 【重构前】
const AUTO_CAPTURE_DISTANCE := 15.0
const AUTO_CAPTURE_CHECK_INTERVAL := 3  # 帧数

# 【重构后】
const AUTO_CAPTURE_DISTANCE := PitchConstants.absolute(15.0)  # 接球范围，身体尺度
const AUTO_CAPTURE_CHECK_INTERVAL := 3
```

### 文件：`scenes/ball/ball_states/ball_state_carried.gd`

```gdscript
# 【重构前】
const TOUCH_INTERVAL_MIN := 0.14  # 秒
const TOUCH_INTERVAL_MAX := 0.32
const TOUCH_OFFSET_MIN := 8.0
const TOUCH_OFFSET_MAX := 20.0
const FREE_BALL_RATIO := 0.7
const BALL_SPEED_MULTIPLIER := 1.15
const FOLLOW_LERP_FACTOR := 12.0

# 【重构后】
const TOUCH_INTERVAL_MIN := 0.14
const TOUCH_INTERVAL_MAX := 0.32
const TOUCH_OFFSET_MIN := PitchConstants.absolute(8.0)  # 带球距离，视觉尺度
const TOUCH_OFFSET_MAX := PitchConstants.absolute(20.0)
const FREE_BALL_RATIO := 0.7
const BALL_SPEED_MULTIPLIER := 1.15
const FOLLOW_LERP_FACTOR := 12.0  # lerp 系数，无量纲（或需实验调整）
```

## 实施步骤

### 第 1 步：更新 `utils/pitch_constants.gd`
- 添加 `REFERENCE_WIDTH/HEIGHT`
- 添加 `SCALE_FACTOR`
- 添加辅助函数 `scaled()`, `scaled_speed()`, `scaled_accel()`, `absolute()`
- 更新现有常量使用缩放

### 第 2 步：逐文件重构
按以下顺序：
1. AI 行为文件（`ai_behavior_*.gd`）
2. 球状态文件（`ball_states/*.gd`）
3. 玩家状态文件（`character_states/*.gd`）
4. 球主文件（`ball.gd`）

### 第 3 步：测试验证
1. 保持 `WIDTH=850, HEIGHT=360`，运行所有测试，确保无回归
2. 修改为 `WIDTH=1700, HEIGHT=720`，测试游戏性是否一致
3. 修改为 `WIDTH=425, HEIGHT=180`，测试小场地

### 第 4 步：文档更新
- 更新 `CLAUDE.md` 说明缩放系统
- 在 `docs/` 中添加"如何调整球场尺寸"指南

## 潜在陷阱

### 1. 碰撞体尺寸
场景文件（`.tscn`）中的 `CollisionShape2D` 尺寸是硬编码的，需要：
- 选项 A：手动调整每个场景的碰撞体
- 选项 B：在代码中动态设置：`$CollisionShape2D.shape.radius *= PitchConstants.SCALE_FACTOR`

### 2. 精灵缩放
如果场地变大，球员精灵可能显得太小，需要：
```gdscript
player_sprite.scale = Vector2.ONE * PitchConstants.SCALE_FACTOR
```
但这会破坏像素艺术的锐利度（非整数缩放）。

### 3. 摄像机视野
场地变大后，摄像机可能看不到全场，需要调整 `Camera2D.zoom`。

### 4. 平衡性测试
所有常量基于 850×360 调试，改变尺寸后需要重新平衡：
- AI 的射门/传球时机
- 门将的反应距离
- 球的摩擦力（影响传球距离）

## 建议

**保守策略**：
- 只缩放明确的"相对距离"（AI 判断、战术位置）
- 绝对距离（接触、碰撞）保持不变
- 速度和加速度谨慎缩放（影响手感）

**激进策略**：
- 整个物理系统同步缩放
- 保持运动学相似性（相同的时间打过全场）

**推荐起始点**：保守策略 + 充分测试。
