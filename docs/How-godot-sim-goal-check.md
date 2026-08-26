# How-godot-sim-goal-check

在 Godot 4 的 2D 足球游戏中，要实现“高空球砸中横梁/立柱弹开”**以及**“球射入网窝后被网布包裹减速（挂网）”的效果，同样可以延续之前“物理归 2D 平面，高度/形变归逻辑与视觉”的核心思想。

以下是实现横梁高低判定与 2D 网窝形变减速的具体方案：

### 一、 3D 立体球门在 2D 平面上的物理拆解

在 2D 俯视角/斜 45 度视角下，球门不是一个简单的矩形，而是包含**地面网区、立柱、横梁**三层逻辑：

Plaintext

```
       ┌─────────────────────────┐  <-- 1. 横梁 (Crossbar): 仅当 Height_Z ≈ 柱高 时碰撞
       │                         │
       │    2. 网窝内 (Net Zone) │  <-- 高度低于立柱且进入此区域 = 进球 + 网布阻尼减速
 ──────┴─────────────────────────┴────── <--- 门线 (Goal Line)
       [左立柱]            [右立柱]   <-- 3. 门柱 (Posts): 任何高度（非高空超界）均碰撞
```

### 二、 模块一：横梁与立柱的 Z 轴高低碰撞判定

#### 1. 节点搭建

在球门节点下创建以下碰撞节点：

- `CrossbarArea` (Area2D)：横梁判定区（放置在球门上沿）。
- `LeftPostArea` / `RightPostArea` (Area2D)：左右立柱判定区。

#### 2. 判定逻辑 (GDScript)

横梁并不是原生的 `StaticBody2D` 硬阻挡，而是利用 `Area2D` 进行**高度重叠校验**。当球进入 `CrossbarArea` 时，比对球的 `height_z`：

GDScript

```
# 挂载于 CrossbarArea (Area2D) 的脚本
extends Area2D

@export var crossbar_height_min: float = 30.0 # 横梁下沿高度
@export var crossbar_height_max: float = 45.0 # 横梁上沿高度

func _ready() -> void:
	body_entered.connect(_on_ball_entered)

func _on_ball_entered(body: Node2D) -> void:
	if body is Football2D:
		var ball := body as Football2D
		
		# 判断球的虚拟 Z 轴高度是否恰好撞击横梁
		if ball.height_z >= crossbar_height_min and ball.height_z <= crossbar_height_max:
			_trigger_crossbar_bounce(ball)

func _trigger_crossbar_bounce(ball: Football2D) -> void:
	# 1. Z 轴反弹 (砸中横梁向下/向上弹)
	ball.velocity_z = -ball.velocity_z * 0.5
	
	# 2. XY 平面反弹 (朝球场方向反弹)
	# 假设球门朝向为 Vector2.DOWN，反弹向量向上
	var bounce_dir = Vector2(randf_range(-0.3, 0.3), 1.0).normalized()
	ball.linear_velocity = bounce_dir * (ball.linear_velocity.length() * 0.7)
	
	# 3. 播放砸梁音效与镜头震动 (可选)
	# SoundManager.play_sfx("crossbar_hit")
```

> **逻辑说明**：
>
> - 如果 `ball.height_z < 30.0`（地滚球或低空球），球会直接穿过横梁下方进入网窝。
> - 如果 `ball.height_z > 45.0`（高飞球），球会从横梁上方飞出底线。
> - 只有在 `30.0 ~ 45.0` 之间才会触发砸梁反弹。

### 三、 模块二：足球挂网（网窝包裹减速与网布凹陷）

要实现 PES/FIFA 中**大力抽射入网后，球被网布迅速吸住减速并贴网下落**的逼真效果，需要配合 **网布阻尼 Area2D** 与 **网布 Sprite 变形/Shader**。

#### 1. 网窝物理减速 (Net Physical Dampen)

在球门框内部（门线后方）放置一个 `NetZone` (Area2D)。当球进入网窝区时，强行赋予极其高昂的物理阻尼，并拉低 Z 轴速度：

GDScript

