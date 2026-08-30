# 像素无关性重构检查清单

## 快速判断：这个常量需要缩放吗？

### ✅ 需要缩放的（相对尺度）

| 类型 | 示例 | 判断标准 |
|------|------|----------|
| **AI 判断距离** | 射门距离 150px | "离球门多远开始射门" - 场地大则应该更远 |
| **战术位置** | 后腰保持距离 80px | "站位布局" - 与场地比例相关 |
| **传球范围** | 短传吸附 180px | "传球能覆盖的区域" - 场地大则范围应更大 |
| **场地区域** | 过中线 425px | "半场、禁区" - 明确的场地比例 |
| **球速/摩擦** | 地面摩擦 60 px/s² | "球滚动多远停下" - 与场地尺寸相关 |
| **冲刺速度** | 100 px/s | "多久跑完全场" - 保持相对速度感 |

### ❌ 不需要缩放的（绝对尺度）

| 类型 | 示例 | 判断标准 |
|------|------|----------|
| **身体接触** | 铲球距离 15px | "脚能触及的范围" - 与球员身体尺寸相关 |
| **碰撞检测** | 接球距离 15px | "身体碰到球" - 物理接触 |
| **视觉设计** | 带球偏移 8-20px | "球在脚边的视觉距离" - 与精灵大小相关 |
| **2.5D 高度** | 头球高度 5-30px | "跳起高度" - 与球员身高相关（除非精灵也缩放）|
| **无量纲比例** | 冲刺倍数 1.6 | "加速是基础速度的 1.6 倍" - 本身就是比例 |
| **时间/帧数** | 锁定 200ms / 3 帧 | "持续时间" - 与空间尺度无关 |
| **角度** | 急转阈值 90° | "转向角度" - 几何角度不变 |

### 🤔 需要实验的（灰色地带）

| 类型 | 建议 | 原因 |
|------|------|------|
| **转向速率** | 不缩放 | rad/s 是角速度，与线性尺度无关 |
| **跟随系数** | 不缩放 | lerp 因子是收敛速率，数学特性 |
| **空气摩擦倍数** | 不缩放 | 无量纲系数 |
| **门将扑救** | 缩放 | 虽然是身体动作，但覆盖范围与球门大小相关 |

---

## 代码模式速查

### Pattern 1: 简单距离

```gdscript
# ❌ 硬编码
const SHOT_DISTANCE := 150

# ✅ 相对距离
const SHOT_DISTANCE := PitchConstants.scaled(150.0)

# ✅ 绝对距离
const TACKLE_DISTANCE := PitchConstants.absolute(15.0)
```

### Pattern 2: 语义化位置

```gdscript
# ❌ 魔法数字
const SPRINT_DIST_TO_GOAL_MAX := 425.0  # 场地一半

# ✅ 使用语义常量
const SPRINT_DIST_TO_GOAL_MAX := PitchConstants.HALFPITCH_X
```

### Pattern 3: 速度

```gdscript
# ❌ 硬编码速度
const BALL_TUMBLE_SPEED := 100.0  # px/s

# ✅ 缩放速度
const BALL_TUMBLE_SPEED := PitchConstants.scaled_speed(100.0)
```

### Pattern 4: 加速度/摩擦

```gdscript
# ❌ 硬编码摩擦力
const GROUND_FRICTION := 60.0  # px/s²

# ✅ 缩放加速度
const GROUND_FRICTION := PitchConstants.scaled_accel(60.0)
```

### Pattern 5: 无量纲保持不变

```gdscript
# ✅ 比例、系数、角度都不需要改
const SPRINT_MULTIPLIER := 1.6        # 无量纲
const CUTBACK_PENALTY := 0.6          # 无量纲
const TURN_RATE := 12.0               # rad/s，角速度
const CUTBACK_ANGLE := deg_to_rad(90) # 角度
const BOUNCINESS := 0.8               # 弹性系数
```

### Pattern 6: 时间不变

```gdscript
# ✅ 时间、帧数都不需要缩放
const HOLD_DURATION_MS := 3000
const SHOT_DROP_MS := 600
const CHECK_INTERVAL := 3  # 帧数
const TOUCH_INTERVAL := 0.14  # 秒
```

---

## 重构工作流

### Step 1: 扫描文件
```bash
grep -n "const.*:=.*[0-9]" your_file.gd
```

### Step 2: 逐个判断
对每个常量问自己：
1. **这个值的含义是什么？** （距离、速度、时间、比例？）
2. **如果场地变成 2 倍大，这个值应该是多少？** （2 倍、不变、需实验？）
3. **它跟什么对比？** （场地、球员、球、时间？）

### Step 3: 应用模式
- 相对距离 → `PitchConstants.scaled(value)`
- 相对速度 → `PitchConstants.scaled_speed(value)`
- 相对加速度 → `PitchConstants.scaled_accel(value)`
- 绝对距离 → `PitchConstants.absolute(value)` 或保持原样
- 无量纲/时间 → 保持不变

### Step 4: 添加注释
```gdscript
const SHOT_DISTANCE := PitchConstants.scaled(150.0)  ## 相对：AI 射门触发距离
const TACKLE_DISTANCE := PitchConstants.absolute(15.0)  ## 绝对：身体接触范围
const SPRINT_MULTIPLIER := 1.6  ## 无量纲：冲刺速度倍数
```

---

