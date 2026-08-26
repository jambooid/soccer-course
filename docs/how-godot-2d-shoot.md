# How-godot-2d-shoot

在 WE/PES（实况足球）中，射门之所以能带来极致的“力量感、不确定性与绝杀时的激动人心”**，是因为它的射门系统绝非简单的“按下射门键球飞向球门”，而是一个将**蓄力压制、身体姿态（Off-balance）、球星属性与碰撞物理高度融合的动态过程。

要在 Godot 4 2D 中复刻这种极其出色的射门手感，需要从“蓄力与力量弧度”、“姿态与属性偏角”、“足球物理弹道（压枪/高飞/弧线）”以及“辅助打击感”四大技术模块进行落地：

### 一、 核心逻辑架构：WE 射门的四阶段流水线

Plaintext

```
[1. 按下射门键 (Square/X)] ──► 开启蓄力时间 (Power Charge)
                                      │
[2. 松开按键 / 蓄力满] ───► 锁定物理蓄力值 & 计算输入偏角 (Direction Input)
                                      │
[3. 姿态与属性误差校验 (Stat & Posture Check)]
       ├── 校验 射门精度 (Shot Acc) & 射门力量 (Shot Power)
       ├── 校验 逆足 (Weak Foot) & 顺足 (Strong Foot)
       └── 校验 身体姿态 (跑动中 / 急停 / 迎球一脚抽射 / 背身)
                                      │
[4. 动作锁死与触球瞬间 (Animation Event & Ball Launch)]
       ├── 播放对应的射门动画 (大力抽射 / 压低推射 / 凌空抽射)
       └── 脚触球帧 ──► 结合 Z 轴高度与 XY 矢量，给 RigidBody2D 施加 Impulse
```

### 二、 核心技术模块实现

#### 1. 蓄力机制与“压枪 / 飞天”控制 (Power Bar & Vertical Pitch)

WE 射门最精彩的悬念在于：**力量过小会被扑，力量过大（过顶）球会飞向观众席（压不住枪）。**

##### 力量与 Z 轴高度（飞行弧度）的函数映射：

- **适度蓄力（`0.1 ~ 0.7`）**：球保持在低空或中空（`velocity_z` 适中），呈压低的大力抽射（Drive Shot）。
- **过度蓄力（`0.7 ~ 1.0`）**：`velocity_z` 剧增，球将以极陡的角度升空，直接高过横梁（高飞高尔夫球）。
- **方向控制**：在蓄力期间，玩家手柄摇杆的偏角（如左上、右上）决定球射向球门的**死角角度（Corner Targeting）**。

GDScript

```
# 计算射门的 XY 矢量与 Z 轴初速度 (伪代码)
func calculate_shot_vectors(passer: Node2D, charge_ratio: float, input_dir: Vector2) -> Dictionary:
	var goal_target = get_goal_target_point(input_dir) # 根据手柄方向选球门死角
	var shot_dir = (goal_target - global_position).normalized()
	
	# 1. XY 平面基础力量 (基于球员射门力量属性 Shot Power)
	var max_speed = remap(shot_power_stat, 1, 99, 300.0, 600.0)
	var xy_force = charge_ratio * max_speed
	
	# 2. Z 轴高度 (蓄力超过 0.75 后的指数级升空：飞天机制)
	var z_force = 0.0
	if charge_ratio <= 0.7:
		z_force = remap(charge_ratio, 0.0, 0.7, 30.0, 180.0) # 压低抽射 / 中空球
	else:
		z_force = remap(charge_ratio, 0.7, 1.0, 180.0, 500.0) # 蓄力过满，飞天高尔夫
		
	return {"xy_impulse": shot_dir * xy_force, "z_impulse": z_force}
```

#### 2. 姿态惩罚与离向偏差（Posture & Accuracy Matrix）

WE 中极具戏剧性的一幕是：**在身体失去平衡或迎着来球逆足射门时，球会离谱偏出。** 这是手感真切的核心。

##### 动态偏差角（Error Angle）计算公式：

我们将**球员射门精度属性（Shot Accuracy）**、身体朝向与射门方向的夹角（Angle Difference）**以及**来球相对速度（Ball Speed）合成一个随机偏角：

$$\text{ErrorAngle} = \left(1.0 - \frac{\text{ShotAccuracy}}{99}\right) \times \text{PostureFactor} \times \text{MaxErrorDeg}$$

GDScript

```
func apply_accuracy_error(base_dir: Vector2, is_one_touch: bool) -> Vector2:
	# 1. 计算身体朝向与目标方向的夹角 (背身/侧身射门惩罚)
	var angle_diff = transform.x.angle_to(base_dir) # 0 ~ PI
	var posture_factor = 1.0 + (abs(angle_diff) / PI) * 1.5 # 侧身最高加倍 2.5
	
	# 2. 一脚凌空抽射/迎球怒射 (One-Touch Shot) 难度提升
	if is_one_touch:
		posture_factor *= 1.3
		
	# 3. 计算最终随机误差角度 (精度越高，误差越小)
	var accuracy_ratio = shot_accuracy_stat / 99.0
	var max_err_deg = (1.0 - accuracy_ratio) * 18.0 * posture_factor # 最大可偏出 30+ 度
	
	var final_angle = deg_to_rad(randf_range(-max_err_deg, max_error_deg))
	return base_dir.rotated(final_angle)
```

#### 3. 搓射与香蕉球（R2 Curving / Spin Physics）

WE2000 / PES5/6 中最令人激动的射门之一就是 **R2 搓弧线球（Curling Shot / Finesse Shot）**。

