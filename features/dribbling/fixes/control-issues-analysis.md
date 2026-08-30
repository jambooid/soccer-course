# 控球体验问题分析与修复方案

## 问题描述

用户反馈三个核心体验问题：

1. **球员切换过早** - 手动控制的球员在没有实质性得到球权时就切换了
2. **移动响应迟钝** - 球员移动惯性过大，按键响应慢，违反"体验优先"原则
3. **球不跟脚** - 获得球权后球容易脱离控制，无法稳定带球

## 根本原因分析

### 问题 1：球员切换逻辑

**当前实现：**
```gdscript
# BallStateDribbling._enter_tree():36
GameEvents.ball_possessed_by.emit(carrier)

# ActorsContainer._on_ball_possessed():157
func _on_ball_possessed(player: Player) -> void:
    # 立即切换控制权到获球球员
    _swap_control_to(player, Player.ControlScheme.P1, squad)
```

**问题：**
- `ball_possessed_by` 在进入 DRIBBLING 状态的 `_enter_tree()` 就发出
- 此时球员刚开始带球，可能还在"接球宽限期"（0.3 秒），球权并不稳定
- 导致球还没真正控住就切换了球员

**修复方案：**
- 延迟切换：等待宽限期结束后才发出"稳定控球"信号
- 新增信号：`ball_possession_stable(player)` - 在宽限期结束后发出
- 切换逻辑改为监听稳定信号，而不是初始获球信号

### 问题 2：移动响应迟钝

**当前实现：**
```gdscript
# PlayerStateMoving.handle_human_movement():63
player.velocity = player.velocity.move_toward(Vector2.ZERO, player.speed * 3.0 * delta)
```

**问题：**
- 减速系数 `3.0` 相对于最大速度来说太小
- 典型球员速度 60-80 px/s，减速度只有 180-240 px/s²
- 在 60fps 下，每帧只减速 3-4 px/s，停下来需要 15-20 帧（0.25-0.33 秒）
- 按键响应时也受此影响，方向切换时旧速度衰减慢

**修复方案：**
- 大幅提高减速系数到 `8.0`（从 3.0 提升到 8.0）
- 加速度提高到 `10.0`（新增）
- 按键有输入时立即设置目标速度，减少惯性延迟
- 参考 WE2000 的"即按即停"手感

### 问题 3：球不跟脚

**当前实现：**
```gdscript
# BallStateDribbling._process():110
if dist > max_control and to_ball.dot(player_dir) > 0:
    _release_ball()
```

**问题：**
- 失控判定纯粹基于距离阈值
- 球的物理运动（摩擦、碰撞反弹）可能让球偏离
- 触球区判定是椭圆形，但球可能在触球冷却期内飘出去
- 静止控球的"吸回"逻辑只在低速时生效

**修复方案：**
- 增强静止/低速时的吸附力（从 `0.1` 提高到 `0.3`）
- 减小触球冷却时间（让触球更频繁）
- 宽限期延长到 0.5 秒（从 0.3）
- 添加"跟随辅助"：当球速度与球员速度方向偏离太大时，给球一个回正力

## 修复优先级

- **P0（必须修）**: 问题 1（切换逻辑）和问题 2（响应速度）
- **P1（应该修）**: 问题 3（球跟脚）的宽限期和吸附力调整
- **P2（可选）**: 问题 3 的高级跟随辅助

## 实现计划

1. 修改 `BallStateDribbling`：添加稳定控球信号
2. 修改 `ActorsContainer`：切换逻辑改为监听稳定信号
3. 修改 `PlayerStateMoving`：提高加减速系数
4. 调整带球参数：宽限期、吸附力、触球频率
5. 测试验证：在 `test_manual_scene.tscn` 中验证手感
