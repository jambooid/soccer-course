class_name DribblePhysics
extends RefCounted

enum Mode { JOG, SPRINT }

# ---- 已知问题：摩擦模型不一致 ----
# ⚠️ 带球状态（DRIBBLING）使用指数衰减摩擦 v(t) = v0 * f^t（本文件），
#    而自由状态（FREEFORM）使用线性衰减摩擦（move_toward + friction_ground）。
#    两者衰减曲线不同，会导致球从带球释放时出现"突兀的摩擦力变化"——
#    指数摩擦前期衰减快后期慢，线性摩擦匀速衰减。
#    建议在后续任务中统一为同一种摩擦模型（推荐统一为指数模型）。
#    本文件中的 stop_distance / predict_ball_position 等公式仅适用于带球状态。

# ---- 数学模型说明 ----
# 带球物理基于指数衰减摩擦模型：v(t) = v0 * f^t
# 停止距离（解析解）：S = v0 / -ln(f)
#   f=0.35, -ln(f)=1.050 → S ≈ v0 × 0.95
#   即球以初速 80px/s 滑行约 76px 停下
#
# 稳态带球触球频率估算：
#   每次触球将球速从 v_entry 提升到 v_high = lerp(v_entry, push_speed, eff)
#   球向前冲出触球区后减速回落，回到 zone_end 时 v_entry = v_high * f^T
#   触球频率 ≈ 1 / T（受 MIN_TOUCH_INTERVAL 下限限制）
#
# 关键指标（满速 80px/s，technique=98）：
#   - 触球频率：约 2.3 Hz（自然节奏，不受冷却限制）
#   - 球平均前距：约 32px（球员前方）
#   - 急停最远距离：约 95px（可控距离 78px 的 1.22 倍，会丢球但不多）
#   - 满速 90° 急转失控时间：约 0.62s
#   - 60% 速 90° 急转失控时间：约 1.16s（高技术球员有充裕反应时间）
#
# 参数设计原则：
#   - 低技术球员（technique=30-50）：触球频繁但推不远，控制范围小 → 细碎盘带
#   - 高技术球员（technique=80-98）：触球较少但推送有力，控制范围大 → 大步趟球
#   - 急停必丢球（技能 = 逐渐减速），但不会丢太远（可快速追回）

# ---- 常量（已校准） ----
const GROUND_FRICTION_PER_SEC := 0.35       # 每秒速度衰减系数（f=0.35 → 停止距离 ≈ v0 × 0.95）
const TOUCH_ZONE_LEN_MIN := 12.0            # 触球区最小长度（px，低技术）
const TOUCH_ZONE_LEN_MAX := 28.0            # 触球区最大长度（px，满技术）
const TOUCH_ZONE_WIDTH := 8.0               # 触球区宽度（px，两侧各一半）
const MIN_TOUCH_INTERVAL := 0.08            # 最小触球间隔（秒，防止帧频过高导致连触）
const PUSH_MULT_LOW_SPEED := 1.6            # 低速推球倍率（站定时把球拨出去）
const PUSH_MULT_HIGH_SPEED := 1.35          # 高速推球倍率（冲刺时顺势推）
const TOUCH_EFFICIENCY_MIN := 0.5           # 最低触球效率（lerp 权重，低技术）
const TOUCH_EFFICIENCY_MAX := 0.9           # 最高触球效率（lerp 权重，满技术）
const MAX_INACCURACY_RAD := 0.15            # 最大推球方向偏差（弧度，低技术时）
const MAX_CONTROL_DISTANCE_MIN := 50.0      # 最小可控距离（px，低技术）
const MAX_CONTROL_DISTANCE_MAX := 80.0      # 最大可控距离（px，满技术）
const IDLE_SPEED_THRESHOLD := 20.0          # 静止/慢速阈值（px/s）
const TOUCH_ZONE_FRONT_OFFSET := 6.0        # 触球区前端距球员身体的偏移（px）

