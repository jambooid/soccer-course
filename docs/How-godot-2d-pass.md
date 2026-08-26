# How-godot-2d-pass

在 PS1/PS2 时代的 WE/PES（如 *WE2000* 或 *WE6/7/8*）中，**传球系统**是其战术流转的核心。你观察得非常准确：**传球分为脚下传球（Pass to Feet）与直塞/空档传球（Through Ball），没有强制蓄力条，且深受球员属性、身体姿态、触球时机（一脚传球）的影响。**

要在 Godot 4 2D 中优雅地复刻这套系统，核心在于构建一个 **“目标点预测（Target Finder） + 动态误差修正（Stat Matrix） + 动作帧同步（Animation Sync）”** 的技术架构。

### 一、 核心架构：WE 传球的三阶段管道（Pass Pipeline）

WE 的传球并不是“按下按键瞬间球飞出去”，而是经历以下三个阶段：

Plaintext

```
[1. 玩家按下按键 (短传 / 直塞)]
       │
       ▼
[2. 寻找最佳接球目标点 (Target Finder)]
       ├── 普通短传 ──► 锁定队友脚下 (To Feet)
       └── 空档直塞 ──► 锁定前方跑动空档 (To Space)
       │
       ▼
[3. 属性与姿态计算 (Accuracy & Force Math)]
       ├── 根据 传球属性 (Passing Stat) 计算方向与力量误差
       └── 根据 身体朝向与球的相对位置 计算姿态惩罚 (如逆足/背身)
       │
       ▼
[4. 动作锁死与触球发射 (Animation Touch Launch)]
       ├── 常规传球 ──► 等待播放传球动画到“触球帧”才真正给球施加 Impulse
       └── 一脚传球 ──► 触球前预输入(Buffer) -> 自动匹配“脚后跟/拉球”等顺势动画
```

### 二、 核心技术模块落地实现

#### 1. 目标点检索：脚下传球 vs 空档直塞 (Target Finding Logic)

- **普通短传（Pass to Feet）**：
  - **逻辑**：寻找手柄摇杆输入方向弧度扇形内（如 $\pm 30^\circ$）最近的队友，将目标点设定为该队友的**当前坐标 (`target_partner.global_position`)**。
- **空档直塞（Through Ball）**：
  - **逻辑**：预测队友的**跑动趋势**与防守者的**拦截盲区**，目标点不是队友脚下，而是**队友跑动方向的前方空档 (`space_position`)**。

##### 空档目标点计算伪代码 (GDScript)：

GDScript

```
func get_through_pass_target(passer: Node2D, input_dir: Vector2) -> Vector2:
	var best_teammate = find_teammate_in_cone(passer, input_dir)
	if not best_teammate:
		return passer.global_position + input_dir * 150.0 # 没找到队友就向方向推空球

	# 1. 基础预测点：队友坐标 + 队友速度 * 预判时间 (例如 0.8秒后的位置)
	var teammate_velocity = best_teammate.velocity
	var lead_time = 0.8
	var predicted_space = best_teammate.global_position + (teammate_velocity * lead_time)
	
	# 如果队友正处于静止状态，直塞球自动给他前方 1.5 米的领跑空间
	if teammate_velocity.length() < 10.0:
		var forward_dir = (best_teammate.global_position - passer.global_position).normalized()
		predicted_space = best_teammate.global_position + forward_dir * 40.0
		
	return predicted_space
```

#### 2. 无蓄力条的力量与精度计算（Power & Accuracy Curve）

PS1/PS2 早期 WE 没有短传蓄力条，**力量是根据传球距离自动衰减计算的，而精度由属性和姿态决定**：

1. **自动力量（Auto Force）**：

   $$\text{BaseImpulse} = \text{DistanceToTarget} \times \text{ForceMultiplier}$$

   根据传球距离自动匹配出刚好的物理冲量，确保球恰好送到接球员脚下减速。

2. **精度与角度误差（Error Matrix）**：

   - **传球属性（Pass Accuracy）**：属性越低，随机角度偏移量（`error_angle`）越大。
   - **逆足与姿态惩罚**：如果球员朝向为右，却要向左后方传球（背身传球），偏移量翻倍，且力量减弱 30%。

GDScript

```
func calculate_pass_impulse(passer: Node2D, target_pos: Vector2, is_through_pass: bool) -> Vector2:
	var to_target = target_pos - passer.global_position
	var dist = to_target.length()
	var base_dir = to_target.normalized()
	
	# 1. 计算姿态惩罚 (身体朝向与传球方向的夹角)
	var body_forward = passer.transform.x # 假设 transform.x 为朝向
	var angle_diff = body_forward.angle_to(base_dir) # 0 到 PI
	var posture_penalty = remap(abs(angle_diff), 0, PI, 1.0, 2.5) # 背身传球惩罚达 2.5 倍
	
	# 2. 计算属性带来的偏角误差 (短传/直塞精度 1-99)
	var stat = passer.short_pass_accuracy if not is_through_pass else passer.through_pass_accuracy
	var accuracy_ratio = stat / 99.0
	var max_error_deg = (1.0 - accuracy_ratio) * 20.0 * posture_penalty # 最大误差角度
	
	# 施加随机偏角
	var final_dir = base_dir.rotated(deg_to_rad(randf_range(-max_error_deg, max_error_deg)))
	
	# 3. 自动匹配力量 (直塞球额外加 20% 力度，穿透防线)
	var force_speed = dist * (1.8 if not is_through_pass else 2.2)
	force_speed = clamp(force_speed, 120.0, 450.0) # 限制上下限
	
	return final_dir * force_speed
```

