# Soccer Course 实施计划与任务清单

> 基于 `design-document.md` 设计规格 + 现有代码架构
>
> 版本：v1.0 · 日期：2026-08-20

---

## 总览

### 现有代码基线

- **引擎**：Godot 4.4 / GDScript / GL Compatibility
- **内部分辨率**：280×180（需扩展到 560×360）
- **球队阵容**：6 人/队（1 GK + 5 场上），需扩展到 11 人
- **状态机数量**：4 域（Game/Player/Ball/Screen），共 ~30 个状态
- **核心文件规模**：`player.gd` 202 行 / `ball.gd` 96 行 / `actors_container.gd` 121 行
- **已有功能**：传球、射门、铲球、头球、倒钩、凌空、锦标赛、hitstop、AI on-duty 权重

### 任务规模估计

| 里程碑 | 任务数 | 新增文件 | 修改文件 | 预估工作量（人天） |
|--------|--------|---------|---------|-----------------|
| M1 手感跃迁 | 18 | ~12 | ~20 | 15-20 天 |
| M2 玩法深度 | 16 | ~10 | ~18 | 12-16 天 |
| M3 AI 升级 | 12 | ~8 | ~15 | 10-14 天 |
| M4 完整度提升 | 8 | ~6 | ~10 | 8-12 天 |
| **合计** | **54** | **~36** | **~63** | **45-62 天** |

### 实施原则

1. **自底向上**：先做基础系统（输入、球物理、属性），再做上层（AI、UI、流程）
2. **每个任务独立可验证**：完成一个任务就能跑起来看到效果
3. **保持可玩**：每阶段结束时游戏都能完整运行（不会中间坏掉）
4. **优先手感**：每个系统第一版先做"能用"，再迭代调参优化手感

---

## M1：手感跃迁（P0 全部）

**目标**：11 人制 WE2000 式操作，传球准确，过人/断球有博弈，比赛可玩

**验收标准**：
- 能打满一场 2 分钟 11 vs 11 的比赛
- 四键操作流畅（短传/长传/直塞/射门 + 加速 + 特殊动作）
- 带球过人有手感（直直冲防守者会被断，变向能过人）
- 三种传球各有特点
- 越位规则生效
- 雷达小地图显示全局态势

### M1 任务列表

#### 基础层（先做这些，不依赖彼此）

##### M1-01：视窗扩大到 560×360

**文件**：`project.godot`、场景缩放调整、`camera.gd`

**改动要点**：
- `project.godot`: `viewport_width=560`, `viewport_height=360`, `window_width_override=2800`, `window_height_override=1800`
- 球场背景图重新适配（或用代码缩放）
- `Camera` 的 `DISTANCE_TARGET`、平滑速度等参数需要调整
- 所有 UI 元素的位置和大小可能需要重新校准
- 球场 spawn 点、球门位置等的坐标需要按比例调整

**依赖**：无
**工作量**：小（1 天）
**风险**：美术资源可能需要重做或缩放

---

##### M1-02：输入缓冲系统 InputBuffer

**文件**：
- 新增：`utils/input_buffer.gd`（Autoload）
- 修改：`project.godot`（新增 autoload 注册）、`player.gd`、各 player_state_*.gd

**改动要点**：
```gdscript
# input_buffer.gd — Autoload 单例
class_name InputBuffer
extends Node

const BUFFER_WINDOW_MS := 200
var buffer: Dictionary = {}  # action_name → timestamp_ms

func press(action: String) -> void: ...
func consume(action: String) -> bool: ...
func consume_any(actions: Array) -> String: ...
func clear() -> void: ...
```
- `Player._input()` 改为写入 `InputBuffer.press()` 而不是直接触发状态
- 各状态在可接受输入帧调用 `InputBuffer.consume()` 检查
- `KeyUtils` 增加 `is_action_buffered(scheme, action)` 封装

**依赖**：无
**工作量**：小（1 天）
**验证方式**：在射门动画中按传球键，动画结束后立即触发传球

---

##### M1-03：操作映射扩展为 WE2000 六动作键

**文件**：`project.godot`、`utils/key_utils.gd`、`player.gd`、`player_state_moving.gd`

**改动要点**：
- `project.godot` [input] 节新增：
  - P1：`p1_short_pass`(Z), `p1_long_pass`(X), `p1_through_pass`(C), `p1_sprint`(Shift), `p1_special`(Tab)
  - P2：`p2_short_pass`(1), `p2_long_pass`(2), `p2_through_pass`(3), `p2_sprint`(Q), `p2_special`(E)
- `KeyUtils.Action` 枚举扩展：`SHORT_PASS, LONG_PASS, THROUGH_PASS, SHOOT, SPRINT, SPECIAL`
- `PlayerStateMoving._process_input()` 重写为六动作分发
- 原 `p1_pass` / `p2_shoot` 映射迁移（保留过渡期或直接替换）

**依赖**：M1-02（输入缓冲）
**工作量**：中（2 天）
**验证方式**：六个按键各自触发不同动作，操作无冲突

---

##### M1-04：Player 属性扩展到 7 维