## 验证测试

### 测试用例 1: 默认尺寸（无回归）
```gdscript
# pitch_constants.gd
const WIDTH := 850.0
const HEIGHT := 360.0
```
- 运行所有测试套件
- 游戏行为应该与之前完全一致

### 测试用例 2: 双倍场地
```gdscript
const WIDTH := 1700.0
const HEIGHT := 720.0
```
**预期行为**：
- ✅ AI 射门距离变为 300px（原来 150px）
- ✅ 过中线判断变为 850px（原来 425px）
- ✅ 传球吸附范围扩大到 360px（原来 180px）
- ✅ 铲球距离仍为 15px（不变）
- ✅ 球员带球感觉与小场地相似（速度同步缩放）
- ⚠️ 球员精灵可能显得太小（需要手动缩放精灵）

### 测试用例 3: 半场地
```gdscript
const WIDTH := 425.0
const HEIGHT := 180.0
```
**预期行为**：
- ✅ 所有相对距离缩小一半
- ✅ 游戏节奏更快（场地小）
- ⚠️ 可能太拥挤（22 个球员 + 1 个球在小场地）

---

## 常见问题

### Q1: 为什么不把所有常量都改成 `scaled()`？
**A**: 过度抽象会：
1. 隐藏真实意图（15px 是身体接触，不应该缩放）
2. 破坏手感（某些值是实验调出来的，缩放后需要重新平衡）
3. 增加复杂度（阅读代码时需要记住什么会缩放）

**原则**：只缩放明确与场地尺寸相关的值。

### Q2: `absolute()` 函数只是返回原值，为什么要写？
**A**: 语义化！代码告诉读者："我知道这里可以缩放，但我*选择*不缩放，因为这是绝对距离"。

### Q3: 速度要缩放吗？
**A**: 看情况：
- **相对速度**（"多久跑完全场"）→ 缩放
- **绝对速度**（"现实中的 5m/s"）→ 不缩放

这个项目是街机风格，建议缩放速度以保持相对手感。

### Q4: 重力要缩放吗？
**A**: 
- **缩放重力** = 保持抛物线形状相似（推荐）
- **不缩放** = 大场地上球会"飘"，小场地上球会"砸"

### Q5: 碰撞体怎么办？
**A**: 
- 场景中的 `CollisionShape2D` 需要手动调整
- 或在代码中动态设置：
  ```gdscript
  func _ready():
      $CollisionShape2D.shape.radius *= PitchConstants.SCALE_FACTOR
  ```

### Q6: 改完后手感不对怎么办？
**A**: 
1. 检查是否遗漏了某个关键常量
2. 有些值可能需要非线性缩放（如 `value * sqrt(SCALE_FACTOR)`）
3. 重新平衡游戏（改尺寸本质上是重新设计）

---

## 逐文件重构进度跟踪

复制此表格到你的工作日志：

| 文件 | 常量数 | 已重构 | 状态 | 备注 |
|------|--------|--------|------|------|
| `utils/pitch_constants.gd` | - | - | ⬜ 待开始 | 添加缩放系统 |
| `ai_behavior_field.gd` | ~10 | 0 | ⬜ 待开始 | 高优先级 |
| `ai_behavior_goalie.gd` | ~7 | 0 | ⬜ 待开始 | 高优先级 |
| `player_state_passing.gd` | 3 | 0 | ⬜ 待开始 | 高优先级 |
| `player_state_moving.gd` | 5 | 0 | ⬜ 待开始 | 中优先级 |
| `player_state_hurt.gd` | 1 | 0 | ⬜ 待开始 | 中优先级 |
| `ball.gd` | 5 | 0 | ⬜ 待开始 | 中优先级 |
| `ball_state_kicked.gd` | 4 | 0 | ⬜ 待开始 | 中优先级 |
| `ball_state_shot.gd` | 7 | 0 | ⬜ 待开始 | 中优先级 |
| `ball_state_freeform.gd` | 2 | 0 | ⬜ 待开始 | 中优先级 |
| `ball_state_carried.gd` | 7 | 0 | ⬜ 待开始 | 低优先级 |
| `ball_state_saved.gd` | 2 | 0 | ⬜ 待开始 | 低优先级 |
| `ball_state_deflected.gd` | 3 | 0 | ⬜ 待开始 | 低优先级 |
| `ball_state_held_by_goalkeeper.gd` | 3 | 0 | ⬜ 待开始 | 低优先级 |

**状态图例**：
- ⬜ 待开始
- 🔄 进行中
- ✅ 已完成
- ⚠️ 需复核

---

## 总结

### 核心原则
1. **区分相对和绝对** - 不是所有数字都需要缩放
2. **语义优先** - 用 `HALFPITCH_X` 而非魔法数字
3. **渐进重构** - 逐个文件，每次提交可测试
4. **充分测试** - 每个阶段都要验证无回归

### 预期收益
- ✅ 可以自由调整球场尺寸
- ✅ 代码意图更清晰（相对 vs 绝对）
- ✅ 更容易移植到不同分辨率
- ✅ 支持未来的"场地大小选项"功能

### 风险
- ⚠️ 需要重新平衡游戏
- ⚠️ 精灵/碰撞体需要同步调整
- ⚠️ 某些手感参数可能需要重新调试

**建议从保守策略开始**，先重构明确的相对距离，逐步扩展到速度和物理系统。
