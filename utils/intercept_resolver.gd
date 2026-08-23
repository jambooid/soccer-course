class_name InterceptResolver
extends RefCounted

## 抢断系统：支持两种模式
## 1. 旧版二元判定（check_auto_intercept）：用于 CARRIED 状态，返回 success/fail + quality
## 2. 新版概率式（compute_intercept_probability + find_best_interceptor）：用于 DRIBBLING 状态

# ---- 旧版二元判定常量（CARRIED 状态用） ----
const AUTO_INTERCEPT_RADIUS := 12.0       ## 基础自动断球半径（像素）
const INTERCEPT_ANGLE_TOLERANCE := 35.0  ## 断球角度容差（度），球朝向防守者±这个角度内才能断
const TECHNIQUE_EVASION_BONUS := 15.0    ## 技术属性带来的"过人角度减免"（技术越好，越小角度也算变向成功）

# ---- 新版概率式常量（DRIBBLING 状态用） ----
const INTERCEPT_MAX_DISTANCE := 18.0           # 最大断球距离（px）
const INTERCEPT_ANGLE_MAX := deg_to_rad(60)    # 最大正面断球角度（60°）
const INTERCEPT_SPEED_REF := 150.0             # 参考速度（用于归一化，px/s）
const BASE_INTERCEPT_RATE := 0.8               # 基础每秒抢断概率（满分时）
const MIN_TECHNIQUE_PROTECTION := 0.2          # 最低技术保护
const MAX_INTERCEPT_CHANCE := 0.9              # 最高每秒抢断概率上限
const BEHIND_ANGLE_SCORE := 0.15               # 身后断球的固定角度分（>90°）

# 真实 Player 属性范围
const DEFENSE_MIN := 24.0
const DEFENSE_MAX := 94.0
const TECHNIQUE_MIN := 30.0
const TECHNIQUE_MAX := 98.0

# ========== 旧版二元判定接口（CARRIED 状态用） ==========

## 检测防守球员是否能自动断下带球队员的球（二元判定）
## 返回 {success: bool, reason: String, quality: float}
static func check_auto_intercept(defender: Player, ball: Ball) -> Dictionary:
	# 只有球处于"离脚"状态时才能被断
	if not ball.is_ball_free():
		return {"success": false, "reason": "ball_not_free"}

	var ball_pos := ball.position
	var ball_vel := ball.velocity
	if ball_vel == Vector2.ZERO:
		return {"success": false, "reason": "ball_stationary"}

	var dist := defender.position.distance_to(ball_pos)
	var defense_bonus := defender.defense / 100.0 * 4.0
	var effective_radius := AUTO_INTERCEPT_RADIUS + defense_bonus
	if dist > effective_radius:
		return {"success": false, "reason": "too_far"}

	var ball_to_defender := defender.position - ball_pos
	var angle_diff := rad_to_deg(abs(ball_vel.angle_to(ball_to_defender)))

	if ball.carrier != null:
		var technique_evasion := (ball.carrier.technique / 100.0) * TECHNIQUE_EVASION_BONUS
		var effective_angle_tolerance := INTERCEPT_ANGLE_TOLERANCE - technique_evasion
		if angle_diff > effective_angle_tolerance:
			return {"success": false, "reason": "bad_angle_evaded"}
	else:
		if angle_diff > INTERCEPT_ANGLE_TOLERANCE:
			return {"success": false, "reason": "bad_angle"}

	var dist_quality := 1.0 - dist / effective_radius
	var angle_quality := 1.0 - angle_diff / INTERCEPT_ANGLE_TOLERANCE
	var quality: float = clamp(dist_quality * 0.6 + angle_quality * 0.4, 0.0, 1.0)
	return {"success": true, "quality": quality, "reason": "intercepted"}

