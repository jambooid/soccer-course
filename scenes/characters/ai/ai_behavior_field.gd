class_name AIBehaviorField
extends AIBehavior

const PASS_PROBABILITY := 0.05
const SHOT_DISTANCE := 150
const SHOT_PROBABILITY := 0.3
const SPREAD_ASSIST_FACTOR := 0.8
const TACKLE_DISTANCE := 15
const TACKLE_PROBABILITY := 0.3

## 无球跑位（进攻支援）参数
const SUPPORT_RUN_WING_WIDTH := 70.0       ## 边路球员拉开宽度
const SUPPORT_RUN_FORWARD_PUSH := 90.0     ## 前锋向前插的距离
const SUPPORT_MID_PUSH := 50.0            ## 中场向前支援的距离
const SUPPORT_FULLBACK_PUSH := 60.0       ## 边后卫插上距离
const SUPPORT_CENTRAL_HOLD_DIST := 80.0   ## 后腰保持的距离（球后方）
const SUPPORT_RUN_ACTIVATION_DIST := 200.0 ## 离球多远以内开始跑位

## 无球跑位状态机
enum OffBallRunState {
	HOLD_POSITION,   ## 保持位置
	BREAK_OFFSIDE,   ## 反越位前插
	PULL_WIDE,       ## 拉边
	DROP_DEEP,       ## 回撤接应
	OVERLAP_RUN      ## 套边助攻
}
const RUN_STATE_COOLDOWN_MS := 800    ## 跑位状态切换冷却（毫秒），防止抖动
var current_run_state : int = OffBallRunState.HOLD_POSITION
var run_state_cooldown_ms := 0.0       ## 剩余冷却时间
var cached_run_target := Vector2.ZERO ## 缓存的跑位目标位置（冷却期内使用）

func perform_ai_movement() -> void:
	var total_steering_force := Vector2.ZERO
	if player.has_ball():
		total_steering_force += get_carrier_steering_force()
	elif is_ball_carried_by_teammate():
		if _is_carrier_human_controlled():
			# 队友是人类玩家 → 智能无球跑位，创造传球选项
			total_steering_force += get_offensive_support_steering_force()
		else:
			# 队友是 AI → 保持阵型跟随
			total_steering_force += get_assist_formation_steering_force()
	else:
		total_steering_force += get_onduty_steering_force()
		if total_steering_force.length_squared() < 1:
			if is_ball_possessed_by_opponent():
				total_steering_force += get_spawn_steering_force()
			elif ball.carrier == null:
				total_steering_force += get_ball_proximity_steering_force()
				total_steering_force += get_density_around_ball_steering_force()

	total_steering_force = total_steering_force.limit_length(1.0)
	player.velocity = total_steering_force * player.speed

func perform_ai_decisions() -> void:
	# 防守时的断球决策
	if is_ball_possessed_by_opponent() and player.position.distance_to(ball.position) < TACKLE_DISTANCE and randf() < TACKLE_PROBABILITY:
		player.switch_state(Player.State.TACKLING)
		return

	# 持球时的进攻决策树
	if ball.carrier == player:
		_make_carrier_decision()