在 2D 物理中，可以通过给 `Football2D` 增加一个 **马格努斯效应（Magnus Effect / Spin）** 来实现平滑的弧线：

GDScript

```
# 足球 RigidBody2D 脚本中的马格努斯弧线模拟
var spin_force: float = 0.0 # 旋转力 (正数右弧线，负数左弧线)

func _physics_process(delta: float) -> void:
	if abs(spin_force) > 0.1 and linear_velocity.length() > 50.0:
		# 马格努斯力垂直于当前的运动矢量
		var perp_dir = Vector2(-linear_velocity.y, linear_velocity.x).normalized()
		# 施加持续的侧向弯曲力
		apply_central_force(perp_dir * spin_force)
		# 旋转力随阻尼衰减
		spin_force = move_toward(spin_force, 0.0, delta * 150.0)

# 射门时调用：如果按下了 R2 搓射键，注入 spin_force
func execute_curling_shot(curve_stat: float, is_left_foot: bool):
	var curve_dir = -1.0 if is_left_foot else 1.0
	spin_force = curve_stat * 12.0 * curve_dir # 弧线属性越大，弯曲越剧烈
```

#### 4. “极度激动人心”的打击感与画面反馈（Juice & Hitstop）

射门手感好不好，一半取决于物理，一半取决于**视觉与音效爆发（Screen Juice）**：

1. **顿帧 / 卡帧 (Hitstop / Frame Freeze)**：
   - 在脚触球打出超级重炮（`charge_ratio > 0.8`）的那一瞬间，将全局 `Engine.time_scale` 设为 `0.05` 持续 `0.04 秒`（即卡顿 2-3 帧），随后恢复 `1.0`。这种短暂的停顿感会让玩家感觉“这脚球力量大到把空气都打爆了”。
2. **镜头瞬间拉近与微震 (Camera Shake & Zoom)**：
   - 射门瞬间，相机镜头瞬间切为 `Zoom In`（拉近 10%），并叠加一个沿射门反方向的 **2D 震屏（Screen Shake）**。
3. **触球爆音与球网拉扯**：
   - 播放极其沉重有力（如爆破声/重炮爆破音）的射门音效。结合我们之前讨论的“网窝形变 Shader”，球高速撞网后触发强烈凹陷，手感瞬间拉满。

### 三、 完整射门流程代码示范 (GDScript)

GDScript

```
extends CharacterBody2D

@export var ball: Football2D
@onready var anim_tree: AnimationTree = $AnimationTree

var is_charging_shot: bool = false
var shot_charge: float = 0.0
@export var charge_speed: float = 1.8 # 蓄力速度

func _process(delta: float) -> void:
	# 1. 蓄力逻辑 (按住射门键)
	if Input.is_action_pressed("shoot") and is_ball_in_control():
		is_charging_shot = true
		shot_charge = clamp(shot_charge + delta * charge_speed, 0.0, 1.0)
		UI_PowerBar.update_bar(shot_charge) # 刷新头顶/UI蓄力条
		
	# 2. 松开射门键，触发射门
	if Input.is_action_just_released("shoot") and is_charging_shot:
		is_charging_shot = false
		trigger_shot_sequence()

func trigger_shot_sequence():
	# 根据身体朝向与速度选择射门动画 (如：迎球抽射 / 压低推射)
	var anim_name = "Shot_Heavy" if shot_charge > 0.5 else "Shot_Light"
	anim_tree.get("parameters/playback").travel(anim_name)

# 3. 动画 Call Method Track 轨道在“脚触球帧”调用的核心逻辑
func _on_anim_event_kick_shot():
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var is_r2_curling = Input.is_action_pressed("finesse_modifier") # R2 搓射键
	
	# A. 计算计算基础目标方向与误差
	var target_goal_pos = get_goal_target_point(input_dir)
	var raw_dir = (target_goal_pos - global_position).normalized()
	var final_dir = apply_accuracy_error(raw_dir, false)
	
	# B. 计算 XY 与 Z 轴冲量
	var vectors = calculate_shot_vectors(self, shot_charge, final_dir)
	
	# C. 打击感爆发 (Hitstop 卡帧 + 震屏)
	if shot_charge > 0.6:
		HitstopManager.trigger_hitstop(0.04) # 停顿 0.04 秒
		Camera2D.trigger_shake(shot_charge * 15.0) # 震屏
		
	# D. 实体出球物理
	ball.current_owner = null
	ball.linear_velocity = Vector2.ZERO
	ball.apply_pass_or_shot(vectors["xy_impulse"], vectors["z_impulse"])
	
	# E. 如果按下了 R2，注入香蕉球旋转力
	if is_r2_curling:
		ball.spin_force = curve_stat * 15.0
		
	# 重置蓄力
	shot_charge = 0.0
	UI_PowerBar.hide_bar()
```

### 四、 总结与体验关键

WE/PES 射门的灵魂就是：**“有控制权的豪赌”**。

1. **蓄力条（Power Bar）是玩家的博弈**：压太低容易被守门员轻松扑救，压太满就会爆射飞天，只有在临界点（`0.6 ~ 0.75`）释放才能打出撕裂球网的挂死角重炮。
2. **状态（State）决定真实感**：跑动中发力抽射、逆足离心发力、迎球一脚凌空，通过不同的误差偏角与动画呈现，每一脚射门的效果都是独特且无法完全预测的。
3. **视觉与音效配合（Hitstop & Shake）**：用重磅音效和微小卡帧把 2D 物理碰撞的瞬间能量“放大”给玩家。