# Soccer Course 测试策略与测试计划

> 测试驱动开发在游戏项目中的务实落地
>
> 版本：v1.0 · 日期：2026-08-20

---

## 一、游戏项目 TDD 的特殊性

游戏开发和传统软件开发有本质区别，TDD 不能直接照搬：

| 传统软件 TDD | 游戏开发 |
|-------------|---------|
| 功能正确 = 行为符合预期 | "手感好" 是主观的，不可完全自动化断言 |
| 输入 → 输出 可精确预测 | 视觉/听觉反馈占一半体验 |
| 测试可以锁定正确行为 | 手感需要反复迭代，测试不能锁死参数 |
| 单元测试价值最高 | 集成测试 + 回归测试价值最高 |

**所以我们的测试策略不是"先写测试再写代码"，而是：**

> **每做一个系统，就写一套能自动验证"它是否按设计工作"的脚本，防止后续改动搞坏它。**

游戏的手感是渐进式调优的，参数会反复变。测试的价值不在于证明"现在是对的"，而在于**发现"什么时候变坏了"**。

---

## 二、测试分层策略

```
┌─────────────────────────────────────────────┐
│  L4: 手感回归测试（手动 checklist）          │  ← 主观，人来跑
│  过人手感、射门手感、传球手感、AI 表现      │
├─────────────────────────────────────────────┤
│  L3: 场景集成测试（GUT 框架）               │  ← 半自动，加载场景验证
│  开球流程、进球流程、越位判定、换人流程      │
├─────────────────────────────────────────────┤
│  L2: 系统级测试（纯逻辑 + 轻量场景）        │  ← 全自动，Headless 模式
│  球物理、断球判定、AI 决策、阵型归位         │
├─────────────────────────────────────────────┤
│  L1: 单元测试（纯函数/工具类）              │  ← 全自动，快速
│  PassAccuracy、InterceptResolver、          │
│  SeededRandom、FormationManager             │
└─────────────────────────────────────────────┘
```

越往下越自动化、越稳定；越往上越接近真实游戏体验、越能发现真问题。

---

## 三、L1 单元测试 — 纯逻辑工具类

### 3.1 适用范围

所有**纯函数式**的工具类 — 输入确定、输出确定、不依赖 Godot 场景树、不依赖帧循环。

### 3.2 测试框架选择

Godot 4 内置 `GDScriptUnitTestRunner` 或使用 GUT (Godot Unit Testing)。考虑到项目规模和简洁性，使用 Godot 内置的 `assert` + 自定义轻量测试 runner 即可。

```
tests/
  test_runner.gd          # 测试运行器（Autoload 或命令行运行）
  unit/
    test_pass_accuracy.gd
    test_intercept_resolver.gd
    test_seeded_random.gd
    test_offside_judge.gd
  integration/
    test_ball_physics.gd
    test_formation.gd
  scenes/
    test_goal_scoring.tscn
    test_kickoff.tscn
```

### 3.3 测试 runner 设计

```gdscript
# tests/test_runner.gd
class_name TestRunner
extends Node

var passed := 0
var failed := 0
var results: Array = []

func run_all_tests() -> void:
    passed = 0
    failed = 0
    results.clear()

    # 注册所有测试类
    var test_classes := [
        preload("res://tests/unit/test_pass_accuracy.gd"),
        preload("res://tests/unit/test_intercept_resolver.gd"),
        preload("res://tests/unit/test_seeded_random.gd"),
        # ...
    ]

    for test_class in test_classes:
        var instance := test_class.new()
        run_test_suite(instance)

    print_summary()

func run_test_suite(instance: Object) -> void:
    var methods := instance.get_method_list()
    for method in methods:
        if method.name.begins_with("test_"):
            var test_name = "%s.%s" % [instance.get_class(), method.name]
            var start_time := Time.get_ticks_msec()
            try:
                instance.set_up()
                instance.call(method.name)
                instance.tear_down()
                passed += 1
                results.append({"name": test_name, "passed": true,
                    "duration": Time.get_ticks_msec() - start_time})
            except error:
                failed += 1
                results.append({"name": test_name, "passed": false,
                    "error": error.message,
                    "duration": Time.get_ticks_msec() - start_time})
```

