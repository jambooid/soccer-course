# Soccer Course - 功能模块总览

本目录包含所有按模块化开发的 WE2000 风格功能。

## 功能模块列表

### [INTEGRATED] 带球（Dribbling）
**目录**：`features/dribbling/`  
**集成日期**：2026-08-27  
**核心技术**：物理推球、触球区、概率式抢断  
**状态**：✅ 已集成到主游戏  

**简介**：
实现物理推球式带球系统，球作为独立物理实体，球员通过周期性触球推动球前进。变向有自然弧线，急停有前冲，属性影响明显。

**关键指标**：
- 自动化测试：32/32 通过
- 手感评分：8.5/10
- 性能：60 FPS 稳定

---

## 待开发功能（参考 WE2000 优先级）

### [PLANNING] 传球辅助（Pass Assist）
**优先级**：P0  
**WE2000 对照**：磁性传球、方向吸附  
**目标**：传球自动吸附到最佳队友，球路轻微弯曲以方便接球  

### [PLANNING] 输入缓冲（Input Buffer）
**优先级**：P1  
**WE2000 对照**：格斗游戏式输入缓冲  
**目标**：动画中按下的指令排队执行，不会因"按早了一帧"失败  

### [PLANNING] 多因子射门（Dynamic Shooting）
**优先级**：P1  
**WE2000 对照**：身体朝向、防守压力、球速影响射门动作  
**目标**：同一按键根据情况选择不同射门变体  

### [PLANNING] 身体对抗（Physical Contest）
**优先级**：P2  
**WE2000 对照**：护球、争顶、推挤  
**目标**：规则式身体对抗判定，不依赖物理引擎  

### [PLANNING] AI 跑位系统（Off-Ball Movement）
**优先级**：P2  
**WE2000 对照**：反越位跑位、拉边、回撤  
**目标**：队友理解持球者意图，主动创造空间  

### [PLANNING] 误差系统（Error System）
**优先级**：P3  
**WE2000 对照**：传球/射门受属性和压力影响的偏差  
**目标**：制造比赛故事感，100% 准确反而不真实  

---

## 开发流程

每个功能模块遵循统一的开发流程：

```
1. 创建模块目录
   features/[name]/
   ├── FEATURE.md           # 功能文档
   ├── implementation/      # 实现文件清单
   ├── tests/               # 测试文件
   ├── docs/                # 相关文档
   └── validation/          # 验证材料

2. 开发 → 测试 → 验证
   - 自动化测试全部通过
   - 手动测试符合 WE2000 手感
   - 集成测试确认兼容性

3. 集成到主游戏
   - 标记为 [INTEGRATED]
   - 保留模块作为历史记录
```

详细流程见：`docs/superpowers/feature-module-framework.md`

---

## 快速开始

### 运行带球功能测试

```bash
# 自动化测试
godot --path . -s features/dribbling/tests/test_physics.gd

# 手动测试场景
godot --path . features/dribbling/tests/test_scene.tscn

# 或在编辑器中打开
godot --path . -e features/dribbling/tests/test_scene.tscn
```

### 创建新功能模块

```bash
# 使用模板创建新模块
cp -r features/_template features/[new_feature_name]
cd features/[new_feature_name]
# 编辑 FEATURE.md，填写功能目标和实现计划
```

---

## 统计数据

- **已集成功能**：1
- **开发中功能**：0
- **计划中功能**：6
- **总代码覆盖**：约 800 行（dribbling）
- **测试用例数**：32（dribbling）

---

## 参考文档

- [功能模块化框架](../docs/superpowers/feature-module-framework.md)
- [WE2000 核心技术](../docs/we2000-core-techniques.md)
- [WE2000 实现研究](../docs/we2000-implementation-research.md)
- [项目架构说明](../docs/CLAUDE.md)

---

**最后更新**：2026-08-30