**文件**：
- 修改：`resources/player_resource.gd`、`assets/json/squads.json`、`utils/data_loader.gd`

**改动要点**：
- `PlayerResource` 新增字段：`technique`, `shooting`, `defense`, `jump`, `stamina`, `number`
- `squads.json` 每个球员增加这 5 个新字段 + `number` 球衣号
- 先填一版合理的初始值（参考 WE2000 球队能力分布）
- `DataLoader` 解析新字段（自动匹配，应该不用改太多）
- `player.gd` 中通过 `player_data.technique` 等访问

**依赖**：无
**工作量**：小（1 天）
**备注**：M1 只有部分属性会被实际使用（技术、防守用于断球），其他先存着后续用

---

#### 球物理层

##### M1-05：球新增 KICKED 状态（传球从 FREEFORM 中拆分）

**文件**：
- 新增：`scenes/ball/ball_states/ball_state_kicked.gd`
- 修改：`ball.gd`（State 枚举）、`ball_state_factory.gd`、`player_state_passing.gd`

**改动要点**：
- `Ball.State` 新增 `KICKED`
- `BallStateKicked`：
  - 水平方向：匀速/微摩擦（比 FREEFORM 摩擦小很多）
  - 空中：重力抛物线
  - 有 `lock_duration`（传球方短时间不能接回）
  - 有明确的 `pass_target` 位置记录
  - 捕获检测：对方球员可拦截，己方球员在锁定后可接
- `PlayerStatePassing` 触发球时从 FREEFORM 改为 KICKED
- 所有传球相关的逻辑要迁移到 KICKED 状态

**依赖**：M1-04（属性，用于传球力度计算）
**工作量**：中（2 天）
**验证方式**：传球后球走 KICKED 状态，锁定时间内己方球员不会自动接球

---

##### M1-06：带球步点系统（替换 cos 振荡）

**文件**：
- 修改：`scenes/ball/ball_states/ball_state_carried.gd`、`player.gd`

**改动要点**：
- `BallStateCarried` 重写：
  - `touch_timer` + `touch_interval`（由球员 `technique` 决定）
  - 每 `touch_interval` 秒触球一次，触球后球自由滚动
  - 触球距离 = f(速度)：越快球离脚越远
  - 新增 `is_ball_free` 标志位（断球窗口）
- `ball.gd` 暴露 `is_ball_free` 公共属性
- 移除现有 `cos(time * 10) * 3` 的振荡方式
- 参数初调：技术 50 → 间隔 0.25s；技术 90 → 间隔 0.15s

**依赖**：M1-04（属性）
**工作量**：中（2 天）
**验证方式**：带球时能看到球有节奏地前后滚动；快跑球离脚远，慢跑离脚近

---

##### M1-07：球新增 SAVED / DEFLECTED / HELD_BY_GOALKEEPER 状态

**文件**：
- 新增：`ball_state_saved.gd`、`ball_state_deflected.gd`、`ball_state_held_by_gk.gd`
- 修改：`ball.gd`、`ball_state_factory.gd`、`player_state_diving.gd`、`ai_behavior_goalie.gd`

**改动要点**：
- `Ball.State` 新增 `SAVED`, `DEFLECTED`, `HELD_BY_GOALKEEPER`
- `BallStateSaved`：球速 ×0.3~0.5，方向由门将扑救方向决定，0.5s 后转 FREEFORM
- `BallStateDeflected`：碰撞反射，能量 ×0.5~0.7，0.3s 后转 FREEFORM
- `BallStateHeldByGK`：球完全跟随门将手部位置，静止，3 秒后自动开大脚
- 门将 `DIVING` 状态扑到球 → SAVED；SAVED 落地前门将再次接住 → HELD_BY_GK
- 球碰到球员身体（非主动触球）→ DEFLECTED（用 `player_detection_area` 的 body_entered 信号）

**依赖**：M1-05（KICKED 状态，先有状态架构再加新状态）
**工作量**：中（2 天）
**验证方式**：射门被门将扑出有减速效果；球打到后卫身上会反弹

---

##### M1-08：球落地预测 API

**文件**：`ball.gd`（+ 各 ball state）

**改动要点**：
```gdscript
func predict_landing_position() -> Vector2:
    # 解 h + hv*t - 0.5*g*t² = 0 求落地时间
    # 水平匀速 → 落点 = 当前位置 + velocity * t_land
    ...

func predict_position_at_time(t: float) -> Vector2:
    # 预测 t 秒后的位置
    ...
```
- 地面球（height=0）直接返回当前位置
- 上升中的球也要能算（从最高点下落的时间）
- KICKED 和 FREEFORM 状态下都可用
- 后面 AI 和 UI 球路预测都会用这个

**依赖**：M1-05
**工作量**：小（0.5 天）
**验证方式**：打印预测位置和实际落点对比，误差 < 5px

---

#### 操作与断球层

##### M1-09：辅助瞄准（磁性传球）— 三种传球

**文件**：
- 修改：`ball.gd`、`player_state_passing.gd`
- 新增：`player_state_long_passing.gd`、`player_state_through_passing.gd`

