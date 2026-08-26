# How-godo t-simu-height

在 Godot 4 的 2D 足球游戏中，要实现**高空传球、头球截击与挑射**，最优雅且主流的做法是：**“2D 刚体物理负责 XY 平面运动，自定义逻辑模拟 Z 轴高度与阴影分离”**。

这样既保留了引擎原生 `RigidBody2D` 的平面碰撞与阻尼，又不用把项目重构成复杂且难以维护的伪 3D 物理。

### 一、 核心逻辑架构

我们可以将足球节点拆解为 **逻辑碰撞体（Parent）** 与 **视觉渲染体（Children）**：

Plaintext

```
Ball (RigidBody2D)                  <-- 负责 XY 平面物理（碰撞、阻尼、移动）
 ├── Shadow (Sprite2D)              <-- 阴影：始终停留在 Ground (Z = 0)
 ├── BallSprite (Sprite2D)          <-- 实际球体：沿 Y 轴向上偏移，模拟 Z 轴高度
 └── ControlArea (Area2D)           <-- 脚下控制区（当 Z > 高度阈值时禁用）
```

- **XY 轴（平面坐标）**：由 `RigidBody2D` 原生物理控制。
- **Z 轴（虚拟高度）**：用代码维护一个 `var height: float = 0.0` 和 `var vertical_velocity: float = 0.0`。
- **视觉渲染**：每帧将 `BallSprite.position.y = -height`（向像素上方偏移即视觉上的“升空”），同时让 `Shadow` 保持在地面 `(0, 0)` 位置，并随 `height` 增大而微调缩放与透明度。

### 二、 Godot 4 GDScript 完整实现代码

将以下脚本挂载到足球的 `RigidBody2D` 节点上：

GDScript

```
class_name Football2D
extends RigidBody2D

# --- Z 轴虚拟物理参数 ---
@export var gravity_z: float = 800.0        # Z 轴重力加速度
@export var bounce_coeff: float = 0.6       # 触地弹力衰减系数 (0.0~1.0)
@export var head_touch_threshold: float = 20.0 # 允许头球/截击的虚拟高度阈值

# --- 当前 Z 轴状态 ---
var height_z: float = 0.0                   # 当前高度 (0 表示贴地)
var velocity_z: float = 0.0                 # Z 轴垂直速度

# --- 子节点引用 ---
@onready var ball_sprite: Sprite2D = $BallSprite
@onready var shadow_sprite: Sprite2D = $Shadow
@onready var control_area: Area2D = $ControlArea

func _physics_process(delta: float) -> void:
	_update_z_physics(delta)
	_update_visuals()

# 1. 计算虚拟 Z 轴物理 (重力、弹跳)
func _update_z_physics(delta: float) -> void:
	if height_z > 0.0 or velocity_z > 0.0:
		# 模拟重力
		velocity_z -= gravity_z * delta
		height_z += velocity_z * delta
		
		# 触地反弹检测 (Height <= 0)
		if height_z <= 0.0:
			height_z = 0.0
			# 如果反弹速度极小，直接置零（防止微小晃动）
			if abs(velocity_z) < 40.0:
				velocity_z = 0.0
			else:
				velocity_z = -velocity_z * bounce_coeff # 动能衰减反弹
				# 触地时给平面速度加一点额外阻尼 (模拟落地的地面摩擦)
				linear_velocity *= 0.85

# 2. 刷新视觉：球体 Y 轴偏移与阴影跟随
func _update_visuals() -> void:
	# 在 2D 视角下，高度表现为 Y 轴负方向 (向上) 的位移
	ball_sprite.position.y = -height_z
	
	# 阴影始终停留在真正的地面点 (0, 0)
	shadow_sprite.position = Vector2.ZERO
	
	# 高度越高，阴影越小且越淡 (营造高空视觉差)
	var shadow_factor = clamp(1.0 - (height_z / 300.0), 0.3, 1.0)
	shadow_sprite.scale = Vector2(shadow_factor, shadow_factor)
	shadow_sprite.modulate.a = shadow_factor * 0.7

# --- 外部接口：供球员传球 / 射门调用 ---

# 踢高空球/挑射/挑传
func apply_pass_or_shot(impulse_xy: Vector2, impulse_z: float) -> void:
	# 1. 施加 XY 平面刚体冲量
	apply_central_impulse(impulse_xy)
	# 2. 赋予 Z 轴初速度
	velocity_z = impulse_z

# 判断脚下带球判定是否有效 (如果在半空中，地面脚部无法控制)
func is_controllable_by_foot() -> bool:
	return height_z <= 12.0

# 判断是否可以进行头球/高空争顶
func is_header_eligible() -> bool:
	return height_z > head_touch_threshold and height_z < 60.0
```

### 三、 传球与争顶控制逻辑对接

在球员脚本中，配合上述足球系统即可轻松完成**接地传球、过顶长传与头球截击**：

GDScript

```
# 球员脚本中的传球/射门逻辑片段
func execute_kick(is_high_pass: bool):
	if not ball.is_controllable_by_foot():
		return # 球在空中，无法脚下踢球
		
	var kick_dir = transform.x # 假设 transform.x 为球员朝向
	
	if is_high_pass:
		# 过顶长传：XY 给适中冲量，Z 轴给较高初速度
		ball.apply_pass_or_shot(kick_dir * 250.0, 350.0)
	else:
		# 地滚传球：Z 轴初速度为 0，只有平面冲量
		ball.apply_pass_or_shot(kick_dir * 400.0, 0.0)

# 球员争顶 / 头球触球逻辑
func try_header():
	if ball.is_header_eligible() and global_position.distance_to(ball.global_position) < 20.0:
		# 触发头球：改变球的平面前进方向，同时赋予向下/向前的 Z 轴速度
		ball.linear_velocity = Vector2.ZERO
		ball.apply_pass_or_shot(transform.x * 300.0, 50.0) # 头球向下顶或平推
```

### 四、 关键细节与优化技巧

1. **碰撞掩码（Collision Layer/Mask）调整**：
   - 球在空中（如 `height_z > 20.0`）时，可以通过代码将足球的碰撞层屏蔽掉一部分（例如不与地面的球员脚部碰撞体做 `PhysicsServer2D` 的阻挡），避免空中球被地面球员的脚直接拦截。
2. **球网与球门梁判空**：
   - 球门横梁（Crossbar）的碰撞体可以单独设置。当 `height_z` 接近横梁高度（如 `35.0~45.0`）时才触发弹梁效果，否则低空球直接穿过横梁下方进入球网。
3. **视觉缩放微调（可选）**：
   - 除了 `ball_sprite.position.y` 向上偏移外，可以在高空时让 `ball_sprite.scale` 稍微放大 `1.1~1.25` 倍（模拟透视近大远小），会让抛物线的视觉感更加逼真。