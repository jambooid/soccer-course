# 像素无关性系统审视 - 总结报告

**日期**: 2026-08-30  
**项目**: Soccer Course (Godot 4.4)  
**目标**: 实现球场尺寸可配置，不依赖具体像素值

---

## 执行摘要

### 当前状况：部分像素无关 ⚠️

项目已经有 `PitchConstants` 单例作为基础设施，但**大量距离/速度常量仍硬编码在各个文件中**，导致改变球场尺寸会破坏游戏平衡。

**关键问题**：
- ✅ 球场尺寸集中在 `PitchConstants`（WIDTH=850, HEIGHT=360）
- ❌ 至少 **50+ 个硬编码常量**散落在 AI、物理、状态机代码中
- ❌ 没有明确区分"相对距离"（应缩放）和"绝对距离"（不应缩放）
- ❌ 如果改变 WIDTH/HEIGHT，AI 判断、传球范围、战术位置都会失效

### 影响评估

| 场景 | 当前行为 | 问题严重性 |
|------|----------|-----------|
| 球场尺寸翻倍 (850→1700) | AI 射门距离仍 150px（相对变近） | 🔴 高 - 游戏性破坏 |
| 球场尺寸翻倍 | "过中线才冲刺"判断失效（425px≠中线） | 🔴 高 - 逻辑错误 |
| 改变分辨率但保持比例 | 物理尺寸不变，UI 正常缩放 | 🟡 中 - 可能需要同步调整 |
| 添加"场地大小"游戏选项 | 当前无法实现 | 🔴 高 - 功能缺失 |

---

## 解决方案架构

### 核心设计：二元分类系统

将所有距离/速度分为两类，采用不同的处理策略：

#### 🟦 相对尺度（Relative Scale）
**定义**：与球场尺寸成比例的值，场地变大则值应变大  
**识别方法**：问"如果场地翻倍，这个值应该是多少？" → 答案是"翻倍"

**包括**：
- AI 判断距离（射门、传球、跑位）
- 战术位置（后腰保持距离、支援激活范围）
- 场地区域（中线、半场）
- 球速、摩擦力（保持"滚动距离"比例一致）

**实现**：`PitchConstants.scaled(value)`

#### 🟩 绝对尺度（Absolute Scale）
**定义**：与球员身体/物理尺寸相关的值，不随场地变化  
**识别方法**：问"这个值跟球员身体有关吗？" → 答案是"是"

**包括**：
- 身体接触距离（铲球 15px、接球 15px）
- 带球偏移（球在脚边 8-20px）
- 2.5D 高度阈值（头球 5-30px，除非精灵也缩放）

**实现**：`PitchConstants.absolute(value)` 或直接保持不变

#### ⚪ 无量纲/时间（Dimensionless）
**定义**：本身就是比例、角度、时间，无需缩放

**包括**：
- 比例系数（冲刺倍数 1.6、反弹系数 0.8）
- 角度（急转 90°、转向速率 rad/s）
- 时间/帧数（锁定 200ms、检测间隔 3 帧）

**实现**：保持不变

### 技术实现

#### 1. 扩展 `PitchConstants`

添加缩放系统：

```gdscript
const REFERENCE_WIDTH := 850.0  # 基准尺寸
const WIDTH := 850.0            # 实际尺寸（可配置）
const SCALE_FACTOR := WIDTH / REFERENCE_WIDTH

static func scaled(value: float) -> float:
    return value * SCALE_FACTOR

static func scaled_speed(value: float) -> float:
    return value * SCALE_FACTOR

static func scaled_accel(value: float) -> float:
    return value * SCALE_FACTOR

static func absolute(value: float) -> float:
    return value  # 语义化标记
```

#### 2. 重构硬编码常量

**示例对比**：

