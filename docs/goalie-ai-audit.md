# 守门员 AI 审查报告与修复计划

> 审查日期：2026-08-23
> 审查范围：守门员 AI 决策、跑位、与球的交互状态
> 状态：**Phase 1 已实施并通过 runtime 验证**

## 一、问题总览

| 级别 | 编号 | 问题 | 影响 |
|------|------|------|------|
| 🔴 P0 | #1 | `can_carry_ball()` 对门将 MOVING 状态返回 false，AI 永远不触发扑救 | 门将形同虚设，不会主动飞身扑救 |
| 🔴 P0 | #2 | SHOT 状态下高速射门穿过门将身体无反应（直接 return） | 站着的门将近乎空气，射门直接穿身 |
| 🔴 P1 | #3 | HELD_BY_GOALKEEPER 释放球时不发射 `ball_released` 信号 | 控球时间统计永久累计，永不归零 |
| 🟠 P1 | #4 | FREEFORM/KICKED/DEFLECTED 中门将抱球导致双重状态切换 | 潜在崩溃/状态不一致 |
| 🟠 P2 | #5 | 门将抱球被铲伤时，球状态强制切换但不发 `ball_released` | 信号泄漏，统计偏差 |
| 🟠 P2 | #6 | SAVED 状态二次扑救不校验门将身份（只查距离） | 边界 case 异常 |
| 🟡 P3 | #7 | `can_carry_ball()` 语义混淆（运球 vs 交互） | 概念混乱，易出新 bug |
| 🟡 P3 | #8 | 门将 AI tick 固定 80ms，不参与 LOD 分级 | 性能浪费（远端也高频决策） |
| 🟡 P3 | #9 | 扑救方向依赖 `player.heading`，纯侧向移动时 heading 不变 | 特殊情况下方向略偏 |
| 🟡 P3 | #10 | `_should_rush_out()` 地滚球判断逻辑冗余 | 可读性差 |

## 二、详细问题分析

### P0-1：门将 MOVING 状态 `can_carry_ball()` 返回 false

**文件**: `scenes/characters/character_states/player_state_moving.gd:77-78`

```gdscript
func can_carry_ball() -> bool:
    return player.role != Player.Role.GOALIE
```

**链路**:
- `AIBehaviorGoalie._should_dive_save()` 第一行：`if not player.can_carry_ball(): return false`
- `player.can_carry_ball()` → `current_state.can_carry_ball()` → MOVING 状态返回 false
- **结果：守门员永远不会主动决定飞身扑救**

**修复**: MOVING 状态下所有球员都能与球交互，返回 `true`。
门将 vs 场上球员的控球方式差异（抱球 vs 带球）由球状态侧的 `body.role == GOALIE` 分支处理，不在这里限制。

---

### P0-2：SHOT 状态高速射门碰门将直接穿过

**文件**: `scenes/ball/ball_states/ball_state_shot.gd:57-67`

```gdscript
if body.role == Player.Role.GOALIE:
    if 慢速低球:
        抱住
    # 高速/高球 → 保持 SHOT 状态，让 DIVING 状态的 ball_detection_area 触发扑救
    return  # ← 什么都不做，球穿过门将身体
```

**问题**: 只有门将处于 DIVING 状态时球才会被处理。如果门将还没进入扑救（AI 没决策、或正处于其他状态），球直接穿过门将身体飞向球门。

**修复**: 高速射门击中站着的门将时，触发折射（deflect），球打在身上弹开。
主动扑救的价值仍然存在：扑救方向更明确，可以把球托出危险区而不是随机折射。

---

### P1-3：HELD_BY_GOALKEEPER 释放时缺少 `ball_released`

**文件**: `scenes/ball/ball_states/ball_state_held_by_goalkeeper.gd`

三个释放路径都不发射 `ball_released`：
- `_auto_kick()`
- `release_with_throw()`
- `release_with_kick()`

对比：`ball_state_carried.gd:181` 和 `ball_state_dribbling.gd:112` 都有发射。

**影响**:
- `GameManager` 控球时间统计永远不停止
- UI 球权显示不更新

**修复**: 在三个释放路径中，`carrier = null` 之前发射 `GameEvents.ball_released.emit()`。