### 3.4 测试用例示例

#### test_pass_accuracy.gd

```gdscript
class TestPassAccuracy extends RefCounted

func set_up() -> void: pass
func tear_down() -> void: pass

func test_short_pass_high_technique_low_error() -> void:
    var player := _make_player(technique=90)
    var error := PassAccuracy.calculate_pass_error(player, 50.0, 0.0, false)
    assert(error < 10.0, "技术 90 的球员短传误差应小于 10px，实际 %f" % error)

func test_long_pass_low_technique_high_error() -> void:
    var player := _make_player(technique=30)
    var error := PassAccuracy.calculate_pass_error(player, 150.0, 0.0, false)
    assert(error > 20.0, "技术 30 的球员长传误差应大于 20px，实际 %f" % error)

func test_pressure_increases_error() -> void:
    var player := _make_player(technique=60)
    var no_pressure := PassAccuracy.calculate_pass_error(player, 80.0, 0.0, false)
    var high_pressure := PassAccuracy.calculate_pass_error(player, 80.0, 0.8, false)
    assert(high_pressure > no_pressure * 1.5, "高压下误差应至少是无压的 1.5 倍")

func _make_player(technique: int) -> Player:
    # 用 mock 或直接构造 PlayerResource
    var data := PlayerResource.new()
    data.technique = technique
    var player := Player.new()
    player.player_data = data
    return player
```

#### test_intercept_resolver.gd

```gdscript
class TestInterceptResolver extends RefCounted

func test_straight_dribble_gets_stolen() -> void:
    """直直带球冲向防守者 → 应该被断球"""
    var attacker := _make_attacker(position=Vector2(50, 0), velocity=Vector2.RIGHT * 100)
    var defender := _make_defender(position=Vector2(100, 0))
    var ball := _make_ball(state=Ball.State.CARRIED, is_free=true, velocity=Vector2.RIGHT * 110)

    var result := InterceptResolver.check_auto_intercept(defender, attacker, ball)
    assert(result.success, "直直带球应该被断")
    assert(result.quality > 0.5, "正面断球质量应该较高")

func test_curve_dribble_gets_past() -> void:
    """变向过人 → 不应该被断"""
    var attacker := _make_attacker(position=Vector2(50, 0), velocity=Vector2(100, 30))
    var defender := _make_defender(position=Vector2(100, 5))
    var ball := _make_ball(state=Ball.State.CARRIED, is_free=true, velocity=Vector2(110, 33))

    var result := InterceptResolver.check_auto_intercept(defender, attacker, ball)
    assert(not result.success, "大角度变向应该能过人")
    assert(result.reason == "bad_angle", "失败原因应该是角度不对")

func test_ball_not_free_no_intercept() -> void:
    """球在脚上（不在步点窗口）→ 不能被断"""
    var attacker := _make_attacker(position=Vector2(50, 0), velocity=Vector2.RIGHT * 100)
    var defender := _make_defender(position=Vector2(60, 0))  # 很近
    var ball := _make_ball(state=Ball.State.CARRIED, is_free=false, velocity=Vector2.RIGHT * 110)

    var result := InterceptResolver.check_auto_intercept(defender, attacker, ball)
    assert(not result.success, "球在脚上时不能被断")
    assert(result.reason == "ball_not_in_window")

func test_high_defense_bigger_radius() -> void:
    """防守属性高 → 断球半径更大"""
    var attacker := _make_attacker(position=Vector2(50, 0), velocity=Vector2.RIGHT * 100)
    var defender_low := _make_defender(position=Vector2(105, 0), defense=20)
    var defender_high := _make_defender(position=Vector2(105, 0), defense=90)
    var ball := _make_ball(state=Ball.State.CARRIED, is_free=true, velocity=Vector2.RIGHT * 110)

    var result_low := InterceptResolver.check_auto_intercept(defender_low, attacker, ball)
    var result_high := InterceptResolver.check_auto_intercept(defender_high, attacker, ball)
    assert(not result_low.success, "低防守在边界外应该断不到")
    assert(result_high.success, "高防守在同样距离应该能断到")
```

### 3.5 应该写 L1 测试的模块（按里程碑）