func _make_carrier_decision() -> void:
	## CPU 持球决策树
	## 根据场上形势、属性、位置决定：射门 / 传球(短/长/直塞) / 带球
	var target_goal_pos := player.target_goal.get_center_target_position()
	var dist_to_goal := player.position.distance_to(target_goal_pos)
	var own_goal_pos := player.own_goal.get_center_target_position()
	var dist_to_own_goal := player.position.distance_to(own_goal_pos)

	# 场上区域判断
	var in_attacking_third := dist_to_goal < SHOT_DISTANCE * 1.5
	var in_midfield := dist_to_goal > SHOT_DISTANCE and dist_to_own_goal > SHOT_DISTANCE
	var in_own_half := dist_to_own_goal < dist_to_goal

	# 防守压力（附近对手数量）
	var opponent_count := _count_nearby_opponents()
	var under_pressure := opponent_count >= 2

	# 玩家队伍的 AI 减少射门/传球频率（把球权交给玩家主导）
	var is_player_team := GameManager.player_setup[0] == player.country \
		or GameManager.player_setup[1] == player.country
	var decision_multiplier := 0.1 if is_player_team else 1.0

	# === 决策优先级 ===

	# 1. 禁区内有机会 → 射门（最高优先级）
	if in_attacking_third and dist_to_goal < SHOT_DISTANCE:
		var shoot_prob := SHOT_PROBABILITY
		# 射门属性高的球员更倾向射门
		shoot_prob *= 0.5 + (player.shooting / 100.0) * 0.8
		# 防守压力大时降低射门概率（更难起脚）
		if under_pressure:
			shoot_prob *= 0.5
		if randf() < shoot_prob * decision_multiplier:
			_execute_shot(target_goal_pos)
			return

	# 2. 防守压力大 → 传球（出球）
	if under_pressure and randf() < 0.6 * decision_multiplier:
		var pass_result := _find_best_pass_option()
		if pass_result.target != null:
			_execute_pass(pass_result.target, pass_result.pass_type)
			return

	# 3. 有好的直塞/长传机会 → 传威胁球
	if not in_own_half:
		var pass_result := _find_best_pass_option()
		if pass_result.target != null and pass_result.quality > 0.7:
			var threat_pass_prob := 0.15 + (player.technique / 100.0) * 0.2
			if randf() < threat_pass_prob * decision_multiplier:
				_execute_pass(pass_result.target, pass_result.pass_type)
				return

	# 4. 中场区域，前面没人 → 偶尔长传找前锋
	if in_midfield and opponent_count == 0 and randf() < 0.05 * decision_multiplier:
		var forward_target := _find_most_forward_teammate()
		if forward_target != null:
			_execute_pass(forward_target, PlayerStateData.PassType.LONG)
			return

	# 5. 默认：继续带球（不做决策，movement 系统负责推进）
	# 技术好的球员更愿意带球推进（这里不做任何事 = 继续带球）

func _count_nearby_opponents() -> int:
	## 统计附近的对手数量
	var count := 0
	for body in opponent_detection_area.get_overlapping_bodies():
		if body is Player and body.country != player.country:
			count += 1
	return count

func _find_best_pass_option() -> Dictionary:
	## 寻找最佳传球选项，返回 {target, pass_type, quality}
	var best_target: Player = null
	var best_quality := -1.0
	var best_pass_type := PlayerStateData.PassType.SHORT

	var goal_pos := player.target_goal.get_center_target_position()

	for body in teammate_detection_area.get_overlapping_bodies():
		if not (body is Player):
			continue
		var teammate: Player = body
		if teammate == player or teammate.country != player.country:
			continue

		var dist := player.position.distance_to(teammate.position)
		if dist < 10.0 or dist > 250.0:
			continue

		# 计算传球质量
		var to_teammate := teammate.position - player.position
		var to_goal := goal_pos - player.position
		var angle_to_goal: float = abs(to_teammate.angle_to(to_goal))
		var angle_score: float = 1.0 - clamp(angle_to_goal / PI, 0.0, 1.0)  # 朝向球门的传球更好

		var dist_score: float = 1.0 - clamp(dist / 250.0, 0.0, 1.0)

		# 前方队友更有威胁
		var forward_factor := 1.0 if to_teammate.dot(to_goal) > 0 else 0.5

		var quality: float = angle_score * 0.4 + dist_score * 0.3 + forward_factor * 0.3

		# 决定传球类型
		var pass_type := PlayerStateData.PassType.SHORT
		if dist > 120.0:
			pass_type = PlayerStateData.PassType.LONG
		elif dist > 60.0 and angle_to_goal < 0.5:  # 正对前方的中距离 → 直塞
			pass_type = PlayerStateData.PassType.THROUGH

		if quality > best_quality:
			best_quality = quality
			best_target = teammate
			best_pass_type = pass_type

	return {"target": best_target, "quality": best_quality, "pass_type": best_pass_type}

func _find_most_forward_teammate() -> Player:
	## 找到最靠前的队友（用于长传冲吊）
	var goal_pos := player.target_goal.get_center_target_position()
	var most_forward: Player = null
	var best_dist := 0.0

	for body in teammate_detection_area.get_overlapping_bodies():
		if not (body is Player):
			continue
		var teammate: Player = body
		if teammate == player or teammate.country != player.country:
			continue
		if teammate.role != Player.Role.OFFENSE:
			continue  # 只找前锋
		var dist := teammate.position.distance_to(goal_pos)
		if most_forward == null or dist < best_dist:
			best_dist = dist
			most_forward = teammate

	return most_forward