# ---- 带球模式参数 ----
# 注：使用 int 键而非 Mode.JOG 因为 const 字典不接受枚举键作为常量表达式
const MODE_TOUCH_ZONE_MULT: Dictionary = {0: 1.0, 1: 1.3}   # JOG, SPRINT
const MODE_CONTROL_DIST_MULT: Dictionary = {0: 1.0, 1: 1.5}   # JOG, SPRINT
const MODE_MIN_INTERVAL_MULT: Dictionary = {0: 1.0, 1: 1.875}  # JOG, SPRINT (0.08s -> 0.15s)
const MODE_INACCURACY_MULT: Dictionary = {0: 1.0, 1: 1.5}   # JOG, SPRINT
const MODE_PUSH_OFFSET: Dictionary = {0: 0.0, 1: 0.2}        # JOG, SPRINT (推球倍率整体上移)
const MODE_EFFICIENCY_OFFSET: Dictionary = {0: 0.0, 1: -0.1}  # JOG, SPRINT (触球效率偏移)

# 速度惩罚：跑得越快，精度越低、效率越差
const SPEED_PENALTY_MAX_INACCURACY := 0.075   # 全速时额外方向偏差（rad）
const SPEED_PENALTY_EFFICIENCY_LOSS := 0.1    # 全速时效率损失

# 停球质量（First Touch）
const FIRST_TOUCH_ABSORPTION_MIN := 0.4      # 低技术吸收比例
const FIRST_TOUCH_ABSORPTION_MAX := 0.85     # 高技术吸收比例
const FIRST_TOUCH_DIR_ERROR_MAX_DEG := 45.0  # 低技术最大方向偏差（度）
const FIRST_TOUCH_DIR_ERROR_MIN_DEG := 5.0   # 高技术最小方向偏差（度）
const FIRST_TOUCH_MIN_SPEED := 15.0          # 停球后最小速度

# 真实 Player 属性范围（从 squads.json 统计）
const TECHNIQUE_MIN := 30.0                 # 最低 technique（门将）
const TECHNIQUE_MAX := 98.0                 # 最高 technique（顶级前锋/中场）

# 归一化 technique 到 0-1 范围（用于 lerp）
static func normalize_technique(technique: float) -> float:
	return clamp((technique - TECHNIQUE_MIN) / (TECHNIQUE_MAX - TECHNIQUE_MIN), 0.0, 1.0)

# 应用地面摩擦力（指数衰减）
static func apply_friction(velocity: Vector2, delta: float) -> Vector2:
	return velocity * pow(GROUND_FRICTION_PER_SEC, delta)

# 获取触球区长度（随 technique 增长）
# technique: Player.technique 属性值（30-98 范围）
static func get_touch_zone_length(technique: float, mode: int = Mode.JOG) -> float:
	var t_norm: float = normalize_technique(technique)
	var base: float = lerp(TOUCH_ZONE_LEN_MIN, TOUCH_ZONE_LEN_MAX, t_norm)
	return base * float(MODE_TOUCH_ZONE_MULT[mode])

# 获取最大可控距离（随 technique 增长）
# technique: Player.technique 属性值（30-98 范围）
static func get_max_control_distance(technique: float, mode: int = Mode.JOG) -> float:
	var t_norm: float = normalize_technique(technique)
	var base: float = lerp(MAX_CONTROL_DISTANCE_MIN, MAX_CONTROL_DISTANCE_MAX, t_norm)
	return base * float(MODE_CONTROL_DIST_MULT[mode])

# 获取最小触球间隔（随模式变化）
static func get_min_touch_interval(technique: float, mode: int = Mode.JOG) -> float:
	return MIN_TOUCH_INTERVAL * float(MODE_MIN_INTERVAL_MULT[mode])

# 检测球是否在触球区内
# 触球区为矩形（胶囊形近似），沿 player_dir 方向，前端在 player_pos 前方 TOUCH_ZONE_FRONT_OFFSET 处
static func is_ball_in_touch_zone(
	ball_pos: Vector2,
	player_pos: Vector2,
	player_dir: Vector2,
	technique: float,
	mode: int = Mode.JOG
) -> bool:
	if player_dir.length() < 0.001:
		return false
	var dir_norm := player_dir.normalized()

	# 将球位置转换到球员局部坐标系（dir_norm 为 +x 轴）
	var to_ball := ball_pos - player_pos
	var local_x := to_ball.dot(dir_norm)
	var perp := dir_norm.rotated(PI / 2.0)
	var local_y: float = abs(to_ball.dot(perp))

	var zone_length := get_touch_zone_length(technique, mode)
	var zone_start_x := TOUCH_ZONE_FRONT_OFFSET
	var zone_end_x := TOUCH_ZONE_FRONT_OFFSET + zone_length

	# x 方向：在触球区前后范围内
	if local_x < zone_start_x or local_x > zone_end_x:
		return false
	# y 方向：在宽度范围内
	return local_y <= TOUCH_ZONE_WIDTH / 2.0