**改动要点**：
- `ball.gd` 新增 3 个辅助瞄准方法：
  - `assisted_short_pass(direction, country) → Vector2`
  - `assisted_long_pass(direction, power, country) → Vector2`
  - `assisted_through_pass(direction, power, country) → Vector2`
- 短传：40° 锥角内找最近队友，吸附到脚下
- 长传：60° 锥角内找远端空位队友，高空球
- 直塞：30° 窄角，找队友前方的空档位置（送到跑动路线上）
- 吸附强度：与球员 `technique` 正相关
- 三个传球状态各调用对应的辅助瞄准方法

**依赖**：M1-03（操作映射）、M1-05（KICKED 状态）
**工作量**：中（2 天）
**验证方式**：方向大致对准队友就会传过去；三种传球轨迹有明显区别

---

##### M1-10：自动断球与过人机制 InterceptResolver

**文件**：
- 新增：`utils/intercept_resolver.gd`
- 修改：`ball_state_carried.gd`、`player.gd`、`ai_behavior_field.gd`

**改动要点**：
- `InterceptResolver.check_auto_intercept(defender, attacker, ball) → {success, reason}`
- 判定条件：球在步点自由窗口 + 防守者在球的路径上 + 距离 < 阈值 + 角度 < 35°
- 防守属性加成：高防守 → 断球半径更大
- 在 `BallStateCarried._physics_process` 中每帧检测附近的对方球员
- 断球成功：球 → FREEFORM，防守方获得球权，进攻方短暂硬直
- 过人判定 = 反向验证：带球变向 → 角度因子不通过 → 断球失败

**依赖**：M1-06（带球步点）、M1-04（属性）
**工作量**：大（3 天）
**验证方式**：
1. 直直冲向防守者 → 球被断
2. 在最后一刻变向 → 成功过人
3. 防守属性高的球员更难被过
**备注**：这是手感核心，需要大量调参时间

---

##### M1-11：控球权自动切换 PossessionManager

**文件**：
- 新增：`utils/possession_manager.gd`（或挂在 ActorsContainer 上）
- 修改：`actors_container.gd`、`player.gd`

**改动要点**：
- 监听 `GameEvents.ball_possessed`：己方球员得球 → 切到该球员
- 防守时默认控制离球最近的己方球员（每 200ms 重新评估）
- 手动切换（空档键）：切到下一个最近的队友
- 切换时：旧玩家 → CPU 模式，新球员 → P1/P2 模式
- 方向输入延续：因为移动输入是每帧读的，切换时自动延续
- `PossessionManager.player_control_changed` 信号 → HUD 更新控球箭头

**依赖**：M1-03（操作映射）
**工作量**：中（2 天）
**验证方式**：传球后控制权自动切到接球者；防守时按空档键切换球员

---

#### 阵容与 AI 层

##### M1-12：11 人制阵容扩展

**文件**：
- 修改：`assets/json/squads.json`（每队 6 → 11 人）
- 修改：`actors_container.gd`、`world_screen.tscn`（Spawns 节点增加 5 个 marker）
- 修改：`player.gd`（`Role` 枚举扩展）

**改动要点**：
- `squads.json` 每队从 6 人增加到 11 人（1 GK + 10 场上）
- 位置角色细化：`GOALKEEPER, RIGHT_BACK, LEFT_BACK, CENTER_BACK, CENTER_BACK_2, RIGHT_MID, LEFT_MID, CENTER_MID, CENTER_MID_2, STRIKER, STRIKER_2`
- 场景中 Spawns 节点增加 5 个 Marker2D（总共 11 个）
- KickOffs 节点也对应增加
- `ActorsContainer.spawn_players()` 循环 11 次
- 性能测试：22 人同屏帧率

**依赖**：M1-01（视窗扩大，需要更大球场空间）、M1-04（属性扩展）
**工作量**：中（2 天）
**验证方式**：比赛开始时 11 vs 11 球员全部在场，位置正确

---

##### M1-13：玩家方无球跑位 AI

**文件**：
- 修改：`scenes/characters/ai/ai_behavior_field.gd`

**改动要点**：
- 新增 `OffBallRunState` 枚举：`HOLD_POSITION, BREAK_OFFSIDE, PULL_WIDE, DROP_DEEP, OVERLAP_RUN, SECOND_BALL`
- 状态切换有冷却（0.8s），防止抖动
- 己方持球时触发跑位决策：
  - 前锋在防线附近 → 反越位前插
  - 中路拥挤 → 拉边
  - 离持球人远 → 回撤接应
  - 边后卫 + 边前卫内切 → 套边
- 跑位目标位置叠加在归位点之上
- 与传球辅助联动：跑位中的球员会成为直塞/长传的目标

**依赖**：M1-12（11 人制）
**工作量**：大（3 天）
**验证方式**：玩家带球时，队友会主动跑位创造传球选项；直塞能传到队友跑动前方

---

##### M1-14：CPU 持球 AI 决策树

**文件**：`ai_behavior_field.gd`

**改动要点**：
- 重写持球决策逻辑（当前只有简单的 shoot/pass 概率）
- 决策优先级：射门 → 直塞 → 短传 → 带球 → 长传 → 护球
- 每个决策有条件判断：
  - 射门：在射程内 + 角度好 + 防守压力小
  - 直塞：有队友前插 + 路线通透
  - 短传：被紧逼 + 队友位置更好
  - 带球：前方有空当