```gdscript
# ❌ 重构前（硬编码）
const SHOT_DISTANCE := 150
const TACKLE_DISTANCE := 15
const SPRINT_DIST_TO_GOAL_MAX := 425.0

# ✅ 重构后（语义明确）
const SHOT_DISTANCE := PitchConstants.scaled(150.0)      # 相对：AI 判断
const TACKLE_DISTANCE := PitchConstants.absolute(15.0)   # 绝对：身体接触
const SPRINT_DIST_TO_GOAL_MAX := PitchConstants.HALFPITCH_X  # 语义：中线
```

---

## 工作量评估

### 需要重构的文件（按优先级）

| 优先级 | 文件 | 常量数 | 预计工时 | 风险 |
|--------|------|--------|----------|------|
| 🔴 高 | `ai_behavior_field.gd` | ~10 | 1h | 影响 AI 核心行为 |
| 🔴 高 | `ai_behavior_goalie.gd` | ~7 | 0.5h | 门将行为 |
| 🔴 高 | `player_state_passing.gd` | 3 | 0.5h | 传球手感 |
| 🟡 中 | `ball_state_kicked.gd` | 4 | 0.5h | 球物理 |
| 🟡 中 | `ball_state_shot.gd` | 7 | 0.5h | 射门物理 |
| 🟡 中 | `ball.gd` | 5 | 0.5h | 球基础参数 |
| 🟡 中 | `player_state_moving.gd` | 5 | 0.5h | 移动手感 |
| 🟢 低 | `ball_state_carried.gd` | 7 | 0.5h | 带球视觉 |
| 🟢 低 | 其他 ball_states | ~10 | 1h | 边缘情况 |

**总计**：~50 个常量，预计 **5-6 小时**纯重构时间

**测试时间**：2-3 小时（多尺寸验证）

**总工时**：**8-10 小时**（包含测试和文档）

---

## 实施路线图

### 🎯 阶段 0：准备（30 分钟）
- [x] 分析现状，编写此文档
- [ ] 团队评审，确认方案

### 🎯 阶段 1：基础设施（1 小时）
**目标**：建立缩放系统，不破坏现有代码

1. 备份 `utils/pitch_constants.gd`
2. 实施新的 `PitchConstants`（参考 `docs/pitch_constants_refactored_example.gd`）
3. 运行所有测试，确保无回归
4. 提交：`feat: add scaling system to PitchConstants`

**验证**：
```bash
# 运行测试套件
$GODOT --path . --headless tools/test_runner.gd
```

### 🎯 阶段 2：高优先级重构（2-3 小时）
**目标**：修复影响游戏性的核心常量

**子任务**：
1. 重构 `ai_behavior_field.gd`
   - 射门距离、铲球距离、跑位逻辑
   - 提交：`refactor(ai): apply pitch scaling to field AI distances`
   
2. 重构 `ai_behavior_goalie.gd`
   - 门将出击、扑救、分配球
   - 提交：`refactor(ai): apply pitch scaling to goalie AI`
   
3. 重构 `player_state_passing.gd`
   - 传球吸附范围
   - 提交：`refactor(player): apply pitch scaling to pass assist ranges`

**验证**：每个文件重构后立即测试

### 🎯 阶段 3：物理系统重构（2 小时）
**目标**：修复球和移动物理

1. 重构球状态文件（`ball_states/*.gd`）
2. 重构球主文件（`ball.gd`）
3. 重构玩家移动状态（`player_state_moving.gd` 等）
4. 提交：`refactor(physics): apply pitch scaling to ball and movement physics`

### 🎯 阶段 4：多尺寸验证（2-3 小时）
**目标**：在不同尺寸下测试游戏

**测试矩阵**：

| 尺寸 | WIDTH×HEIGHT | 预期 | 验证项 |
|------|--------------|------|--------|
| 默认 | 850×360 | 无回归 | 所有测试通过，手感不变 |
| 双倍 | 1700×720 | 游戏性一致 | AI 行为合理，传球/射门正常 |
| 半场 | 425×180 | 节奏更快 | 不卡顿，碰撞正常 |
| 宽屏 | 1200×360 | 拉伸变形 | 应警告宽高比不一致 |

**修复发现的问题**：
- 碰撞体尺寸
- 精灵缩放
- 摄像机视野
- 性能问题

