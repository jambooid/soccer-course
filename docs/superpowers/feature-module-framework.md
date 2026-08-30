# 功能模块化开发框架

> 版本：v1.0  
> 日期：2026-08-30  
> 目的：建立可重复的WE2000风格功能开发、测试和集成流程

## 1. 框架概述

### 1.1 设计原则

- **模块独立**：每个功能单元可以独立开发、测试、验证
- **渐进集成**：验证通过的功能逐步合并到主游戏
- **文档驱动**：每个模块都有清晰的目标、实现要点和验证标准
- **可追溯性**：保留所有开发文档和测试结果

### 1.2 目录结构

```
features/
├── dribbling/              # 带球功能模块（示例）
│   ├── FEATURE.md          # 功能文档（目标、实现、验证）
│   ├── implementation/     # 实现文件的引用清单
│   │   └── files.txt       # 列出所有实现文件的路径
│   ├── tests/              # 测试文件
│   │   ├── test_physics.gd         # 自动化单元测试
│   │   ├── test_scene.tscn         # 手动测试场景
│   │   └── test_integration.gd     # 集成测试
│   ├── docs/               # 相关文档
│   │   ├── design.md       # 设计文档（可选，复杂功能用）
│   │   ├── we2000-reference.md  # WE2000参考（可选）
│   │   └── changelog.md    # 变更日志
│   └── validation/         # 验证材料
│       ├── checklist.md    # 手动测试检查清单
│       ├── test-results.txt # 测试结果记录
│       └── demo-video.txt  # 演示视频链接（可选）
│
├── passing/                # 传球功能模块
├── shooting/               # 射门功能模块
└── README.md               # 功能模块总览
```

## 2. 功能模块生命周期

### 2.1 开发阶段

```
1. 创建功能模块目录
   ├─ 编写 FEATURE.md（定义目标、WE2000对照、验证标准）
   │
2. 实现核心功能
   ├─ 在主代码库中实现（scenes/, utils/ 等）
   ├─ 在 implementation/files.txt 记录所有相关文件
   │
3. 编写测试
   ├─ 自动化测试（tests/test_physics.gd）
   ├─ 手动测试场景（tests/test_scene.tscn）
   ├─ 集成测试（tests/test_integration.gd，可选）
   │
4. 文档补充
   └─ 根据需要添加设计文档、WE2000参考等
```

### 2.2 验证阶段

```
1. 自动化测试
   ├─ 运行 test_physics.gd
   ├─ 所有测试用例必须 PASS
   └─ 记录结果到 validation/test-results.txt
   
2. 手动测试
   ├─ 在 test_scene.tscn 中测试
   ├─ 按 validation/checklist.md 逐项验证
   ├─ 对照 WE2000 手感确认
   └─ 记录测试结果和问题
   
3. 集成测试
   ├─ 在完整游戏环境中测试
   ├─ 确认与其他功能的兼容性
   └─ 性能验证（帧率、内存等）
```

### 2.3 集成阶段

```
1. 代码审查
   ├─ 检查代码质量
   └─ 确认符合项目规范
   
2. 合并到主游戏
   ├─ 功能在主游戏中默认启用
   ├─ 更新 features/README.md
   └─ 更新主项目文档
   
3. 归档
   ├─ 保留模块目录（包含所有文档）
   ├─ 标记为 [INTEGRATED] 状态
   └─ 功能模块作为历史记录和参考
```

## 3. FEATURE.md 模板

每个功能模块的 `FEATURE.md` 包含以下部分：

```markdown
# [功能名称]

**状态**：[DEVELOPMENT | TESTING | INTEGRATED]  
**负责人**：[可选]  
**开始日期**：YYYY-MM-DD  
**集成日期**：YYYY-MM-DD（完成后填写）

## 1. 功能目标

### 1.1 核心目标
简明描述这个功能要实现什么（2-3句话）

### 1.2 WE2000 对照
这个功能对应 WE2000 的哪个机制？目标手感是什么？

### 1.3 成功标准
- [ ] 标准1：具体可测量
- [ ] 标准2：具体可测量
- [ ] 标准3：手感符合WE2000描述

## 2. 实现要点

### 2.1 核心机制
关键技术点（3-5条要点）

### 2.2 关键参数
列出影响手感的关键常量和公式

### 2.3 属性影响
哪些球员属性影响这个功能？如何影响？

## 3. 文件清单

### 3.1 实现文件
- `path/to/file1.gd` - 文件说明
- `path/to/file2.gd` - 文件说明

### 3.2 测试文件
- `features/[name]/tests/test_physics.gd` - 自动化测试
- `features/[name]/tests/test_scene.tscn` - 手动测试场景

### 3.3 相关文档
- `docs/xxx.md` - 设计文档

## 4. 测试策略

### 4.1 自动化测试
测试哪些方面？预期结果？

### 4.2 手动测试要点
需要人工确认的手感、视觉效果等

### 4.3 集成测试
与其他功能的交互测试

## 5. 已知问题

- 问题1：描述 + 优先级
- 问题2：描述 + 优先级

## 6. 后续优化方向

- 方向1：简述
- 方向2：简述
```