- 决策权重受球员属性影响：前锋更愿意射门，中场更喜欢传球
- 每 3 帧决策一次（核心层频率）

**依赖**：M1-12（11 人制）、M1-08（落地预测，用于 AI 判断传球路线）
**工作量**：大（3 天）
**验证方式**：CPU 球队能打出有章法的进攻，不是只会瞎带

---

##### M1-15：门将 AI 基础（出击 + 持球开球）

**文件**：
- 修改：`ai_behavior_goalie.gd`
- 新增：`player_state_goalie_holding.gd`（或复用现有逻辑）

**改动要点**：
- 出击：对方单刀时主动出击缩小角度
  - 判断条件：距离 < 阈值 + 是一对一 + 门将出击属性
  - 出击状态：加速冲向球，碰到球就解围
- 持球：门将接住球后 → HELD_BY_GK 状态
  - 选择开球方式：手抛球给近处队友 / 开大脚给远端
  - 决策时间：1-2 秒内决定
- 扑救方向预判：用 `scoring_raycast` + 球速判断扑救方向

**依赖**：M1-07（HELD_BY_GK 状态）
**工作量**：中（2 天）
**验证方式**：单刀时门将会出击；接住球后会手抛球或开大脚

---

#### 规则与 UI 层

##### M1-16：越位判定系统 OffsideJudge

**文件**：
- 新增：`utils/offside_judge.gd`
- 修改：`ball.gd`、`game_manager.gd`、`actors_container.gd`

**改动要点**：
- `OffsideJudge.check_offside_at_pass(passer, pass_direction) → {is_offside, offender, position}`
- 判定逻辑：
  - 找倒数第二名防守球员（含门将）→ 越位线
  - 检查对方半场内的己方球员是否越过越位线
  - 仅当越位球员"主动参与比赛"（接到球或干扰防守）才吹罚
- 在传球触球帧（KICKED 状态开始时）进行判定
- 越位后：吹哨 → 死球 → 对方间接任意球（SET_PIECE 简化版）
- 角球、门球、界外球不判越位（M2 出界系统出来后再完善）

**依赖**：M1-05（KICKED 状态，传球瞬间判定）
**工作量**：中（2 天）
**验证方式**：
1. 传球时前锋越位 → 哨响 + 球权转换
2. 回传/横传不越位
3. 角球不越位

---

##### M1-17：雷达小地图 RadarMinimap

**文件**：
- 新增：`ui/radar_minimap.gd`（自定义 Control）
- 修改：`ui.tscn`（HUD 中加入雷达）、`world_screen.gd`

**改动要点**：
- 80×50 px 大小，位于屏幕左下角
- 每 3 帧重绘一次（不用 60fps）
- 绘制内容：球场轮廓、中线、己方球员（亮色）、对方球员（暗色）、球（白色）、当前控制球员（高亮环）
- 坐标映射：球场坐标 → 雷达坐标（等比缩放）
- 从 `ActorsContainer` 读取球员和球的位置
- 可通过设置开关

**依赖**：M1-01（视窗扩大，左下角有空间放雷达）
**工作量**：小（1 天）
**验证方式**：雷达上所有球员位置与场上实际位置对应

---

##### M1-18：上下半场制 + HUD 完善

**文件**：
- 修改：`game_manager.gd`（拆分 IN_PLAY 为 FIRST_HALF + SECOND_HALF）
- 新增：`game_state_first_half.gd`、`game_state_second_half.gd`（或在一个状态里加 phase 变量）
- 修改：`ui.gd` / `ui.tscn`（HUD 元素调整）

**改动要点**：
- `GameManager.State` 从 `IN_PLAY` 拆为 `FIRST_HALF` 和 `SECOND_HALF`
- 半场 1 分钟（默认 2 分钟全场）
- 上半场结束 → 短暂停顿 → 双方交换场地 → 下半场开始
- 交换场地：`Actors_container.swap_sides()` —— 所有球员 x 坐标镜像
- HUD 增加：
  - 阶段显示（"上半"/"下半"）
  - 比分板移到顶部（带国旗）
  - 当前控制球员头顶箭头（用现有 ControlSprite 改进）
- 时间格式：`mm:ss`（现有 `TimeHelper` 可复用）

**依赖**：M1-12（11 人制，交换场地要动所有球员）
**工作量**：中（2 天）
**验证方式**：上半场结束 → 交换场地 → 下半场继续

---

### M1 实施顺序（依赖图）

