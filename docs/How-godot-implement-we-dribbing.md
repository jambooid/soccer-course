# How-godot-implement-we-dribbing

在 Godot 4 中用 2D 复刻 PS1/PS2 时代 *实况足球*（WE/PES）的核心带球手感，最根本在于**放弃“球员黏球”的思路**，将其解耦为两个独立的物理刚体，并利用 **AnimationTree 驱动触球冲量（Impulse）与步伐锁死**。

具体落地实现可以拆解为以下四大模块：

### 一、 物理与节点架构（球员与足球解耦）

- **足球 (RigidBody2D)**：开启真实的刚体物理，设置适当的线性阻尼（Linear Damp 约 `1.2~1.5`，模拟草地摩擦），开启 `Continuous CD` 放置高速穿模。
- **球员 (CharacterBody2D)**：不使用强物理碰撞去挤压足球，避免出现乱弹或粘连。
- **触球点与检测区 (Node2D & Area2D)**：
  - 在球员节点下挂载一个 `TouchPoint` (Node2D)，放置在球员脚部前方。
  - 挂载一个 `BallDetectArea` (Area2D)，用于实时判断足球是否处于球员可控制的范围内（半径约 `0.5m~1.0m`）。

### 二、 动画状态机与 8 方向混合 (AnimationTree)

利用 Godot 的 `AnimationTree` 节点解决方向切换与手感权重：

1. **BlendSpace2D 节点**：
   - 在 `AnimationTree` 中创建 `Dribble`（带球）状态，选用 `AnimationNodeBlendSpace2D`。
   - 将 8 个方向的带球序列帧放置在坐标轴上。传入玩家的移动向量 `Input.get_vector()`，Godot 会自动处理平滑转向。
2. **Call Method 轨道（关键帧事件驱动）**：
   - **WE/PES 的核心手感来源于“触球点发生在脚接触球的那一帧”**。
   - 在 `AnimationPlayer` 的带球动画中（如左脚向前迈出/右脚向前迈出的关键帧），添加 **Call Method Track**，调用代码中的 `_on_foot_touch()` 函数。

### 三、 带球冲量逻辑（Dribble Impulse System）

当动画播放到触球关键帧，触发 `_on_foot_touch()` 函数时，根据当前按键状态计算给足球施加的 `Impulse`：

- **普通带球 (Normal Drive)**：
  - **触球频率**：中等（每步触球一次）。
  - **冲量大小**：稍大于球员当前跑动速度，推球距离控制在离脚 `0.5m ~ 1.0m`。
- **冲刺带球 (Sprint / R1 机制)**：
  - **触球频率**：降低（拉长动画间格或隔一步触球一次）。
  - **冲量大小**：大幅提升，将球向前踢出 `2.0m ~ 3.5m`。这会制造一段“球离脚空白期（Out of Control Zone）”，给予防守 AI 滑铲或断球的空间。
- **精准控制 (Precision / R2 机制)**：
  - **触球频率**：极高（锁定小步频）。
  - **冲量大小**：极小，将球的速度强行缩减至与球员运动同步，球离脚不超过 `0.3m`。

### 四、 动态控制偏差与惯性锁死（Weight & Error Math）

为了重现 WE/PES 中“球员属性与运动状态影响带球”的真实感，在给球施加 Impulse 时加入动态修正：

1. **步伐锁死 (Step Lock-in)**：

   - 玩家按下转向或急停时，不要立刻改变球员和球的物理速度。必须等待 `AnimationTree` 播放完当前步态的触球帧或脚着地帧，才响应大角度转向，从而产生“重量感”。

2. **属性与加速度偏角**：

   - 提取球员的 `dribble_accuracy`（带球精度，1-99）和当前 `velocity.length()`（当前跑动速度）。

   - **推球偏移角度**：当球员在最高速冲刺中突然做 90 度变向推球时，施加一个随机的角度扰动：

     $$\text{ErrorAngle} = (1.0 - \frac{\text{DribbleAccuracy}}{99}) \times \text{SpeedFactor} \times \text{MaxDeviation}$$

   - 属性较低或极速转弯的球员会因为这个偏角导致**带球失误/趟大**。

### 五、 GDScript 核心实现伪代码

GDScript

```
extends CharacterBody2D

@export var ball : RigidBody2D
@export var dribble_accuracy : float = 75.0 # 球员带球属性 1-99
@onready var anim_tree : AnimationTree = $AnimationTree
@onready var touch_point : Node2D = $TouchPoint

var is_sprinting : bool = false

func _physics_process(delta):
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	is_sprinting = Input.is_action_pressed("sprint")
	
	# 1. 移动球员与更新动画 BlendSpace2D
	if input_dir != Vector2.ZERO:
		velocity = input_dir * (250.0 if is_sprinting else 150.0)
		anim_tree.set("parameters/Dribble/blend_position", input_dir)
		touch_point.position = input_dir.normalized() * 12.0 # 触球点偏移至脚前
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 500.0 * delta)
	
	move_and_slide()

# 2. 该函数由 AnimationPlayer 里的 Call Method Track 在“脚触球关键帧”自动调用
func _on_animation_foot_touch_frame():
	# 检查球是否在控制范围内
	var dist_to_ball = global_position.distance_to(ball.global_position)
	if dist_to_ball > 25.0: # 超过触球距离，无法触球
		return
		
	apply_dribble_impulse()

func apply_dribble_impulse():
	var move_dir = velocity.normalized()
	if move_dir == Vector2.ZERO:
		return

	# 计算基础推球力度
	var impulse_force = 180.0 if is_sprinting else 100.0
	
	# 根据属性计算误差偏角 (带球精度越高，误差越小)
	var accuracy_ratio = dribble_accuracy / 99.0
	var error_range = (1.0 - accuracy_ratio) * 0.4 # 最大弧度偏差
	var random_angle = randf_range(-error_range, error_range)
	
	# 合成最终施加给足球的物理矢量
	var final_dir = move_dir.rotated(random_angle)
	
	# 将球的当前速度重置或直接施加冲量，使球往前滚
	ball.linear_velocity = Vector2.ZERO 
	ball.apply_central_impulse(final_dir * impulse_force)
```

通过这套“2D 刚体物理球 + Call Method 触球帧驱动 + 带球属性偏角修正”的方案，就可以在 Godot 2D 中低成本、高效率地重现 PS1/PS2 时代 WE/PES 那种强调节奏、重量感与操作上限的带球手感。