```
# 挂载于 NetZone (Area2D) 的脚本
extends Area2D

@export var net_friction: float = 0.85 # 每帧速度衰减比例
@export var goal_side: String = "home" # 哪方球门

func _ready() -> void:
	body_part_process = true

func _physics_process(_delta: float) -> void:
	var overlapping_balls = get_overlapping_bodies()
	for body in overlapping_balls:
		if body is Football2D:
			var ball := body as Football2D
			
			# 1. 模拟网布口袋拦截：极大消耗 XY 平面速度
			ball.linear_velocity *= net_friction
			
			# 2. 模拟网布兜住球：阻止球继续向上飞，顺着网布滑落
			if ball.velocity_z > 0:
				ball.velocity_z *= 0.3 # 迅速打断升空势头
			
			# 3. 触发网窝形变（将球的相对位置传给网布渲染层）
			_deform_net_visual(ball.global_position, ball.linear_velocity.length())

func _deform_net_visual(ball_pos: Vector2, impact_force: float) -> void:
	# 触发网布 Sprite 凹陷效果（见下文视觉方案）
	var net_mesh := $NetMeshInstance2D
	net_mesh.apply_impact(to_local(ball_pos), impact_force)
```

#### 2. 2D 网布凹陷的视觉实现（二选一）

##### 方案 A：Shader 顶点偏移 / 局部拉伸（推荐，效果最自然）

利用 Godot 4 的 2D CanvasItem Shader，在网窝 Sprite 上根据球的相对坐标产生一个微小的**局部膨胀/扭曲波纹**：

OpenGL Shading Language

```
// 保存为 net_deform.gdshader 挂载在球网 Sprite2D 上
shader_type canvas_item;

uniform vec2 impact_point = vec2(0.5, 0.5); // 球撞击网布的 UV 坐标
uniform float impact_strength = 0.0;       // 凹陷强度

void fragment() {
    vec2 uv = UV;
    float dist = distance(uv, impact_point);
    
    // 在撞击点周围产生向外的拉伸形变
    if (dist < 0.25) {
        vec2 dir = normalize(uv - impact_point);
        float factor = (1.0 - dist / 0.25) * impact_strength;
        uv -= dir * factor * 0.05; // 坐标偏移产生凹陷视觉
    }
    
    COLOR = texture(TEXTURE, uv);
}
```

在 GDScript 中根据球撞网的力度动态更新 Shader 参数：

GDScript

```
func apply_impact(local_ball_pos: Vector2, force: float) -> void:
	# 将球的局部坐标转为 UV 坐标 (0.0 ~ 1.0)
	var net_size = $NetSprite.texture.get_size()
	var uv_pos = local_ball_pos / net_size + Vector2(0.5, 0.5)
	
	var mat := $NetSprite.material as ShaderMaterial
	mat.set_shader_parameter("impact_point", uv_pos)
	
	# 用 Tween 做出网布被撞凹再弹回的衰减效果
	var tween = create_tween()
	tween.tween_property(mat, "shader_parameter/impact_strength", clamp(force / 500.0, 0.2, 1.0), 0.05)
	tween.tween_property(mat, "shader_parameter/impact_strength", 0.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
```

##### 方案 B：Skeleton2D / Bone2D 骨骼网格拉伸（适合高精度像素风）

1. 在 Godot 中将球网 Sprite 转为 `MeshInstance2D` 并切分网格。
2. 在网窝后方绑 2~3 根 2D 骨骼（`Bone2D`）。
3. 足球撞网时，用代码将对应骨骼向后拉动一段距离，然后再通过 `Spring`（弹性系数）拉回原位，带动网格 Mesh 发生物理拉伸。

### 四、 完整效果总结

通过上述架构：

1. **高空过顶球**：`height_z` 较高，穿过 `CrossbarArea` 上方或直接飞过门线，不会触网。
2. **重炮轰门撞梁**：`height_z` 在 `30~45` 之间，触发 `CrossbarArea`，球在空中产生剧烈的反向矢量与落体速度，砸梁弹回场内。
3. **挂网进球**：球穿过横梁下方落入 `NetZone`，速度立刻被 `net_friction` 降至原本的 `10%~20%`，并在 `Shader` 的作用下看到球网向后鼓起，随后球贴着网滑落至草坪。