```
第 1 天：M1-01 视窗 + M1-02 InputBuffer + M1-04 属性扩展
         （三个独立任务，可并行）

第 2-3 天：M1-03 操作映射（依赖 M1-02）
           M1-05 KICKED 状态（依赖 M1-04）
           M1-08 落地预测（依赖 M1-05）

第 3-4 天：M1-06 带球步点（依赖 M1-04）
           M1-07 球新状态（SAVED/DEFLECTED/HELD_BY_GK）（依赖 M1-05）

第 5-6 天：M1-09 三种传球 + 辅助瞄准（依赖 M1-03 + M1-05）
           M1-11 控球权切换（依赖 M1-03）

第 7-9 天：M1-10 断球与过人（依赖 M1-06 + M1-04）
           （这是手感核心，多留点时间调参）

第 8-9 天：M1-12 11 人制阵容（依赖 M1-01）
           M1-16 越位判定（依赖 M1-05）

第 10-12 天：M1-13 无球跑位 AI（依赖 M1-12）
             M1-14 CPU 持球 AI（依赖 M1-12 + M1-08）
             M1-15 门将 AI（依赖 M1-07）

第 13 天：M1-17 雷达小地图（依赖 M1-01）
          M1-18 上下半场 + HUD（依赖 M1-12）

第 14-15 天：整体联调 + bug 修复 + 手感调参
```

**总工期估计**：15-20 天

---

## M2：玩法深度（P1 全部 + 部分 P2）

**目标**：动作有变体、对抗有博弈、球员有差异、UI 更完整

**验收标准**：
- 射门/长传/直塞都有蓄力，力量可控
- 起手动作可以取消
- 头球、护球动作可用
- 出界规则完整（界外球/角球/门球）
- 有阵型选择，赛前可调整
- 赛后有数据统计和 MVP
- 难度选择生效

### M2 任务列表

##### M2-01：力度蓄力系统（三动作蓄力）

**文件**：
- 修改：`player.gd`（charge 变量提升到 Player 层）、`player_state_prepping_shot.gd`
- 新增：`player_state_prepping_long_pass.gd`、`player_state_prepping_through_pass.gd`
- 修改：HUD（蓄力条显示）

**改动要点**：
- 三种蓄力动作：射门 / 长传 / 直塞
- 蓄力时间上限 1.5s，ease 曲线
- 蓄力过满（>0.9）精度下降 15%
- HUD 蓄力条：球员脚下显示环形或条形力量指示
- 蓄力变量放在 `Player` 层（`charge_display`）供 HUD 读取

**依赖**：M1-03（操作映射）、M1-09（三种传球）
**工作量**：中（2 天）

---

##### M2-02：可取消窗口

**文件**：各触球状态（`player_state_shooting.gd`、`player_state_passing.gd`、长传/直塞状态）

**改动要点**：
- 起手帧内（前 6-8 帧）可被其他动作取消
- 射门 → 可取消为短传/长传/直塞
- 长传 → 可取消为短传/射门
- 短传 → 可取消为射门/长传
- 铲球不可取消
- 取消检查用 `InputBuffer.consume_any()`
- 取消窗口很短（~100ms），需要快速反应

**依赖**：M1-02（输入缓冲）、M2-01（蓄力）
**工作量**：中（2 天）
**验证方式**：按射门后立刻按短传，会改为传球而不是射门

---

##### M2-03：出界与球权转换系统

**文件**：
- 新增：`utils/ball_boundary_handler.gd`（或挂在 WorldScreen）
- 新增：`ball_state_out_of_play.gd`、`ball_state_set_piece.gd`
- 修改：`ball.gd`、`world_screen.gd`

**改动要点**：
- `OUT_OF_PLAY` 状态：球出界后冻结
- `SET_PIECE` 状态：定位球（子类型：KICKOFF/THROW_IN/CORNER/GOAL_KICK/FREE_KICK）
- `BallBoundaryHandler`：
  - 监听球与边界碰撞
  - 记录最后触球方
  - 判断出界类型（边线球/角球/门球）
  - 球摆到发球点 → SET_PIECE → 等待开球
- 边线球：出界点附近由对方掷（简化为踢）
- 角球：角球点开球
- 门球：门将在小禁区内开球

**依赖**：M1-05（KICKED 状态）
**工作量**：中（2 天）

---

##### M2-04：ContactFrameData 触球帧数据规范化

**文件**：
- 新增：`resources/contact_frame_data.gd`（Resource 类）
- 重构：所有触球类状态（SHOOTING, PASSING, LONG_PASSING, THROUGH_PASSING, HEADER, TACKLING 等）

**改动要点**：
- `ContactFrameData` 统一字段：`startup_frames`, `hit_frame`, `recovery_frames`, `contact_radius`, `launch_velocity_mult`, `is_cancelable`
- 每个触球状态持有一个 `ContactFrameData` 实例
- 状态的帧推进逻辑统一：`startup → active (hit_frame) → recovery`
- 取消窗口 = startup 阶段
- 判定帧 = hit_frame 那一帧做距离检测 + 释放球
- 回收阶段 → 之后转入 RECOVERING 或 MOVING
- 逐步把现有状态的硬编码帧数迁移到数据驱动

**依赖**：M2-02（可取消窗口，已验证 startup 概念）
**工作量**：大（3 天）
**备注**：这是架构性重构，做完后加新动作/调参数会方便很多

---

##### M2-05：多因子动作选择 ActionSelector

**文件**：
- 新增：`utils/action_selector.gd`
- 修改：`player_state_shooting.gd`、`player_state_passing.gd`

