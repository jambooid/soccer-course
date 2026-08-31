# 带球功能（Dribbling）

**状态**：[INTEGRATED]  
**开始日期**：2026-08-23  
**集成日期**：2026-08-27  
**相关分支**：dev

## 1. 功能目标

### 1.1 核心目标

实现物理推球式带球系统，替代原有的 lerp 平滑跟随模式。球作为独立物理实体，球员通过周期性触球推动球前进，带来更自然的变向弧线、急停前冲和属性差异表现。

### 1.2 WE2000 对照

对应 WE2000/PES 的核心带球机制：
- **球员与球解耦**：球是独立运动的物理实体，不是"粘"在脚上
- **触球驱动**：通过周期性触球（Touch Point）推动球，而非连续控制
- **属性影响手感**：technique 影响触球区大小、精度、控制距离
- **变向有弧线**：惯性导致自然的变向弧线，不是瞬间转向
- **大步趟球**：高速时球离脚更远，低速时球更贴身

参考文档：
- `docs/we2000-core-techniques.md` §2（带球机制）
- `docs/We-dribbling.md`
- `docs/How-godot-implement-we-dribbing.md`

### 1.3 成功标准

- [x] **物理真实**：球的运动完全由速度和摩擦力决定，无 lerp 拉扯
- [x] **手感自然**：变向有弧线、急停有前冲、加速有渐进
- [x] **属性差异明显**：高低 technique 球员手感可区分
- [x] **操作可控**：正常带球不会轻易失控
- [x] **抢断有层次**：球离脚越远越容易被断（概率式）
- [x] **自动化测试通过**：所有物理公式和边界条件测试 PASS
- [x] **手动测试通过**：手感符合 WE2000 描述

## 2. 实现要点

### 2.1 核心机制

1. **指数衰减摩擦**：`v(t) = v0 * f^t`，f=0.35，停止距离 ≈ 初速 × 0.95
2. **触球区（Touch Zone）**：椭圆形区域，长度随 technique 变化（12-28px）
3. **触球冲量**：不直接替换球速，而是 lerp 向目标速度（效率由 technique 决定）
4. **失控判定**：球距离 > 最大可控距离（50-80px）且远离球员时释放
5. **概率式抢断**：基于距离、角度、速度、属性四维因子计算抢断概率

### 2.2 关键参数

```gdscript
# DribblePhysics 关键常量
GROUND_FRICTION_PER_SEC = 0.35      # 摩擦系数
TOUCH_ZONE_LEN_MIN = 12.0           # 触球区最小长度
TOUCH_ZONE_LEN_MAX = 28.0           # 触球区最大长度
MIN_TOUCH_INTERVAL = 0.08           # 最小触球间隔（秒）
PUSH_MULT_LOW_SPEED = 1.6           # 低速推球倍率
PUSH_MULT_HIGH_SPEED = 1.35         # 高速推球倍率
TOUCH_EFFICIENCY_MIN = 0.5          # 最低触球效率
TOUCH_EFFICIENCY_MAX = 0.9          # 最高触球效率
MAX_CONTROL_DISTANCE_MIN = 50.0     # 最小可控距离
MAX_CONTROL_DISTANCE_MAX = 80.0     # 最大可控距离
```

关键公式：
- 停止距离：`S = v0 / -ln(f)` ≈ v0 × 0.95
- 预测位置：`x(t) = x0 + v0 * (f^t - 1) / ln(f)`
- 触球区长度：`lerp(12, 28, normalize_technique(tech))`
- 推球方向：`player_dir.rotated(randf_range(-accuracy, accuracy))`

### 2.3 属性影响

| 属性 | 影响参数 | 手感表现 |
|------|---------|---------|
| **technique** (30-98) | 触球区长度、触球效率、方向精度、最大可控距离 | 高技术：球贴身、变向利落、不易失控<br>低技术：球离脚远、变向弧线大、容易趟大 |
| **speed** | 推球基准速度 | 最高带球速度、大步趟球距离 |
| **defense**（对方） | 抢断概率计算 | 高防守更容易断球 |

### 2.4 带球模式