| 模块 | 里程碑 | 测试价值 | 预计用例数 |
|------|--------|---------|-----------|
| `SeededRandom` | M2 | ⭐⭐⭐⭐⭐ 确定性是设计基石 | 3-5 |
| `PassAccuracy` | M2 | ⭐⭐⭐⭐ 参数多、边界多 | 8-12 |
| `InterceptResolver` | M1 | ⭐⭐⭐⭐⭐ 手感核心，改参数容易回归 | 10-15 |
| `OffsideJudge` | M1 | ⭐⭐⭐⭐ 规则复杂，edge case 多 | 8-10 |
| `FormationManager` | M2 | ⭐⭐⭐ 纯计算，容易测 | 5-8 |
| `ActionSelector` | M2 | ⭐⭐⭐ 多因子决策，需要验证各维度 | 6-10 |
| `PhysicalContestResolver` | M3 | ⭐⭐⭐ 数值规则，需要平衡 | 8-10 |
| `InputBuffer` | M1 | ⭐⭐⭐ 简单但关键 | 4-6 |

---

## 四、L2 系统级测试 — 球物理 + AI 决策

### 4.1 适用范围

依赖 Godot 节点但**不依赖视觉/交互**的系统。可以在 headless 模式下运行，通过代码构造轻量场景来验证。

### 4.2 测试方式

使用 Godot 的 `--headless` 模式，代码构造最小测试场景。

#### 示例：球物理弹道测试

```gdscript
# tests/integration/test_ball_physics.gd

func test_ball_predict_landing_matches_actual() -> void:
    """球的落地预测 API 必须和实际物理一致"""
    var test_scene := _setup_minimal_scene()
    var ball := test_scene.ball

    # 设置初始状态：水平 200px/s，竖直 150px/s
    ball.position = Vector2(0, 0)
    ball.velocity = Vector2(200, 0)
    ball.height = 0.0
    ball.height_velocity = 150.0
    ball.switch_state(Ball.State.KICKED)

    var predicted := ball.predict_landing_position()

    # 运行物理直到球落地
    var frames := 0
    while ball.height > 0.0 or ball.height_velocity > 0.0:
        ball._physics_process(1.0/60.0)
        frames += 1
        if frames > 600:  # 10 秒超时
            break

    # 预测位置 vs 实际位置误差 < 5px
    var error := ball.position.distance_to(predicted)
    assert(error < 5.0, "落地预测误差应 < 5px，实际 %f" % error)

func test_short_pass_stops_near_target() -> void:
    """短传应该在目标位置附近停下"""
    var test_scene := _setup_minimal_scene()
    var ball := test_scene.ball
    var target := Vector2(100, 0)

    ball.position = Vector2.ZERO
    ball.short_pass(target, 1.0)

    # 等待球停下
    var frames := 0
    while ball.velocity.length() > 5.0:
        ball._physics_process(1.0/60.0)
        frames += 1
        if frames > 300:
            break

    var distance := ball.position.distance_to(target)
    assert(distance < 15.0, "短传应停在目标 15px 内，实际距离 %f" % distance)
```

#### 示例：AI 决策测试

```gdscript
# tests/integration/test_ai_decisions.gd

func test_cpu_shoots_when_near_goal() -> void:
    """CPU 在射门范围内且角度好时应该射门"""
    var test_scene := _setup_test_scene()
    var attacker := test_scene.add_player(
        country="BRAZIL", position=Vector2(-30, 0), control=ControlScheme.CPU)
    test_scene.ball.carrier = attacker
    test_scene.target_goal.position = Vector2(-200, 0)  # 很近

    attacker.ai_behavior.perform_ai_decisions()

    assert(attacker.current_state == Player.State.SHOOTING or
           attacker.current_state == Player.State.PREPPING_SHOT,
           "近距离面对球门时 CPU 应该射门")

func test_cpu_passes_when_pressured() -> void:
    """被紧逼时 CPU 应该传球而不是硬带"""
    var test_scene := _setup_test_scene()
    var attacker := test_scene.add_player(
        country="BRAZIL", position=Vector2(0, 0), control=ControlScheme.CPU)
    var defender := test_scene.add_player(
        country="GERMANY", position=Vector2(15, 0), control=ControlScheme.CPU)
    var teammate := test_scene.add_player(
        country="BRAZIL", position=Vector2(-50, 30), control=ControlScheme.CPU)
    test_scene.ball.carrier = attacker

    attacker.ai_behavior.perform_ai_decisions()

    assert(attacker.current_state == Player.State.PASSING or
           attacker.current_state == Player.State.SHORT_PASSING,
           "被紧逼时 CPU 应该传球")
```