## 4. 测试清单模板

`validation/checklist.md` 模板：

```markdown
# [功能名称] 手动测试检查清单

测试日期：________  
测试人：________

## 基础功能测试

- [ ] 功能可正常启动
- [ ] 无崩溃或报错
- [ ] 基本操作响应正常

## WE2000 手感对照

- [ ] [具体手感点1]：符合/不符合（备注）
- [ ] [具体手感点2]：符合/不符合（备注）
- [ ] [具体手感点3]：符合/不符合（备注）

## 属性差异测试

- [ ] 高属性球员表现：________
- [ ] 低属性球员表现：________
- [ ] 差异可感知：是/否

## 边界情况测试

- [ ] 极端情况1：________
- [ ] 极端情况2：________

## 集成测试

- [ ] 与功能A兼容：是/否
- [ ] 与功能B兼容：是/否

## 性能测试

- [ ] 帧率稳定：是/否（FPS：____）
- [ ] 无明显卡顿：是/否

## 总体评价

- 手感评分（1-10）：____
- 是否达到验收标准：是/否
- 主要问题：________
- 优化建议：________
```

## 5. 命令行工具

### 5.1 运行自动化测试

```bash
# 运行特定功能的自动化测试
godot --path . -s features/dribbling/tests/test_physics.gd

# 或使用统一测试脚本（待创建）
godot --path . -s features/run_tests.gd dribbling
```

### 5.2 打开手动测试场景

```bash
# 在编辑器中打开测试场景
godot --path . -e features/dribbling/tests/test_scene.tscn

# 或直接运行测试场景
godot --path . features/dribbling/tests/test_scene.tscn
```

## 6. 最佳实践

### 6.1 功能设计

1. **单一职责**：每个功能模块只解决一个核心问题
2. **参数化**：关键常量集中管理，方便调试
3. **状态清晰**：使用状态机模式，状态转换明确
4. **文档优先**：先写 FEATURE.md，明确目标再实现

### 6.2 测试设计

1. **自动化优先**：能自动化的测试都自动化
2. **物理验证**：验证数学公式、边界条件
3. **手感验证**：人工确认与 WE2000 的对照
4. **回归测试**：保留测试用例，防止后续改动破坏

### 6.3 集成原则

1. **向后兼容**：新功能不破坏现有功能
2. **渐进启用**：可通过开关控制新功能
3. **性能监控**：集成后验证整体性能
4. **文档同步**：更新主项目文档

## 7. 工作流程示例

### 示例：开发"传球辅助"功能

```bash
# 1. 创建功能模块
mkdir -p features/passing_assist/{implementation,tests,docs,validation}

# 2. 编写功能文档
vim features/passing_assist/FEATURE.md

# 3. 实现功能
# （在 scenes/ball/, scenes/characters/ 等目录实现）

# 4. 记录实现文件
cat > features/passing_assist/implementation/files.txt << EOF
scenes/ball/ball.gd
scenes/characters/player_state_passing.gd
utils/pass_assist.gd
EOF

# 5. 编写自动化测试
vim features/passing_assist/tests/test_physics.gd

# 6. 创建手动测试场景
# （在 Godot 编辑器中创建 test_scene.tscn）

# 7. 运行测试
godot --path . -s features/passing_assist/tests/test_physics.gd

# 8. 手动测试并填写清单
vim features/passing_assist/validation/checklist.md

# 9. 验证通过，更新状态
# 在 FEATURE.md 中标记为 [INTEGRATED]

# 10. 更新功能总览
vim features/README.md
```

## 8. 附录

### 8.1 功能模块状态说明

- **[DEVELOPMENT]**：开发中，功能尚未完整实现
- **[TESTING]**：实现完成，正在测试验证阶段
- **[INTEGRATED]**：验证通过，已集成到主游戏

### 8.2 功能优先级

功能开发建议顺序（参考 WE2000 核心技术文档）：

| 优先级 | 功能模块 | 理由 |
|--------|---------|------|
| P0 | 带球（Dribbling） | 基础操作，影响手感最大 |
| P0 | 传球辅助（Pass Assist） | 磁性传球，WE2000核心手感 |
| P1 | 输入缓冲（Input Buffer） | 响应性，格斗游戏式操作 |
| P1 | 射门系统增强 | 多因子动作选择 |
| P2 | 身体对抗 | 护球、争顶 |
| P2 | AI 跑位系统 | 无球 AI |
| P3 | 误差系统 | 故事感 |

### 8.3 参考资料

- [WE2000 核心技术](../we2000-core-techniques.md)
- [WE2000 实现研究](../we2000-implementation-research.md)
- [项目架构说明](../CLAUDE.md)