### 🎯 阶段 5：文档和清理（1 小时）
1. 更新 `CLAUDE.md` 说明缩放系统
2. 创建"如何调整球场尺寸"指南
3. 清理临时文件
4. 最终提交：`docs: add pitch scaling documentation`

---

## 风险和缓解措施

### 风险 1：手感改变 🔴
**问题**：重构后游戏手感可能不同  
**缓解**：
- 先在默认尺寸下验证无回归
- 逐文件提交，问题可回溯
- 保留原始值作为注释

### 风险 2：遗漏常量 🟡
**问题**：可能有隐藏的硬编码值  
**缓解**：
- 用 grep 全局搜索数字常量
- 多尺寸测试会暴露遗漏
- 代码审查

### 风险 3：性能下降 🟢
**问题**：函数调用可能增加开销  
**缓解**：
- `scaled()` 是编译时计算（const 上下文）
- 性能分析工具验证
- 影响可忽略（每帧计算次数少）

### 风险 4：场景文件不同步 🟡
**问题**：`.tscn` 中的碰撞体尺寸是硬编码的  
**缓解**：
- 方案 A：手动调整场景
- 方案 B：代码动态设置碰撞体尺寸
- 文档中明确说明

---

## 成功标准

### ✅ 功能正确性
- [ ] 所有现有测试通过（默认尺寸）
- [ ] 双倍尺寸下游戏可玩，AI 行为合理
- [ ] 半场尺寸下游戏可玩，无碰撞穿透

### ✅ 代码质量
- [ ] 所有相对距离使用 `scaled()`
- [ ] 所有绝对距离标记 `absolute()` 或添加注释
- [ ] 无魔法数字，语义清晰

### ✅ 可维护性
- [ ] `PitchConstants` 有完整文档
- [ ] 重构清单和检查指南已归档
- [ ] 新成员能理解如何添加缩放常量

### ✅ 用户价值
- [ ] 可以修改 `WIDTH/HEIGHT` 立即体验不同尺寸
- [ ] 为未来"场地大小选项"功能奠定基础

---

## 推荐行动

### 立即行动（本周）
1. **团队评审此方案**（30 分钟会议）
2. **实施阶段 1**：扩展 `PitchConstants`（1 小时）
3. **验证无回归**（30 分钟）

### 短期行动（下周）
4. **实施阶段 2-3**：渐进式重构（2-3 天，每天 1-2 小时）
5. **持续测试**：每个文件重构后立即验证

### 中期行动（下下周）
6. **多尺寸测试**：完整的验证周期（1 天）
7. **文档更新**：归档最佳实践

### 可选增强
- **配置文件**：从 JSON 读取球场尺寸
- **编辑器插件**：可视化调整尺寸
- **游戏选项**：运行时切换场地大小（需要重新加载）

---

## 参考文档

本次审视创建了以下文档（位于 `docs/`）：

1. **`pixel-independence-analysis.md`** - 深度分析，问题盘点
2. **`pitch-constants-refactor-proposal.md`** - 技术方案，重构清单
3. **`pixel-independence-checklist.md`** - 快速参考，判断标准
4. **`pitch_constants_refactored_example.gd`** - 可运行示例代码
5. **`pixel-independence-summary.md`** - 本文档，执行摘要

---

## 结论

项目当前**部分像素无关**，已有良好的基础设施（`PitchConstants`），但需要系统性重构才能真正实现尺寸可配置。

**工作量可控**（8-10 小时），**风险可管理**（渐进式重构），**收益明确**（支持未来功能，代码更清晰）。

**建议采用保守策略**：
- ✅ 优先重构明确的相对距离（AI、战术）
- ⚠️ 谨慎处理速度和物理系统（影响手感）
- ✅ 充分测试每个阶段，避免大爆炸式重构

---

**下一步**: 团队评审此方案 → 批准后开始阶段 1 实施

---

**审视完成时间**: 2026-08-30  
**预计实施完成**: 2026-09-06（1 周后）