---

### P1-4：FREEFORM/KICKED/DEFLECTED 中门将抱球 → 双重状态切换

**文件**:
- `scenes/ball/ball_states/ball_state_freeform.gd:14-17`
- `scenes/ball/ball_states/ball_state_kicked.gd:63-66`
- `scenes/ball/ball_states/ball_state_deflected.gd:41-44`

**模式**:
```gdscript
ball.hold_by_goalkeeper(body)   # 内部已调用 ball.switch_state(HELD_BY_GOALKEEPER)
transition_state(Ball.State.HELD_BY_GOALKEEPER)  # 又调一次！
```

第一次 `switch_state` 已经把当前状态 queue_free 并创建了新状态，紧接着的 `transition_state` 又触发一次切换——对一个即将被释放的节点发出的信号，其行为取决于 queue_free 的时机，存在不确定性。

**修复**: 保留 `ball.hold_by_goalkeeper(body)`，删除多余的 `transition_state(...)` 调用。

---

### P2-5：门将抱球被铲伤 → 球状态强制切换无信号

**场景**: 对方球员冲撞门将，门将进入 HURT 状态。

HURT 状态 `_enter_tree` 检查 `ball.carrier == player` 后调用 `ball.tumble()` → 球变成 KICKED 状态，carrier 被设为 null。

但 HELD_BY_GOALKEEPER 状态是被外部强制切换出去的，没有走正常的释放路径，因此不发射 `ball_released`。

**修复**: 在 `BallStateHeldByGoalkeeper._exit_tree()` 中兜底：如果退出时 carrier 仍不为 null（非正常释放），发射 `ball_released`。

由于正常释放路径（_auto_kick 等）在 transition 之前已经把 carrier 设为 null，不会重复发射。

---

### P2-6：SAVED 二次扑救不校验门将身份

**文件**: `scenes/ball/ball_states/ball_state_saved.gd:57-65`

`_check_nearby_goalie()` 只检查 `goalie.position.distance_to(ball.position)`，没有确认检测到的就是扑球的那个门将。

实际中对方门将不会跑到这边，但代码严谨性有问题。优先级低，暂不处理。

---

### P3-7 ~ P3-10：低优先级问题

详见总览表，待高优先级修复完成后视情况处理。

## 三、修复实施步骤

### Phase 1：核心修复（P0 + P1）

| 步骤 | 内容 | 涉及文件 |
|------|------|----------|
| 1 | 修复 `PlayerStateMoving.can_carry_ball()` 返回 true | `player_state_moving.gd` |
| 2 | 修复 SHOT 碰门将无反应 → 触发折射 | `ball_state_shot.gd` |
| 3 | 修复 HELD_BY_GOALKEEPER 释放信号 | `ball_state_held_by_goalkeeper.gd` |
| 4 | 修复双重状态切换（3个球状态） | `ball_state_freeform.gd` `ball_state_kicked.gd` `ball_state_deflected.gd` |
| 5 | HELD_BY_GOALKEEPER 加 `_exit_tree` 兜底信号 | `ball_state_held_by_goalkeeper.gd` |
| 6 | 验证：跑 `test_full_game.gd` 和 `test_runtime.gd` | - |

### Phase 2：次要修复（P2 + P3，可选）

| 步骤 | 内容 | 涉及文件 |
|------|------|----------|
| 7 | SAVED 二次扑救身份校验 | `ball_state_saved.gd` |
| 8 | 门将 AI 接入 LOD 系统 | `ai_behavior_goalie.gd` |
| 9 | 代码清理 + 注释完善 | 多处 |

## 四、验证方案

1. **功能验证**：运行 `test_full_game.gd`，观察：
   - 门将是否会做出扑救动作
   - 射门打在门将身上是否被挡出
   - 门将抱球后是否能正确发球
   - 控球时间统计是否合理

2. **稳定性验证**：运行 `test_runtime.gd`，60 秒无崩溃无状态错误

3. **手动验证**（可选）：在游戏中观察门将行为：
   - 对方射门时门将是否有反应
   - 门将站位、出击是否合理
   - 抱球 → 发球流程是否顺畅