#### 3. 动作锁死与“一脚传球（One-Touch Pass）”的流畅衔接

这是 WE 手感最精妙的地方：**你按下传球键时，球不会立刻飞出，而是触发动作队列。**

##### (1) 指令缓冲（Input Buffer）与预判

在球滚动向球员的过程中，或者球员正在跑动未触球时，允许玩家**提前 0.3~0.5 秒按下传球键**。这个指令会被写入 `input_buffer`。

##### (2) 智能选择“一脚传球”动画（Smart Animation Selection）

当球即将接触脚部瞬间（`_on_ball_approaching`），检查是否存在传球预输入：

- **普通一脚传球**：传球目标在前方/侧面 $\rightarrow$ 播放 `one_touch_pass` 快速推射动画。
- **脚后跟传球（Heel Pass）**：
  - **条件**：传球目标在球员**正后方（与身体朝向夹角 $> 135^\circ$）**，且属于一脚不停球传球。
  - **逻辑**：不旋转球员身体，直接播放 `heel_pass`（脚后跟隐蔽磕球）动画！

Plaintext

```
[球向球员滚动] ──► 玩家提前按传球 ──► 写入 InputBuffer (预输入)
                                            │
[球到达脚下 0.1m] ◄─────────────────────────┘
       │
       ├── 目标在后方 + 有预输入？ ──► 播放 [脚后跟动画] + 直接给球反向 Impulse
       └── 目标在前方 + 无预输入？ ──► 播放 [停球调整动画] ──► 再播放 [常规传球动画]
```

##### (3) Call Method 轨道发射物理球

不论是脚后跟还是常规传球，**真正给 `Football2D` 施加 `linear_velocity` 的时刻，必须是 AnimationPlayer 里脚部接触球的那个帧（Call Method Track）**，这样动作与球的弹飞完全同步，绝无“离体飞球”的悬浮感。

### 三、 WE/PES 传球系统的 GDScript 综合实战

在球员 `CharacterBody2D` 脚本中串联以上逻辑：

GDScript

```
extends CharacterBody2D

@export var ball : RigidBody2D
@onready var anim_tree : AnimationTree = $AnimationTree

var buffered_pass_cmd = null # 传球指令缓冲 {"target_pos": Vector2, "is_through": bool}

func _input(event):
	# 1. 捕捉传球按键 (短传或直塞)
	if event.is_action_pressed("pass_short") or event.is_action_pressed("pass_through"):
		var is_through = event.is_action_pressed("pass_through")
		var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		
		# 计算传球目标点
		var target_pos = Vector2.ZERO
		if is_through:
			target_pos = get_through_pass_target(self, input_dir)
		else:
			target_pos = get_feet_pass_target(self, input_dir)
			
		# 写入预输入缓冲区
		buffered_pass_cmd = {
			"target_pos": target_pos,
			"is_through": is_through,
			"timestamp": Time.get_ticks_msec()
		}
		
		# 如果球已经在脚下，立刻启动传球流程；若球在空中/远处，等待球靠近
		if is_ball_in_control():
			start_pass_sequence()

# 2. 检查并启动传球动画流程
func start_pass_sequence():
	if not buffered_pass_cmd: return
	
	var target_pos = buffered_pass_cmd["target_pos"]
	var pass_dir = (target_pos - global_position).normalized()
	var angle_to_target = transform.x.angle_to(pass_dir)
	
	# 一脚传球判断：如果目标在正后方 (> 135度)，播放脚后跟动画
	if abs(angle_to_target) > deg_to_rad(135.0):
		anim_tree.get("parameters/playback").travel("Pass_Heel")
	else:
		# 正常传球：旋转方向，播放标准传球动画
		anim_tree.get("parameters/playback").travel("Pass_Standard")

# 3. 动画关键帧事件 (由 AnimationPlayer 的 Call Method 轨道在脚触球瞬间调用)
func _on_anim_event_kick_ball():
	if not buffered_pass_cmd: return
	
	# 计算最终物理矢量 (含属性与姿态偏角)
	var impulse = calculate_pass_impulse(
		self, 
		buffered_pass_cmd["target_pos"], 
		buffered_pass_cmd["is_through"]
	)
	
	# 解除带球关系，给足球施加 Impulse 冲量
	ball.current_owner = null
	ball.linear_velocity = Vector2.ZERO
	ball.apply_central_impulse(impulse)
	
	# 赋予接球队友短暂的“优先拿球权 (Priority Claim)”
	# 清空缓冲
	buffered_pass_cmd = null
```

### 四、 总结与体验提升调优

要达到 WE/PES 的操作上限，请注意以下三个调试细节：

1. **接球者的“接球硬直与智能跑位”**：当直塞球发出后，系统应自动将当前操作视角/控制权**切换到接球者**，并让接球者 AI 自动沿出球轨迹做 `move_toward()` 迎球，而不是站在原地傻等。
2. **防守 AI 的拦截（Interception）**：传球轨迹如果穿过了防守球员的 `Area2D`，防守 AI 根据其“防守意识（Defense）”和“反应（Response）”属性，有机会播放“伸脚拦截（Block）”动画将球中途断下。
3. **出球音效与卡帧震动**：在 `_on_anim_event_kick_ball()` 触球瞬间，叠加一个短促的脚部触球音效，以及 1~2 帧的微小屏幕顿挫（Hitstop），能瞬间提升传球的“打击感与重量感”。