### 4.3 应该写 L2 测试的系统

| 系统 | 测试价值 | 关键验证点 |
|------|---------|-----------|
| 球物理弹道 | ⭐⭐⭐⭐⭐ 确定性是一切的基础 | 落地预测 = 实际落点、短传停在目标附近、弹跳能量守恒 |
| 带球步点 | ⭐⭐⭐⭐ 断球机制的基础 | 技术高触球频、速度快跑幅大 |
| AI 决策树 | ⭐⭐⭐⭐ 防止 AI 行为退化 | 近门射门、紧逼传球、空当带球 |
| 阵型归位 | ⭐⭐⭐ | 球移动时阵型整体平移、攻防阶段偏移正确 |
| 控球权切换 | ⭐⭐⭐ | 得球自动切、防守切最近的 |

---

## 五、L3 场景集成测试 — 游戏流程

### 5.1 适用范围

完整场景加载后的流程验证。不是自动化的"断言 pass/fail"，而是**一键加载测试场景，人眼快速检查**的半自动测试。

### 5.2 测试场景清单

```
tests/scenes/
  test_goal_scoring.tscn       # 验证进球判定：球从不同角度射入
  test_kickoff_flow.tscn       # 验证开球流程：进球 → 庆祝 → 归位 → 开球
  test_offside.tscn            # 验证越位判定：各种越位/不越位场景
  test_corner_kick.tscn        # 验证角球流程：出底线 → 摆球 → 开球
  test_substitution.tscn       # 验证换人流程
  test_penalty.tscn            # 验证点球流程
  test_free_kick.tscn          # 验证任意球
```

每个测试场景：
- 预设好球员位置和球状态
- 有一个"播放"按钮自动触发事件
- 旁边有说明文字，告诉测试者应该看到什么

### 5.3 测试菜单

在游戏的主菜单加一个隐藏的"测试场景"入口（按某个组合键进入），列出所有测试场景，点击即可加载。

**价值**：每次改完相关系统，花 30 秒加载对应测试场景看一眼，比打完整场比赛快得多。

---

## 六、L4 手感回归检查清单（手动）

### 6.1 为什么需要手动

手感是主观的——你可以写测试断言"球在第 N 帧被断"，但你不能写测试断言"断球手感像 WE2000"。

但手感的**退化**是可以被人快速感知的。所以我们需要一个清单，每次大改之后对着过一遍。

### 6.2 手感回归 Checklist

#### 带球 & 过人
- [ ] 直直冲向静止的防守者 → 球会被断（距离越近断得越干脆）
- [ ] 在最后一刻变向 → 能过人（时机对的话）
- [ ] 太早变向 → 防守者能调整位置，还是会被断
- [ ] 技术好的球员带球更"黏脚"，更难过掉
- [ ] 高速带球更容易丢球
- [ ] 按住 L1 护球 → 防守者更难断球，但自己也跑不快

#### 传球
- [ ] 短传准度高，基本能传到脚下
- [ ] 长传有弧线，落点准确
- [ ] 直塞能送到队友前方空当
- [ ] 被紧逼时传球精度下降（能感觉到传偏）
- [ ] 技术差的球员传球偏差更大

#### 射门
- [ ] 禁区内射门精度高
- [ ] 远射容易偏
- [ ] 蓄力满射门力量大
- [ ] 被干扰时射门变形

#### 防守
- [ ] 站在传球路线上能自动断球
- [ ] 站在带球路线上能自动断球
- [ ] 铲球范围比自动断球大，但铲空有硬直
- [ ] 防守 AI 不会一窝蜂冲球，有层次