static func find_best_interceptor(defenders: Array, ball: Ball) -> Dictionary:
	var best: Player = null
	var best_quality := -1.0

	for defender in defenders:
		if defender == null:
			continue
		var result := check_auto_intercept(defender, ball)
		if result.success and result.quality > best_quality:
			best = defender
			best_quality = result.quality

	if best != null:
		return {"defender": best, "quality": best_quality}
	return {}

# ========== 新版概率式接口（DRIBBLING 状态用） ==========

# 计算每秒的抢断概率（0.0 ~ MAX_INTERCEPT_CHANCE）
# 调用方需要 × delta 后再按概率判定
#
# 使用真实的 defense vs technique 属性（范围 24-94 vs 30-98）
static func compute_intercept_probability(
	defender: Player,
	dribbler: Player,
	ball_pos: Vector2,
	ball_vel: Vector2
) -> float:
	# 1. 距离分：球离防守者越近，分越高
	var dist_to_ball := defender.position.distance_to(ball_pos)
	if dist_to_ball > INTERCEPT_MAX_DISTANCE:
		return 0.0
	var dist_score := clamp(1.0 - dist_to_ball / INTERCEPT_MAX_DISTANCE, 0.0, 1.0)

	# 2. 角度分：防守者是否在球的正面方向
	var angle_score := 1.0
	var ball_speed := ball_vel.length()
	if ball_speed >= 5.0:
		var ball_to_defender := (defender.position - ball_pos).normalized()
		var angle_diff := abs(ball_vel.angle_to(ball_to_defender))
		if angle_diff > PI / 2.0:
			# 身后（>90°）也能断但概率大幅降低，固定为 15% 角度分
			angle_score = BEHIND_ANGLE_SCORE
		else:
			# 正面（0°）最高，侧面（60°）降为 0
			angle_score = clamp(1.0 - angle_diff / INTERCEPT_ANGLE_MAX, 0.0, 1.0)

	# 3. 相对速度分：接近速度越快越突然（越容易断）
	var defender_to_ball := (ball_pos - defender.position).normalized()
	var defender_approach_speed := max(0.0, defender.velocity.dot(defender_to_ball))
	var total_approach := ball_speed + defender_approach_speed
	var speed_score := clamp(total_approach / INTERCEPT_SPEED_REF, 0.0, 1.0)

	# 4. 属性对抗：defense vs technique（真实属性范围）
	# 归一化到 0-1，然后计算对抗因子
	var def_norm := clamp((defender.defense - DEFENSE_MIN) / (DEFENSE_MAX - DEFENSE_MIN), 0.0, 1.0)
	var tech_norm := clamp((dribbler.technique - TECHNIQUE_MIN) / (TECHNIQUE_MAX - TECHNIQUE_MIN), 0.0, 1.0)
	# stat_factor: 防守高/技术低 → 接近 0.9，防守低/技术高 → 接近 0.2
	var stat_factor := clamp(0.5 + (def_norm - tech_norm) * 0.4, MIN_TECHNIQUE_PROTECTION, MAX_INTERCEPT_CHANCE)

	# 综合：距离 × 角度 × 速度 作为机会分，再 × 属性因子 × 基础概率
	var opportunity := dist_score * angle_score * (0.5 + speed_score * 0.5)
	var per_second_prob := opportunity * stat_factor * BASE_INTERCEPT_RATE

	return clamp(per_second_prob, 0.0, MAX_INTERCEPT_CHANCE)

# 找到附近最合适的断球者（概率最高的那个）
# 返回 {player: Player, probability: float} 或空字典
static func find_best_interceptor_probability(
	candidates: Array[Player],
	dribbler: Player,
	ball_pos: Vector2,
	ball_vel: Vector2
) -> Dictionary:
	var best: Player = null
	var best_prob := 0.0
	for defender in candidates:
		if defender == dribbler:
			continue
		if not is_instance_valid(defender):
			continue
		var prob := compute_intercept_probability(defender, dribbler, ball_pos, ball_vel)
		if prob > best_prob:
			best_prob = prob
			best = defender
	if best != null:
		return {"player": best, "probability": best_prob}
	return {}
