class_name InterceptResolver
extends RefCounted

## 自动断球与过人判定
## 核心原则：防守球员不需要按键，只要站在带球路线上就能断球
## 过人 = 在球进入断球范围的一瞬间变向，让球的运动方向偏离防守者

const AUTO_INTERCEPT_RADIUS := 12.0       ## 基础自动断球半径（像素）
const INTERCEPT_ANGLE_TOLERANCE := 35.0  ## 断球角度容差（度），球朝向防守者±这个角度内才能断 — 规格 35°
const TECHNIQUE_EVASION_BONUS := 15.0    ## 技术属性带来的"过人角度减免"（技术越好，越小角度也算变向成功）

## 检测防守球员是否能自动断下带球队员的球
## 返回 {success: bool, reason: String, quality: float}
static func check_auto_intercept(defender: Player, ball: Ball) -> Dictionary:
	# 只有球处于"离脚"状态时才能被断
	if not ball.is_ball_free():
		return {"success": false, "reason": "ball_not_free"}

	var ball_pos := ball.position
	var ball_vel := ball.velocity

	# 球没有速度（静止中被断？不应该）
	if ball_vel == Vector2.ZERO:
		return {"success": false, "reason": "ball_stationary"}

	var dist := defender.position.distance_to(ball_pos)

	# 防守属性加成：高防守的球员断球半径更大
	var defense_bonus := defender.defense / 100.0 * 4.0
	var effective_radius := AUTO_INTERCEPT_RADIUS + defense_bonus

	if dist > effective_radius:
		return {"success": false, "reason": "too_far"}

	# 球是否朝防守者方向来（带球人直线冲向防守者 = 最容易被断）
	var ball_to_defender := defender.position - ball_pos
	var angle_diff := rad_to_deg(abs(ball_vel.angle_to(ball_to_defender)))

	# 如果带球者有 carrier，计算其技术带来的变向优势
	if ball.carrier != null:
		var technique_evasion := (ball.carrier.technique / 100.0) * TECHNIQUE_EVASION_BONUS
		# 技术越好，需要更小的角度偏差才能被断（相当于防守者有效角度容差变小）
		var effective_angle_tolerance := INTERCEPT_ANGLE_TOLERANCE - technique_evasion
		if angle_diff > effective_angle_tolerance:
			return {"success": false, "reason": "bad_angle_evaded"}
	else:
		if angle_diff > INTERCEPT_ANGLE_TOLERANCE:
			return {"success": false, "reason": "bad_angle"}

	# 角度和距离都满足 → 断球成功
	# quality = 断球质量（越高 = 越干净的断球）
	var dist_quality := 1.0 - dist / effective_radius
	var angle_quality := 1.0 - angle_diff / INTERCEPT_ANGLE_TOLERANCE
	var quality: float = clamp(dist_quality * 0.6 + angle_quality * 0.4, 0.0, 1.0)

	return {
		"success": true,
		"quality": quality,
		"reason": "intercepted"
	}

## 在一组防守球员中找最可能断球的那个
## 返回 {defender: Player, quality: float} 或 null
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