#### AI
- [ ] 队友会主动跑位（前插、拉边、回撤）
- [ ] CPU 进攻有章法，不是瞎带
- [ ] 门将单刀会出击
- [ ] 不同难度有明显差异

#### 节奏
- [ ] 比赛时间感觉合适（不会太快或太慢）
- [ ] 进球后庆祝时间刚好（不长不短）
- [ ] 整体节奏有快有慢

---

## 七、测试与实施的配合方式

### 7.1 推荐工作流

不是严格的"先写测试再写代码"，而是**每个功能任务包含 3 个阶段**：

```
1. 写实现（能跑就行）
      ↓
2. 写测试（验证实现符合设计）
      ↓
3. 调参 + 手动手感验证
      ↓
4. 测试固化（锁定当前参数下的正确行为）
```

测试的作用是**锁住"当前是好的"状态**，以后改别的东西时如果跑不过测试，就知道哪里被改坏了。

### 7.2 每个里程碑的测试产出

| 里程碑 | 新增 L1 测试 | 新增 L2 测试 | 新增 L3 测试场景 | L4 检查项 |
|--------|-------------|-------------|-----------------|----------|
| M1 | `InputBuffer`, `InterceptResolver`, `OffsideJudge` | 球物理、带球步点 | 开球/进球、越位测试场景 | 带球过人手感、传球手感、防守断球 |
| M2 | `SeededRandom`, `PassAccuracy`, `FormationManager`, `ActionSelector` | AI 决策、阵型归位 | 角球/任意球、设置 | 蓄力手感、误差感、难度差异 |
| M3 | `PhysicalContestResolver` | 防守 AI、身体对抗 | 换人流程、加时赛 | 防守站位、对抗手感、球队风格 |
| M4 | （按需补充） | 点球、弧线球 | 点球大战 | 假动作、体力节奏 |

### 7.3 运行方式

```bash
# 运行所有单元测试（headless）
godot --path . --headless -s res://tests/test_runner.gd

# 运行单个测试类
godot --path . --headless -s res://tests/test_runner.gd --test=TestPassAccuracy

# 运行场景测试（带画面，人来检查）
godot --path . res://tests/scenes/test_offside.tscn
```

可以在 CI 里跑 L1 + L2，每次提交自动跑一遍。

---

## 八、优先级建议

**不是所有测试都要立刻写。** 按价值排序：

### 第一批（M1 就要写，最有价值）

1. **`InterceptResolver` 单元测试** — 手感核心，参数最多，最容易回归
2. **球物理弹道测试** — 所有系统的基础，必须保证确定性
3. **`OffsideJudge` 单元测试** — 规则复杂，edge case 多，自动化收益最高
4. **开球/进球 测试场景** — 每次改 GameManager 都能快速验证流程没坏

### 第二批（M2 写）

5. `PassAccuracy` 单元测试
6. `ActionSelector` 单元测试
7. `FormationManager` 单元测试
8. AI 决策集成测试
9. 越位/角球 测试场景

### 第三批（M3/M4 按需补充）

10. `PhysicalContestResolver`
11. 换人/加时 测试场景
12. 其他边缘系统

---

## 九、反模式（测试里不要做的事）

| 反模式 | 为什么 |
|--------|--------|
| 追求 100% 代码覆盖率 | 游戏代码大部分是"调出来的"，测试覆盖率高不等于游戏好玩 |
| 测试动画帧精确数值 | 动画会改，参数会调，测试会全崩。只测关键行为，不测精确数值 |
| 用测试锁定手感参数 | 手感需要反复迭代，参数会经常变。测试应该验证"关系"（技术越高误差越小），不验证"绝对值"（误差 = 15.3px） |
| 写大量 UI 测试 | UI 改得快，自动化测试维护成本太高 |
| 每个函数都写测试 | 价值密度低。只测"纯逻辑 + 高复杂度 + 容易回归"的部分 |
| 为了测试而过度抽象 | 不要为了"可测试性"把简单的事情搞复杂 |

---

> **核心原则**：测试是为了**防止退化**，不是为了证明正确。
>
> 写 10 个能抓住真 bug 的测试 > 写 100 个走形式的测试。

---

**文档版本**：v1.0
**日期**：2026-08-20
