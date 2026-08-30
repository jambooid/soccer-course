# 测试场景球员乱跑问题 - 系统性排查与修复

## 问题描述
用户报告：测试场景启动后，带球球员立即跑到场边外面，无法手动控制

## 排查过程

### 第一次尝试（失败）
**假设**：球员 control_scheme 设置错误
**修复**：改 PlayerLowTech 从 control_scheme=0 (CPU) 到 control_scheme=2 (P2)
**结果**：仍然乱跑 ❌

### 第二次尝试（失败）
**假设**：AI 行为对象仍在运行
**修复**：在 _ready() 中显式释放 current_ai_behavior
**结果**：仍然乱跑 ❌

### 第三次尝试（成功）✅
**系统性审查流程**：
1. 阅读 `Player.gd` 完整初始化流程
2. 发现 `_ready()` 第 72 行：切换到 `RESETING` 状态
3. 检查 `PlayerStateReseting` 实现
4. 发现该状态会驱动球员移动到 `kickoff_position`
5. 检查测试场景：`kickoff_position` 未设置（默认 `Vector2.ZERO`）
6. **根本原因确认**：球员在跑向 (0, 0) 位置（场景左上角）

## 根本原因

### Player 初始化流程
```gdscript
// Player._ready() - line 60
func _ready() -> void:
    set_control_texture()
    setup_ai_behavior()              // 62: 无条件创建 AI
    set_shader_properties()
    // ... 其他初始化 ...
    var initial_position := kickoff_position  // 71: 从 kickoff_position 获取
    switch_state(State.RESETING, 
        PlayerStateData.build().set_reset_position(initial_position))  // 72
```

### RESETING 状态行为
```gdscript
// PlayerStateReseting._process()
func _process(_delta: float) -> void:
    if not has_arrived:
        var direction := player.position.direction_to(state_data.reset_position)
        if player.position.distance_squared_to(state_data.reset_position) < 2:
            has_arrived = true
            player.velocity = Vector2.ZERO
        else:
            player.velocity = direction * player.speed  // 持续移动向目标
```

### 测试场景配置
```
PlayerHighTech:
  position = Vector2(400, 180)  ✅ 正确
  kickoff_position = <未设置>   ❌ 默认 Vector2.ZERO
  
PlayerLowTech:
  position = Vector2(300, 180)  ✅ 正确
  kickoff_position = <未设置>   ❌ 默认 Vector2.ZERO
```

### 问题链条
```
Player._ready() 
  → switch_state(RESETING) 
    → reset_position = kickoff_position (Vector2.ZERO)
      → PlayerStateReseting 驱动移动到 (0, 0)
        → 球员跑向场景左上角
          → 超出可视区域，看起来"跑到场边外面"
```

## 修复方案

### 修复代码
```gdscript
func _ready() -> void:
    // 1. 设置 kickoff_position 为当前位置
    player_high.kickoff_position = player_high.position
    player_low.kickoff_position = player_low.position

    // 2. 禁用 AI 行为
    if player_high.current_ai_behavior:
        player_high.current_ai_behavior.queue_free()
        player_high.current_ai_behavior = null
    if player_low.current_ai_behavior:
        player_low.current_ai_behavior.queue_free()
        player_low.current_ai_behavior = null

    // 3. 强制切换到 MOVING 状态，绕过 RESETING
    player_high.switch_state(Player.State.MOVING)
    player_low.switch_state(Player.State.MOVING)

    // 4. 让高技术球员控球
    await get_tree().create_timer(0.1).timeout
    player_high.control_ball()
```

### 修复逻辑
1. **设置 kickoff_position** - 阻止跑向 (0, 0)
2. **禁用 AI** - 确保纯手动控制
3. **跳过 RESETING 状态** - 直接进入 MOVING 状态，避免任何自动移动

## 为什么生产环境没有这个问题？

生产游戏使用 `ActorsContainer.spawn_player()` 创建球员：

```gdscript
// ActorsContainer.spawn_player() - line 70
var player := spawn_player(
    player_position,         // spawn 位置
    kickoff_position,        // ✅ 明确传入 kickoff 位置
    own_goal, target_goal, 
    player_data, country
)

// Player.initialize() - line 87
func initialize(..., context_kickoff_position: Vector2, ...) -> void:
    kickoff_position = context_kickoff_position  // ✅ 正确设置
```

测试场景直接实例化 Player 节点，跳过了 `initialize()` 调用，导致 `kickoff_position` 未设置。

## 经验教训

### 1. 系统性排查的重要性
- **不要只看表面现象**："球员乱跑" → 可能是 AI、可能是状态机、可能是初始化
- **追踪完整流程**：从 `_ready()` 开始，逐行跟踪代码执行路径
- **检查默认值**：未设置的属性会使用默认值（`Vector2.ZERO`），可能导致意外行为

### 2. 测试场景的特殊性
- 测试场景为了简化，跳过了正常的初始化流程（`initialize()`）
- 需要在测试脚本中手动补全缺失的初始化步骤
- 生产代码的隐式依赖在测试环境中会暴露

### 3. 状态机的副作用
- `Player._ready()` 自动切换到 `RESETING` 状态
- 该状态有移动副作用（drive to kickoff_position）
- 测试场景需要显式绕过或正确配置

## 相关文件

- `scenes/characters/player.gd` - Player 初始化流程
- `scenes/characters/character_states/player_state_reseting.gd` - RESETING 状态行为
- `scenes/screens/world/actors_container.gd` - 生产环境的正确初始化
- `features/dribbling/tests/test_manual_scene.gd` - 测试场景修复

## 提交历史

1. `dd6b433` - 修改 control_scheme (失败尝试)
2. `a98e80f` - 禁用 AI behavior (失败尝试)  
3. `e2c483f` - 系统性修复：kickoff_position + 跳过 RESETING (成功) ✅