**改动要点**：
- 射门变体：正脚背 / 外脚背 / 匆忙射门 / 脚尖捅射 / 推射
- 评估维度：身体朝向 vs 球门、防守压力、来球速度、平衡状态、球员能力
- 每个变体有不同的 `ContactFrameData` 参数
- 球员个人参数叠加：`hit_frame_offset`, `power_mult` 等
- 先只做射门的多因子选择，传球后面再补

**依赖**：M2-04（ContactFrameData）
**工作量**：大（3 天）

---

##### M2-06：护球动作 PROTECTING_BALL

**文件**：
- 新增：`player_state_protecting_ball.gd`
- 修改：`player.gd`、`intercept_resolver.gd`

**改动要点**：
- 触发：持球时按住 L1（特殊动作键）+ 方向
- 效果：
  - 移动速度 × 0.4（很慢）
  - 自动断球难度 × 2（球在身体另一侧）
  - 铲球成功率 × 0.5
  - 球始终保持在远离防守者的一侧
- 松开 L1 → 回到 DRIBBLING
- 背身过人：护球时 180° 转身，球从身体一侧换到另一侧

**依赖**：M1-10（断球机制，护球的价值建立在断球之上）
**工作量**：中（2 天）

---

##### M2-07：头球动作完善

**文件**：`player_state_header.gd`（现有，需增强）

**改动要点**：
- 当前已有 HEADER 状态，完善判定和手感
- 头球触发：球在空中 + 球员在球落点附近 + 按射门/传球键
- 头球攻门 vs 头球摆渡：按射门键攻门，按短传键摆渡给队友
- 争顶判定：两人同时跳 → `jump` 属性高的争到
- 头球威力 < 射门威力（×0.7）
- 身高影响：个子高的球员争顶有优势

**依赖**：M1-08（落地预测，AI 用它跑位争顶）
**工作量**：中（2 天）

---

##### M2-08：AI 分级 LOD

**文件**：
- 修改：`ai_behavior.gd`（基类）、`ai_behavior_field.gd`、`actors_container.gd`

**改动要点**：
- 三级更新频率：核心层（每 3 帧）、中间层（每 15 帧）、远端层（每 60 帧）
- LOD 级别由 `ActorsContainer` 每 200ms 重新分配
  - 离球最近的 2-3 人 → 核心层
  - 距离中等的 6-8 人 → 中间层
  - 其他人 → 远端层
- 核心层：完整决策 + 每帧移动
- 中间层：归位点移动 + 盯人调整
- 远端层：只向归位点缓慢移动 + 偶尔小幅晃动
- 现有 `weight_on_duty_steering` 改造为 LOD 级别分配

**依赖**：M1-12（11 人制，人才够多需要分级）
**工作量**：中（2 天）
**验证方式**：22 人 AI 不掉帧；远端球员站位合理

---

##### M2-09：AI 难度等级

**文件**：
- 新增：`resources/difficulty_settings.gd`、`utils/game_settings.gd`
- 修改：`ai_behavior_field.gd`、`ai_behavior_goalie.gd`

**改动要点**：
- 难度三档：简单 / 普通 / 困难
- 影响参数：
  - 射门精度倍率（0.7 / 1.0 / 1.2）
  - 传球精度倍率（0.75 / 1.0 / 1.15）
  - 反应延迟（0.2s / 0.08s / 0.02s）
  - 防守紧逼度（0.6 / 1.0 / 1.3）
  - 失误率（25% / 8% / 2%）
- 难度存储在 `GameSettings.difficulty`
- 所有 AI 决策读取难度参数

**依赖**：M1-14（CPU 持球 AI，先有 AI 再调难度）
**工作量**：小（1 天）

---

##### M2-10：阵型系统 + 归位点

**文件**：
- 新增：`resources/formation_resource.gd`、`assets/json/formations.json`
- 新增：`ai/formation_manager.gd`
- 修改：`ai_behavior_field.gd`、`data_loader.gd`

**改动要点**：
- 4 种预设阵型：4-4-2 / 4-3-3 / 3-5-2 / 5-3-2
- `FormationResource`：11 个归位点坐标 + 角色分配
- `FormationManager`：
  - 根据球的位置整体平移阵型
  - 攻防阶段整体前压/后撤
  - 横向/纵向压缩
- 球员 AI 的 `home_position` 从 FormationManager 获取
- 阵型选择影响球队风格（4-3-3 偏进攻，5-3-2 偏防守）

**依赖**：M2-08（AI LOD，归位点系统需要和 AI 移动结合）
**工作量**：大（3 天）

---

##### M2-11：阵型选择界面

**文件**：
- 新增：`ui/formation_select_screen.gd` + `.tscn`
- 修改：`screen_factory.gd`、`soccer_game.gd`

**改动要点**：
- 球队选择后进入阵型选择（可选，或按某个键进入）
- 显示 4 种阵型图标
- 阵型示意图：小球场 + 11 个球员位置点
- 球队能力雷达图：速度/力量/技术/防守/进攻五维
- 确认后进入比赛

**依赖**：M2-10（阵型系统）
**工作量**：中（2 天）

---

##### M2-12：赛后结算画面 + MVP