func _execute_shot(target_pos: Vector2) -> void:
	## 执行射门：以 target_pos 为基准，根据射门精度添加随机偏差
	player.face_towards_target_goal()
	# 根据射门属性计算偏差：属性越低，偏差越大
	var inaccuracy: float = (1.0 - player.shooting / 100.0) * 15.0
	var offset_y: float = randf_range(-inaccuracy, inaccuracy)
	var shot_target := target_pos + Vector2(0, offset_y)
	var shot_direction := player.position.direction_to(shot_target)
	var data := PlayerStateData.build().set_shot_power(player.power).set_shot_direction(shot_direction)
	player.switch_state(Player.State.SHOOTING, data)

func _execute_pass(target: Player, pass_type: int) -> void:
	## 执行传球
	var direction := player.position.direction_to(target.position)
	if sign(player.heading.x) != sign(direction.x):
		player.heading *= -1
	var data := PlayerStateData.build().set_pass_type(pass_type).set_pass_target(target)
	player.switch_state(Player.State.PASSING, data)

func _is_carrier_human_controlled() -> bool:
	## 判断球的持有者是否是人类玩家（P1 或 P2）
	if ball.carrier == null:
		return false
	return ball.carrier.control_scheme == Player.ControlScheme.P1 \
		or ball.carrier.control_scheme == Player.ControlScheme.P2

func get_offensive_support_steering_force() -> Vector2:
	## 人类队友持球时的无球跑位（状态机驱动，带冷却防抖）
	## 跑位状态每 800ms 重新评估一次，冷却期内维持当前跑位目标
	var carrier := ball.carrier
	if carrier == null:
		return Vector2.ZERO

	# 太远了就先回到阵型位置（防止乱跑）
	var dist_to_ball := player.position.distance_to(carrier.position)
	if dist_to_ball > SUPPORT_RUN_ACTIVATION_DIST:
		current_run_state = OffBallRunState.HOLD_POSITION
		return get_assist_formation_steering_force()

	# 更新冷却 + 判断是否需要重新选择跑位状态
	if run_state_cooldown_ms <= 0:
		# 冷却结束，重新选择跑位状态
		_select_run_state(carrier)
		# 根据新状态计算目标位置
		cached_run_target = _compute_run_target_for_state(carrier, current_run_state)
		run_state_cooldown_ms = RUN_STATE_COOLDOWN_MS
	else:
		run_state_cooldown_ms -= _get_tick_interval_ms()

	var target_pos := cached_run_target
	var direction := player.position.direction_to(target_pos)
	var dist_to_target := player.position.distance_to(target_pos)

	# 靠近目标时减速，保持位置
	var weight := get_bicircular_weight(player.position, target_pos, 20, 0.1, 50, 1.0)

	# 离球越近，跑位越积极
	var proximity_factor: float = clamp(1.0 - dist_to_ball / SUPPORT_RUN_ACTIVATION_DIST, 0.3, 1.0)

	return weight * direction * proximity_factor

func _select_run_state(carrier: Player) -> void:
	## 根据场上形势选择跑位状态
	var goal_pos := player.target_goal.get_center_target_position()
	var dist_to_goal := player.position.distance_to(goal_pos)
	var dist_to_ball := player.position.distance_to(carrier.position)
	var attack_dir := carrier.position.direction_to(goal_pos)

	# 计算球员在阵型中的横向位置
	var spawn_y_offset := player.spawn_position.y - carrier.spawn_position.y
	var is_wide_player: bool = abs(spawn_y_offset) > 40

	match player.role:
		Player.Role.OFFENSE:
			# 前锋：大部分时间尝试反越位前插，偶尔拉边
			if is_wide_player and randf() < 0.4:
				current_run_state = OffBallRunState.PULL_WIDE
			else:
				current_run_state = OffBallRunState.BREAK_OFFSIDE

		Player.Role.MIDFIELD:
			# 中场：根据距离选择回撤或前插
			if dist_to_ball > 120.0:
				current_run_state = OffBallRunState.DROP_DEEP
			elif is_wide_player and randf() < 0.3:
				current_run_state = OffBallRunState.PULL_WIDE
			else:
				current_run_state = OffBallRunState.BREAK_OFFSIDE

		Player.Role.DEFENSE:
			# 后卫：边后卫套边，中后卫留守
			if is_wide_player and dist_to_goal > 150.0:
				current_run_state = OffBallRunState.OVERLAP_RUN
			else:
				current_run_state = OffBallRunState.HOLD_POSITION

		_:
			current_run_state = OffBallRunState.HOLD_POSITION