- **JOG（慢跑）**：触球区标准、推球力度适中
- **SPRINT（冲刺）**：触球区 × 1.3、可控距离 × 1.5、触球间隔 × 1.875、精度下降

## 3. 文件清单

### 3.1 实现文件

**核心工具类**：
- `utils/dribble_physics.gd` - 所有物理计算的静态工具类（摩擦、触球区、预测）
- `utils/intercept_resolver.gd` - 概率式抢断判定

**球状态**：
- `scenes/ball/ball.gd` - 增加 `State.DRIBBLING` 枚举
- `scenes/ball/ball_states/ball_state_dribbling.gd` - 新的带球状态（替代 CARRIED）
- `scenes/ball/ball_state_factory.gd` - 注册 DRIBBLING 状态

**集成点**：
- `scenes/ball/ball_states/ball_state_freeform.gd` - 拾球进入 DRIBBLING
- `scenes/characters/ai/ai_behavior_field.gd` - AI 带球适配
- `scenes/characters/character_states/player_state_moving.gd` - 球员移动状态适配

**调试工具**：
- `scenes/debug/dribble_debug_draw.gd` - 可视化触球区、速度向量

**遗留代码（保留）**：
- `scenes/ball/ball_states/ball_state_carried.gd` - 标记为 LEGACY，作为回退方案

### 3.2 测试文件

- `features/dribbling/tests/test_physics.gd` - 自动化物理测试（32个测试用例）
- `features/dribbling/tests/test_diagonal_turn_animation.gd` - 斜向转身序列帧和场景绑定校验
- `features/dribbling/tests/test_scene.tscn` - 手动测试场景
- `tools/test_dribbling.gd` - 原有测试（符号链接到 features/dribbling/tests/test_physics.gd）
- `tools/test_dribbling_scene.tscn` - 原有测试场景（符号链接）

### 3.3 相关文档

- `docs/dribbling-physics-design.md` - 完整设计文档（含数学推导）
- `docs/We-dribbling.md` - WE2000 带球机制研究
- `docs/How-godot-implement-we-dribbing.md` - Godot 实现指南
- `docs/we2000-core-techniques.md` - WE2000 核心技术参考

## 4. 测试策略

### 4.1 自动化测试

测试覆盖（32个测试用例，全部 PASS）：

1. **摩擦力测试**：t=0 不变、1秒衰减到 f 倍、2秒衰减到 f² 倍、方向保持
2. **触球区测试**：正前方在区内、边界精确、后方不在、侧面边界
3. **停止距离测试**：正值、零速为零、线性缩放、解析解匹配
4. **位置预测测试**：t=0 不变、向前移动、考虑摩擦、解析解匹配、长时间趋向停止距离
5. **触球区长度测试**：tech=0 最小、tech=100 最大、tech=50 中间、负值钳制、超范围钳制
6. **最大可控距离测试**：同上
7. **触球冲量测试**：静止不触球、移动改变球速、方向匹配、慢速不触球
8. **带球模式测试**：SPRINT 触球区更长、SPRINT 可控距离更大、SPRINT 推球力度更大
9. **速度惩罚测试**：高速时方向偏差更大
10. **停球质量测试**：高技术吸收更多、低技术弹得远

运行方法：
```bash
godot --path . -s features/dribbling/tests/test_physics.gd
```

预期输出：
```
=== Dribble Physics Tests ===
...
Results: 32 passed, 0 failed
All tests passed!
```

### 4.2 手动测试要点

在 `test_scene.tscn` 中测试（详见 `validation/checklist.md`）：

1. **直线带球**：球稳定在身前、波浪形速度节奏
2. **变向手感**：自然弧线、高 tech 收得快、低 tech 弧线宽
3. **急停前冲**：物理真实、高 tech 前冲短
4. **加速启动**：由慢到快、步幅渐大
5. **属性差异**：tech=30 vs tech=98 手感明显不同
6. **抢断概率**：球离脚远时更易被断、正面拦截更易成功

### 4.3 集成测试

1. **与传球系统兼容**：带球→传球过渡流畅
2. **与射门系统兼容**：带球→射门过渡流畅
3. **AI 带球正常**：CPU vs CPU 比赛正常
4. **性能验证**：22 球员同时带球无卡顿