**文件**：
- 新增：`ui/result_overlay.gd`（覆盖在 WorldScreen 上）
- 修改：`world_screen.gd`、`game_manager.gd`

**改动要点**：
- 终场后显示结算界面
- 内容：
  - 大字比分（"X - Y"）
  - 胜方名称 + 国旗
  - 比赛统计：控球率、射门数、角球数
  - MVP：评分最高的球员（名字 + 号码 + 数据）
- 按钮：重赛 / 选队重赛 / 返回主菜单
- MVP 评分算法：进球 +2 分，助攻 +1，抢断 +0.5，扑救 +0.3，失误 -0.5

**依赖**：M1-18（上下半场制，有完整比赛数据）
**工作量**：中（2 天）

---

##### M2-13：设置系统 GameSettings + 设置界面

**文件**：
- 新增：`utils/game_settings.gd`（Autoload）
- 新增：`ui/settings_screen.gd` + `.tscn`
- 修改：各系统读取设置值

**改动要点**：
- 设置项：
  - 比赛时长（1/2/3/5 分钟）
  - 难度（简单/普通/困难）
  - 传球辅助强度（低/中/高）
  - 球路预测（开/关）
  - 音效音量 / 音乐音量
- 使用 `ConfigFile` 持久化到用户目录
- 设置界面：分页或滚动列表
- 主菜单和暂停菜单都能进设置

**依赖**：M2-09（难度系统）
**工作量**：中（2 天）

---

##### M2-14：误差系统 PassAccuracy + SeededRandom

**文件**：
- 新增：`utils/pass_accuracy.gd`、`utils/seeded_random.gd`
- 修改：`ball.gd`（传球/射门时叠加误差）

**改动要点**：
- `PassAccuracy.calculate_pass_error()`：技术/距离/压力/跑动状态 → 误差半径
- `PassAccuracy.calculate_shot_deviation()`：射门精度/距离/压力/蓄力 → 偏差角度
- `PassAccuracy.calculate_first_touch_error()`：技术/来球速度 → 停球误差
- `SeededRandom`：每局一个种子，误差可复现
- 叠加时机：传球触球帧、射门触球帧、停球瞬间
- 误差是矢量偏移（传球）或角度偏转（射门）

**依赖**：M1-09（辅助瞄准 + 传球）
**工作量**：中（2 天）

---

##### M2-15：UI 提示完善（传球目标高亮 + 控球指示 + 体力条）

**文件**：修改 `ui.gd` / `ui.tscn` / `world_screen.gd`

**改动要点**：
- 传球目标高亮：
  - 蓄力/瞄准时，目标队友脚下有环形高亮
  - 短传 = 脚下圆圈
  - 直塞 = 前方跑动路线上的标记
- 控球指示优化：
  - 当前控制球员头顶箭头更明显（带颜色区分 P1/P2）
  - 切换时短暂闪烁
- 蓄力条样式优化（环形更好看）

**依赖**：M2-01（蓄力系统）、M1-09（辅助瞄准）
**工作量**：小（1 天）

---

##### M2-16：出界与定位球的 SET_PIECE 完善

**文件**：`ball_state_set_piece.gd`、`game_manager.gd`

**改动要点**：
- 各种定位球的完整规则：
  - 开球：中圈，对方退出 9.15m，球向前踢
  - 角球：角球点，防守方退出 9.15m
  - 任意球：犯规地点，防守方排人墙
  - 门球：小禁区内，对方退出禁区
  - 界外球：出界地点，用脚踢（街机简化）
- SET_PIECE 状态管理：等待 → 助跑 → 踢出 → KICKED/SHOT
- 越位在定位球时的生效/不生效规则

**依赖**：M2-03（出界系统）
**工作量**：中（2 天）

---

### M2 实施顺序

```
第 1-2 天：M2-01 蓄力系统 + M2-02 取消窗口

第 3-5 天：M2-04 ContactFrameData 重构（架构性工作，先做）
          M2-05 多因子动作选择（紧接其后）

第 3-4 天：M2-03 出界系统（与上面并行）
          M2-16 定位球完善（紧接出界）

第 5-6 天：M2-06 护球动作
          M2-07 头球完善

第 6-7 天：M2-08 AI 分级 LOD
          M2-10 阵型 + 归位点（依赖 LOD）

第 8 天：  M2-09 难度等级
          M2-13 设置系统（依赖难度）

第 9-10 天：M2-11 阵型选择界面
            M2-12 结算画面 + MVP
            M2-15 UI 提示完善

第 11-12 天：M2-14 误差系统
             整体调优 + bug 修复
```

**总工期估计**：12-16 天

---

## M3：AI 升级（P2 全部）

**目标**：跑位聪明、防守合理、球队像整体

### M3 任务列表