# 计算触球后的球速（冲量 = lerp 向推球方向，保留部分惯性）
# technique: Player.technique 属性值（30-98 范围）
static func compute_touch_impulse(
	ball_velocity: Vector2,
	player_velocity: Vector2,
	player_max_speed: float,
	technique: float,
	mode: int = Mode.JOG
) -> Vector2:
	var player_speed := player_velocity.length()
	if player_speed < 1.0:
		return ball_velocity  # 球员不动则不触球

	var t_norm: float = normalize_technique(technique)
	var speed_factor: float = clamp(player_speed / player_max_speed, 0.0, 1.0)

	# 1. 推球方向 = 球员速度方向 + 随机偏移（技术越高越准）
	var push_direction: Vector2 = player_velocity.normalized()
	var base_inaccuracy: float = lerp(MAX_INACCURACY_RAD, 0.0, t_norm)
	var mode_inaccuracy_mult: float = float(MODE_INACCURACY_MULT[mode])
	# 速度惩罚：速度越快偏差越大
	var speed_penalty_inaccuracy: float = SPEED_PENALTY_MAX_INACCURACY * speed_factor
	var total_inaccuracy: float = base_inaccuracy * mode_inaccuracy_mult + speed_penalty_inaccuracy
	push_direction = push_direction.rotated(randf_range(-total_inaccuracy, total_inaccuracy))

	# 2. 推球目标速度 = 球员速度 × 倍率（速度越高倍率越低 + 模式偏移）
	var push_mult_base: float = lerp(PUSH_MULT_LOW_SPEED, PUSH_MULT_HIGH_SPEED, speed_factor)
	var push_multiplier: float = push_mult_base + float(MODE_PUSH_OFFSET[mode])
	var push_speed: float = player_speed * push_multiplier
	var push_velocity: Vector2 = push_direction * push_speed

	# 3. 触球效率（技术越高越接近目标速度；速度越快效率越低；模式有偏移）
	var base_efficiency: float = lerp(TOUCH_EFFICIENCY_MIN, TOUCH_EFFICIENCY_MAX, t_norm)
	var efficiency_with_mode: float = base_efficiency + float(MODE_EFFICIENCY_OFFSET[mode])
	var speed_efficiency_loss: float = speed_factor * SPEED_PENALTY_EFFICIENCY_LOSS
	var total_efficiency: float = clamp(efficiency_with_mode - speed_efficiency_loss, 0.2, 0.95)

	return ball_velocity.lerp(push_velocity, total_efficiency)

# 计算停球后的球速（First Touch Quality）
# 高技术球员停球稳（速度慢、方向准），低技术停球弹得远、方向偏
static func compute_first_touch_velocity(
	incoming_velocity: Vector2,
	control_direction: Vector2,
	technique: float
) -> Vector2:
	var t_norm: float = normalize_technique(technique)

	# 吸收比例：高技术吸收多（球慢）
	var absorption: float = lerp(FIRST_TOUCH_ABSORPTION_MIN, FIRST_TOUCH_ABSORPTION_MAX, t_norm)
	var remaining_speed: float = incoming_velocity.length() * (1.0 - absorption)
	remaining_speed = max(remaining_speed, FIRST_TOUCH_MIN_SPEED)

	# 方向偏差：高技术准
	var error_deg: float = lerp(FIRST_TOUCH_DIR_ERROR_MAX_DEG, FIRST_TOUCH_DIR_ERROR_MIN_DEG, t_norm)
	var error_rad: float = deg_to_rad(error_deg)
	var final_dir: Vector2 = control_direction.rotated(randf_range(-error_rad, error_rad))

	return final_dir * remaining_speed

# 计算球在指数摩擦下的停止距离（解析解）
# ⚠️ 仅适用于带球状态的指数摩擦模型（GROUND_FRICTION_PER_SEC）。
# 不适用于 FREEFORM 状态的线性摩擦。
static func compute_stop_distance(velocity: Vector2) -> float:
	var f := GROUND_FRICTION_PER_SEC
	if f >= 1.0 or f <= 0.0:
		return INF
	var speed := velocity.length()
	return speed / -log(f)