## 5. 已知问题

- [P2] **摩擦模型不一致**：DRIBBLING 用指数摩擦，FREEFORM 用线性摩擦，释放球时有突变感
  - 影响：球从带球释放时摩擦力变化略显突兀
  - 解决方案：统一为指数摩擦模型（需修改 ball_state_freeform.gd）
  - 优先级：中（不影响基本游戏性）

- [P3] **SPRINT 模式未充分测试**：手动测试主要集中在 JOG 模式
  - 影响：冲刺带球的平衡性未充分验证
  - 解决方案：补充 SPRINT 模式的专项测试
  - 优先级：低（基本功能正常）

## 6. 后续优化方向

### 6.1 短期优化（P1-P2）

1. **统一摩擦模型**：FREEFORM 也改为指数摩擦，消除状态切换突变
2. **触球音效**：在触球帧播放音效，增强反馈感
3. **SPRINT 平衡调整**：根据实际游戏数据调整 SPRINT 参数
4. **AI 带球决策增强**：AI 根据球的实际位置做更智能的决策

### 6.2 中期扩展（P3）

1. **背身护球机制**：低速 + 防守球员接近时触发护球姿态
2. **技巧动作**：牛尾巴、马赛回旋等特殊带球动作
3. **体力影响**：stamina 低时触球效率下降
4. **地形影响**：不同场地摩擦力不同

### 6.3 长期愿景

1. **脚底触球动画**：与触球帧同步的动画事件
2. **球的视觉滚动**：球的旋转与速度匹配
3. **带球训练模式**：专门的带球技巧练习场景

## 7. 验证记录

### 7.1 自动化测试结果

```
日期：2026-08-27
执行人：系统自动化
结果：32 passed, 0 failed
详情：所有物理公式测试通过，边界条件正确
```

### 7.2 手动测试结果

```
日期：2026-08-27
测试人：开发者
结果：通过
详情：
- 直线带球稳定：✓
- 变向弧线自然：✓
- 急停前冲合理：✓
- 属性差异明显：✓（tech 30 vs 98 手感差异显著）
- 手感符合 WE2000：✓（与文档描述一致）
```

### 7.3 集成测试结果

```
日期：2026-08-27
结果：通过
详情：
- 与传球兼容：✓
- 与射门兼容：✓
- AI 带球正常：✓（CPU vs CPU 测试 5 场，无异常）
- 性能正常：✓（60 FPS 稳定）
```

## 8. 经验总结

### 8.1 成功要素

1. **设计先行**：详细的设计文档（dribbling-physics-design.md）明确了所有参数和公式
2. **自动化测试**：32 个测试用例覆盖所有物理计算，快速发现问题
3. **工具类设计**：DribblePhysics 纯函数工具类，易测试、易调试
4. **文档驱动**：参考 WE2000 文档，目标明确

### 8.2 遇到的挑战

1. **参数调校**：物理参数（摩擦、触球倍率）需要反复调整才能达到好的手感
   - 解决：通过可视化调试工具（DribbleDebugDraw）实时观察
2. **AI 适配**：AI 需要适应新的物理模型，初期 CPU 球员经常丢球
   - 解决：AI 增加"安全阈值"，球离脚稍远就传球
3. **摩擦不一致**：指数 vs 线性摩擦的差异
   - 解决：暂时保留，列为已知问题，后续统一

### 8.3 可复用模式

- ✅ **工具类 + 状态类**：DribblePhysics（静态计算）+ BallStateDribbling（状态管理）分离清晰
- ✅ **测试驱动**：先写测试用例，再实现功能，覆盖率高
- ✅ **回退方案**：保留旧代码（CARRIED），快速回退
- ✅ **调试可视化**：DribbleDebugDraw 大幅提升调试效率

## 9. 参考资料

- [功能模块化框架](../../docs/superpowers/feature-module-framework.md)
- [WE2000 核心技术](../../docs/we2000-core-techniques.md)
- [WE2000 实现研究](../../docs/we2000-implementation-research.md)
- [带球物理设计](../../docs/dribbling-physics-design.md)