| # | 任务 | 主要改动 | 工作量 | 依赖 |
|---|------|---------|--------|------|
| M3-01 | 加时赛（金球制） | `GameManager` 新增状态 | 小 | M1-18 |
| M3-02 | 防守 AI 完整重写（站位优先、危险度排序、协防补位、造越位） | `AIBehaviorField` 防守逻辑 | 大 | M2-08 |
| M3-03 | 身体对抗系统 | `PhysicalContestResolver` | 大 | M1-10 |
| M3-04 | 球队风格与战术系统（进攻/防守/控球/冲击） | 球队级 AI 参数 + `team_style` | 中 | M2-10 |
| M3-05 | 半场休息 + 换人系统 | `HalftimeScreen` + 换人逻辑 | 大 | M2-10 |
| M3-06 | 球员动作风格参数（shot_power_mult, dribble_freq 等） | `PlayerResource` 扩展 + 各状态使用 | 中 | M2-05 |
| M3-07 | 屏幕震动增强（多档位、衰减） | `camera.gd` | 小 | 已有基础 |
| M3-08 | 粒子特效（射门火花、铲球尘土、进球爆发） | 粒子预制体 + 触发逻辑 | 中 | 已有 spark 基础 |
| M3-09 | 球员状态指示（号码、接应示意、体力状态、越位线） | HUD 扩展 | 中 | M1-17 |
| M3-10 | 球路预测 UI 显示（落点标记） | HUD 辅助线 | 小 | M1-08 |
| M3-11 | 半场休息界面 | `HalftimeScreen` UI | 中 | M3-05 |
| M3-12 | 防守 AI 造越位陷阱 | 防线整体前压逻辑 | 中 | M3-02 |

**总工期估计**：10-14 天

---

## M4：完整度提升（P3 全部）

**目标**：细节打磨、沉浸感、可选功能

### M4 任务列表

| # | 任务 | 主要改动 | 工作量 | 依赖 |
|---|------|---------|--------|------|
| M4-01 | 点球大战 | 点球状态机 + UI | 大 | M2-01 |
| M4-02 | 弧线球（侧旋） | Ball 轨迹 + 球员参数 | 中 | M1-05 |
| M4-03 | 倒钩射门完善 | `BICYCLE_KICK` 状态调优 | 小 | M2-05 |
| M4-04 | 凌空射门完善 | `VOLLEY_KICK` 状态调优 | 小 | M2-05 |
| M4-05 | 假动作系统 | 假动作状态 + 方向组合输入 | 大 | M2-06 |
| M4-06 | 体力系统 | Player stamina + 速度/反应衰减 | 中 | M1-04 |
| M4-07 | 犯规和红黄牌（可选） | 犯规判定 + 红牌系统 | 大 | M1-16 |
| M4-08 | 按键映射设置 | 设置界面扩展 | 小 | M2-13 |
| M4-09 | 球队节奏参数系统 | `TeamRhythm` 类 + 传球速度/控球范围 | 中 | M3-04 |
| M4-10 | 更多音效（观众欢呼层次、不同射门音效） | SoundPlayer 扩展 + 音效资源 | 小 | 已有基础 |
| M4-11 | 更多音乐（进球庆祝曲、胜利/失败曲） | MusicPlayer 扩展 + 音乐资源 | 小 | 已有基础 |

**总工期估计**：8-12 天

---

## 全局架构性改动（贯穿所有阶段）

这些不是独立任务，而是每个阶段做新功能时都要遵守/维护的：

### 状态机一致性
- 所有新增状态遵循 `*State` + `*StateFactory` + `*StateData` 三件套模式
- 状态通过 `state_transition_requested` 信号切换，不直接调用
- 状态是 Node，通过 `add_child` 挂载，`queue_free` 销毁

### GameEvents 信号总线
- 跨系统通信走 `GameEvents`
- 需要时新增信号，保持信号列表集中管理
- 不直接引用深层节点路径

### 调色板换色
- 新球员/队伍用 shader 参数换色，不做新图
- 保持 palette 索引的一致性

### 输入抽象
- 玩家输入走 `KeyUtils`，不以硬编码 P1/P2 方式写
- 新增动作键在 `KeyUtils.Action` 枚举中注册

### 性能预算
- AI 分级 LOD 严格遵守（近端 3 帧、中端 15 帧、远端 60 帧）
- 粒子效果控制数量
- 雷达每 3 帧重绘

---

## 风险与注意事项

| 风险 | 影响 | 应对 |
|------|------|------|
| **手感调参时间不可控** | M1-10 断球系统可能需要反复调试 | 先做能运行的版本，留 2-3 天专门调参 |
| **11 人制性能问题** | 22 人 AI + 渲染可能掉帧 | AI LOD 是 M2 内容，但 M1 就应该做性能测试，有问题提前优化 |
| **美术资源不足** | 视窗扩大后球场、UI 可能需要重做 | 先用代码缩放对付，美术资源迭代优化 |
| **状态数量爆炸** | 球 9 态 + 球员 20 态，复杂度高 | 严格按状态机模式写，同类状态共用基类逻辑 |
| **squads.json 数据量大** | 每队 11 人 × 8 队 × 7 维属性，人工填容易错 | 写一个简单的校验脚本；初版用程序化生成（随机 + 上下限） |
| **越位判定的边界情况** | 各种 edge case（门将位置、同时多人越位） | 先实现主逻辑，边界情况逐步补测试 |

---

> **文档版本**：v1.0
> **日期**：2026-08-20
> **对应设计文档**：design-document.md
