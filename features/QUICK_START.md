# 功能模块开发快速指南

> 本指南帮助你快速上手功能模块化开发框架

## 1. 创建新功能模块（5分钟）

### 步骤1：复制模板
```bash
# 假设你要开发"传球辅助"功能
cd features/
cp -r _template passing_assist
cd passing_assist
```

### 步骤2：填写 FEATURE.md
```bash
vim FEATURE.md
```

必填内容：
- **功能名称**：传球辅助
- **核心目标**：2-3句话描述
- **WE2000 对照**：对应哪个机制
- **成功标准**：3-5条可测量标准

### 步骤3：开始开发
在主代码库中实现功能（`scenes/`, `utils/` 等），然后记录实现文件：

```bash
# 将实现的文件路径写入 implementation/files.txt
cat > implementation/files.txt << EOF
utils/pass_assist.gd
scenes/ball/ball.gd
scenes/characters/player_state_passing.gd
EOF
```

## 2. 编写测试（10分钟）

### 自动化测试
```bash
vim tests/test_physics.gd
```

测试模板：
```gdscript
extends Node

var _passed := 0
var _failed := 0

func _ready() -> void:
    print("=== [功能名称] Tests ===")
    
    test_case_1()
    test_case_2()
    
    print("Results: %d passed, %d failed" % [_passed, _failed])
    get_tree().quit()

func _assert(condition: bool, test_name: String) -> void:
    if condition:
        _passed += 1
        print("  [PASS] %s" % test_name)
    else:
        _failed += 1
        print("  [FAIL] %s" % test_name)

func test_case_1() -> void:
    # 你的测试逻辑
    _assert(true, "Test case 1")
```

### 手动测试场景
在 Godot 编辑器中创建 `tests/test_scene.tscn`，包含：
- 测试场地
- 测试用的球员和球
- 调试显示（可选）

## 3. 运行测试（2分钟）

### 自动化测试
```bash
godot --path . -s features/passing_assist/tests/test_physics.gd
```

期望看到：
```
=== [功能名称] Tests ===
  [PASS] Test case 1
  [PASS] Test case 2
Results: X passed, 0 failed
```

### 手动测试
```bash
# 在编辑器中打开
godot --path . -e features/passing_assist/tests/test_scene.tscn

# 或直接运行
godot --path . features/passing_assist/tests/test_scene.tscn
```

按照 `validation/checklist.md` 逐项测试并记录结果。

## 4. 验证和集成（5分钟）

### 确认验收标准
检查 FEATURE.md 中的成功标准：
- [ ] 自动化测试全部通过
- [ ] 手动测试符合 WE2000 手感
- [ ] 集成测试无冲突
- [ ] 性能正常

### 更新状态
```bash
# 在 FEATURE.md 中更新状态
状态：[DEVELOPMENT] → [TESTING] → [INTEGRATED]
```

### 提交
```bash
git add features/passing_assist/
git commit -m "feat(passing_assist): implement magnetic passing system

- Add pass target selection with angle tolerance
- Implement ball trajectory adjustment
- Add comprehensive test suite (X tests)
- All tests passing, manual validation complete
"
```

## 5. 常见场景

### 场景1：快速验证一个想法
```bash
# 1. 创建最小化模块
mkdir -p features/experiment_xxx/{tests,validation}

# 2. 直接在主代码中实现

# 3. 写一个简单测试验证
vim features/experiment_xxx/tests/test_quick.gd

# 4. 运行测试
godot --path . -s features/experiment_xxx/tests/test_quick.gd

# 5. 如果成功，补全文档；如果失败，直接删除模块
```

### 场景2：迭代现有功能
```bash
# 1. 查看现有功能
ls features/dribbling/

# 2. 查看实现文件
cat features/dribbling/implementation/files.txt

# 3. 修改实现代码

# 4. 重新运行测试
godot --path . -s features/dribbling/tests/test_physics.gd

# 5. 更新 changelog
vim features/dribbling/docs/changelog.md
```

### 场景3：对比不同实现方案
```bash
# 创建两个实验模块
cp -r features/_template features/experiment_approach_a
cp -r features/_template features/experiment_approach_b

# 分别实现和测试

# 对比结果，选择最优方案

# 删除未选中的方案
rm -rf features/experiment_approach_b
```

## 6. 最佳实践

### ✅ 推荐做法
1. **小步迭代**：先实现最小可用版本，通过测试后再扩展
2. **测试驱动**：先写测试用例，再实现功能
3. **文档同步**：边开发边更新 FEATURE.md
4. **保留记录**：即使功能已集成，也保留模块目录作为历史记录
5. **复用模式**：参考已有模块（如 dribbling）的结构

### ❌ 避免做法
1. **不写文档**：FEATURE.md 是必需的，不要跳过
2. **不写测试**：至少要有基本的自动化测试
3. **提前优化**：先让功能可用，再考虑优化
4. **孤立开发**：定期在完整游戏中测试集成效果
5. **忽略已知问题**：在 FEATURE.md 中如实记录问题

## 7. 工具和技巧

### 快速查看功能状态
```bash
cat features/README.md
```

### 运行所有测试（待实现）
```bash
# 未来可以创建一个统一的测试运行器
godot --path . -s features/run_all_tests.gd
```

### 查看带球示例
带球功能是第一个完整的示例，参考它的结构：
```bash
tree features/dribbling/
cat features/dribbling/FEATURE.md
```

### 调试技巧
1. **可视化调试**：参考 `scenes/debug/dribble_debug_draw.gd`
2. **打印关键数值**：在测试中打印中间结果
3. **分步验证**：每个测试用例只测一个点

## 8. 获取帮助

### 参考文档
- [功能模块化框架](../../docs/superpowers/feature-module-framework.md) - 完整框架说明
- [WE2000 核心技术](../../docs/we2000-core-techniques.md) - 技术参考
- [带球功能示例](../dribbling/FEATURE.md) - 完整示例

### 检查清单
如果遇到问题，按顺序检查：
1. [ ] FEATURE.md 填写完整了吗？
2. [ ] 自动化测试覆盖了核心逻辑吗？
3. [ ] 手动测试场景可以正常运行吗？
4. [ ] 实现文件清单准确吗？
5. [ ] 测试结果记录了吗？

---

**记住**：功能模块化的目的是让每个功能都能独立验证，逐步集成。不要追求完美，先让它工作起来，再迭代优化。