# 预测球在 time 秒后的位置（基于指数摩擦模型）
# ⚠️ 仅适用于带球状态的指数摩擦模型。
static func predict_ball_position(
	current_pos: Vector2,
	velocity: Vector2,
	time: float
) -> Vector2:
	if velocity.length() < 0.1:
		return current_pos
	var f := GROUND_FRICTION_PER_SEC
	if f >= 1.0 or f <= 0.0:
		return current_pos + velocity * time
	# 积分 ∫v(t)dt = v0 / -ln(f) * (1 - f^t)
	var direction := velocity.normalized()
	var v0 := velocity.length()
	var displacement := v0 / -log(f) * (1.0 - pow(f, time))
	return current_pos + direction * displacement

# 估算下一次触球的时间间隔（近似，用于调试和参数调优）
# 此函数给出稳态下触球频率的**理论估算**，实际触球间隔受 MIN_TOUCH_INTERVAL 限制
# 且不考虑球员变向、加速等动态因素。用于调试可视化，不用于游戏逻辑。
#
# ⚠️ 注意：该估算的前提是球员匀速前进且触球区中点在球员正前方。
# 在低速/高速变化、急停急转等情况下，实际触球间隔会偏离此估算。
# 现场测试表明，估算在球员速度 > 50% 最大速度时相对准确（±20%），
# 低速时高估（实际触球更频繁，因为球速衰减更快进入触球区）。
static func estimate_next_touch_interval(
	ball_velocity: Vector2,
	player_velocity: Vector2,
	player_max_speed: float,
	technique: float,
	mode: int = Mode.JOG
) -> float:
	var player_speed: float = player_velocity.length()
	if player_speed < IDLE_SPEED_THRESHOLD:
		return get_min_touch_interval(technique, mode)

	var t_norm: float = normalize_technique(technique)
	var f: float = GROUND_FRICTION_PER_SEC
	var base_efficiency: float = lerp(TOUCH_EFFICIENCY_MIN, TOUCH_EFFICIENCY_MAX, t_norm)
	var efficiency: float = base_efficiency + float(MODE_EFFICIENCY_OFFSET[mode])
	var zone_len: float = get_touch_zone_length(technique, mode)
	var zone_end: float = TOUCH_ZONE_FRONT_OFFSET + zone_len

	var speed_factor: float = clamp(player_speed / player_max_speed, 0.0, 1.0)
	var push_mult_base: float = lerp(PUSH_MULT_LOW_SPEED, PUSH_MULT_HIGH_SPEED, speed_factor)
	var push_multiplier: float = push_mult_base + float(MODE_PUSH_OFFSET[mode])
	var v_exit: float = player_speed * push_multiplier

	# 简化假设：触球后球以 v_exit 速度离开，衰减后回落到 zone_end
	# 求 v_exit * f^t 下降到某个值时，球从当前位置滚动到 zone_end 的时间
	# 实际上这是个超越方程，这里用粗略近似：T ≈ zone_len / (球平均速度)
	var v_avg: float = v_exit * 0.6  # 粗略取摩擦衰减后平均速度
	var interval: float = zone_len / v_avg if v_avg > 1.0 else MIN_TOUCH_INTERVAL
	return max(interval, get_min_touch_interval(technique, mode))

# 调试用：计算给定 technique 下的理论控球指标
# 返回 Dictionary: {touch_zone_len, max_control_dist, touch_efficiency, inaccuracy_deg}
static func debug_get_technique_stats(technique: float, mode: int = Mode.JOG) -> Dictionary:
	var t_norm: float = normalize_technique(technique)
	var base_efficiency: float = lerp(TOUCH_EFFICIENCY_MIN, TOUCH_EFFICIENCY_MAX, t_norm)
	var base_inaccuracy: float = lerp(MAX_INACCURACY_RAD, 0.0, t_norm)
	return {
		"technique_raw": technique,
		"technique_normalized": t_norm,
		"mode": mode,
		"touch_zone_len": get_touch_zone_length(technique, mode),
		"max_control_dist": get_max_control_distance(technique, mode),
		"min_touch_interval": get_min_touch_interval(technique, mode),
		"touch_efficiency": base_efficiency + float(MODE_EFFICIENCY_OFFSET[mode]),
		"inaccuracy_deg": rad_to_deg(base_inaccuracy * float(MODE_INACCURACY_MULT[mode])),
	}