func _compute_run_target_for_state(carrier: Player, state: int) -> Vector2:
	## 根据跑位状态计算目标位置
	var goal_pos := player.target_goal.get_center_target_position()
	var carrier_pos := carrier.position
	var attack_dir := carrier_pos.direction_to(goal_pos)
	var lateral_dir := Vector2(-attack_dir.y, attack_dir.x)
	var spawn_y_offset := player.spawn_position.y - carrier.spawn_position.y

	match state:
		OffBallRunState.BREAK_OFFSIDE:
			# 反越位：向球门方向前插
			var forward_push := SUPPORT_RUN_FORWARD_PUSH
			return carrier_pos + attack_dir * forward_push

		OffBallRunState.PULL_WIDE:
			# 拉边：向边路拉开宽度
			var wide_amount: float = sign(spawn_y_offset) * SUPPORT_RUN_WING_WIDTH
			var mid_push := SUPPORT_MID_PUSH * 0.5
			return carrier_pos + attack_dir * mid_push + lateral_dir * wide_amount

		OffBallRunState.DROP_DEEP:
			# 回撤：回到球后方接应
			var drop_back := SUPPORT_CENTRAL_HOLD_DIST * 0.8
			return carrier_pos - attack_dir * drop_back

		OffBallRunState.OVERLAP_RUN:
			# 套边：沿边路插上
			var fb_push := SUPPORT_FULLBACK_PUSH
			var wide_amount: float = sign(spawn_y_offset) * SUPPORT_RUN_WING_WIDTH
			return carrier_pos + attack_dir * fb_push + lateral_dir * wide_amount

		_:  # HOLD_POSITION
			# 保持位置：停在当前位置附近
			return player.position + attack_dir * 20.0



func get_onduty_steering_force() -> Vector2:
	return player.weight_on_duty_steering * player.position.direction_to(ball.position)

func get_carrier_steering_force() -> Vector2:
	var target := player.target_goal.get_center_target_position()
	var direction := player.position.direction_to(target)
	var weight := get_bicircular_weight(player.position, target, 100, 0, 150, 1)
	return weight * direction

func get_assist_formation_steering_force() -> Vector2:
	var spawn_difference := ball.carrier.spawn_position - player.spawn_position
	var assist_destination := ball.carrier.position - spawn_difference * SPREAD_ASSIST_FACTOR
	var direction := player.position.direction_to(assist_destination)
	var weight := get_bicircular_weight(player.position, assist_destination, 30, 0.2, 60, 1)
	return weight * direction

func get_ball_proximity_steering_force() -> Vector2:
	var weight := get_bicircular_weight(player.position, ball.position, 50, 1, 120, 0)
	var direction := player.position.direction_to(ball.position)
	return weight * direction

func get_spawn_steering_force() -> Vector2:
	var weight := get_bicircular_weight(player.position, player.spawn_position, 30, 0, 100, 1)
	var direction := player.position.direction_to(player.spawn_position)
	return weight * direction

func get_density_around_ball_steering_force() -> Vector2:
	var nb_teammates_near_ball := ball.get_proximity_teammates_count(player.country)
	if nb_teammates_near_ball == 0:
		return Vector2.ZERO
	var weight := 1 - 1.0 / nb_teammates_near_ball
	var direction := ball.position.direction_to(player.position)
	return weight * direction

func has_teammate_in_view() -> bool:
	var players_in_view := teammate_detection_area.get_overlapping_bodies()
	return players_in_view.find_custom(func(p: Player): return p != player and p.country == player.country) > -1
