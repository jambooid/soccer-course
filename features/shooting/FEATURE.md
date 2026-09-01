# 射门系统（Shooting）

**状态**：[TESTING]
**开始日期**：2026-08-31

## 1. 功能目标

持球时按住射门键会进入可取消的蓄力窗口，松开或蓄力满后才播放踢球动画并在触球帧出球。蓄力期间保留带球速度；方向输入不会取消蓄力或改变带球方向，只用于释放时的球门上下轨迹微调。

### WE2000 对照

采用 WE2000/PES 的“输入蓄力 -> 起手动画 -> 触球出球”节奏。射门方向自动吸附目标球门；蓄力期间球员保持原带球方向，方向输入只在出脚时微调目标线路。射门属性、距离和蓄力共同决定最终速度。

## 2. 成功标准

- [x] 蓄力比例在 0..1 内，力量随蓄力单调增加并有上限。
- [x] 射门方向自动吸附目标球门，并会依据属性、距离和蓄力调整力量。
- [x] technique、shooting、power 会影响目标线路；方向键可微调球门上下区域。
- [x] 蓄力期间方向键不会取消射门或改变球员带球方向，球保持 `DRIBBLING`。
- [x] 释放/蓄力满后才进入 `SHOOTING` 并由动画回调触球。
- [ ] 纯函数自动化测试通过（当前 Godot 二进制无法启动，见验证记录）。
- [ ] 主游戏手动手感验证（待在 Godot 窗口完成）。

## 3. 实现要点

- `ShootingPhysics` 计算 1.5 秒上限的蓄力比例、球门瞄准和射门速度，并根据 technique、shooting、power 调整目标线路。
- `PlayerStatePreppingShot` 不再播放 `prep_kick` 或清零速度；蓄力期间忽略方向对球员移动的影响。
- `PlayerStateShooting` 只负责踢球动画和触球回调，并清理玩家蓄力显示状态。
- 速度范围为 90..520 px/s；射门属性提供 0.78..1.18 倍修正；距离提供 0.75..1.35 倍自动补偿。
- 可调参数统一位于 `PitchConstants.PLAYER` 的 SHOOT 常量组。

## 4. 属性影响

| 属性 | 影响 | 手感 |
|---|---|---|
| `power` | 基础球速 | 力量高的球员更有重炮感 |
| `shooting` | 瞄准输入权重、速度倍率 | 高射门属性更容易命中选择的区域 |
| 距离球门 | 自动力量补偿 | 远距离不会因固定速度而明显变弱 |

## 5. 文件清单

- `utils/shooting_physics.gd` - 可测试的瞄准、蓄力和速度计算。
- `scenes/characters/player.gd` - 暴露 `charge_display` / `is_charging`。
- `scenes/characters/character_states/player_state_prepping_shot.gd` - 可取消蓄力状态。
- `scenes/characters/character_states/player_state_shooting.gd` - 动画后触球及状态清理。
- `features/shooting/tests/test_physics.gd` - L1 纯函数测试。
- `features/shooting/tests/test_manual_scene.tscn` - 独立手动测试场景，可直接运行。
- `features/shooting/tests/test_manual_scene.gd` - 球权切换、重置、调试瞄准线和状态 HUD。

## 6. 测试策略

自动化覆盖边界、球门辅助方向、蓄力单调性和属性差异。独立手动场景验证从带球进入蓄力、方向锁定、动画触球、球门命中和属性差异。

运行：

```bash
godot --headless --path . -s features/shooting/tests/test_physics.gd

# 独立手动测试场景
godot --path . features/shooting/tests/test_manual_scene.tscn
```

## 7. 已知问题与后续

- 当前没有专用 HUD 力量条；`Player.charge_display` 已预留给 HUD。
- 2D 球门只有中心点/上下方向辅助，弧线和搓射属于后续功能。
- 手动 Godot 场景验证仍需在有窗口环境执行。

## 8. 验证记录

自动化测试和手动测试结果分别记录在 `validation/test-results.txt` 和 `validation/checklist.md`。当前状态为 `[TESTING]`。

## 9. 参考资料

- `docs/we2000-core-techniques.md` §9（输入缓冲、触球时机）
- `docs/we2000-implementation-research.md` §4（动画事件与出球）
- `docs/how-godot-2d-shoot.md`
- `features/dribbling/FEATURE.md`
