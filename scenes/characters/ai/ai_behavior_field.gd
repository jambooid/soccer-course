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
	if is_ball_possessed_by_opponent() and player.position.distance_to(ball.position) < TACKLE_DISTANCE and randf() < TACKLE_PROBABILITY:
		player.switch_state(Player.State.TACKLING)
	if ball.carrier == player:
		var target := player.target_goal.get_center_target_position()
		var shot_probability := SHOT_PROBABILITY
		if GameManager.player_setup[0] == player.country or GameManager.player_setup[1] == player.country:
			shot_probability = shot_probability / 10.0
		if player.position.distance_to(target) < SHOT_DISTANCE and randf() < SHOT_PROBABILITY:
			player.face_towards_target_goal()
			var shot_direction := player.position.direction_to(player.target_goal.get_random_target_position())
			var data := PlayerStateData.build().set_shot_power(player.power).set_shot_direction(shot_direction)
			player.switch_state(Player.State.SHOOTING, data)
		elif randf() < PASS_PROBABILITY and has_opponents_nearby() and has_teammate_in_view():
			player.switch_state(Player.State.PASSING)

func _is_carrier_human_controlled() -> bool:
	## 判断球的持有者是否是人类玩家（P1 或 P2）
	if ball.carrier == null:
		return false
	return ball.carrier.control_scheme == Player.ControlScheme.P1 \
		or ball.carrier.control_scheme == Player.ControlScheme.P2

func get_offensive_support_steering_force() -> Vector2:
	## 人类队友持球时的无球跑位
	## 根据角色不同，做出不同类型的支援跑动：
	## - 前锋：向禁区/对方球门方向插入（反越位跑）
	## - 边锋/边前卫：拉边，创造宽度
	## - 中场：前插支援 + 保持阵型层次
	## - 边后卫：沿边路插上
	## - 中后卫：留在后方，不贸然压上
	var carrier := ball.carrier
	if carrier == null:
		return Vector2.ZERO

	# 太远了就先回到阵型位置（防止乱跑）
	var dist_to_ball := player.position.distance_to(carrier.position)
	if dist_to_ball > SUPPORT_RUN_ACTIVATION_DIST:
		return get_assist_formation_steering_force()

	var target_pos := _compute_support_target(carrier)
	var direction := player.position.direction_to(target_pos)
	var dist_to_target := player.position.distance_to(target_pos)

	# 靠近目标时减速，保持位置
	var weight := get_bicircular_weight(player.position, target_pos, 20, 0.1, 50, 1.0)

	# 离球越近，跑位越积极
	var proximity_factor := clamp(1.0 - dist_to_ball / SUPPORT_RUN_ACTIVATION_DIST, 0.3, 1.0)

	return weight * direction * proximity_factor

func _compute_support_target(carrier: Player) -> Vector2:
	## 根据角色计算支援跑位的目标位置
	var goal_pos := player.target_goal.get_center_target_position()
	var carrier_pos := carrier.position
	var attack_dir := carrier_pos.direction_to(goal_pos)
	var lateral_dir := Vector2(-attack_dir.y, attack_dir.x)  # 垂直于进攻方向

	# 计算球员在阵型中的横向位置（相对于中线的偏侧）
	var spawn_y_offset := player.spawn_position.y - carrier.spawn_position.y
	var is_wide_player := abs(spawn_y_offset) > 40  # 离中线远的就是边路球员

	match player.role:
		Player.Role.OFFENSE:
			# 前锋：向前插，跑到球和球门之间的位置
			var forward_push := SUPPORT_RUN_FORWARD_PUSH
			# 边路前锋拉边，中路前锋插禁区
			if is_wide_player:
				var wide_amount := sign(spawn_y_offset) * SUPPORT_RUN_WING_WIDTH * 0.7
				return carrier_pos + attack_dir * forward_push + lateral_dir * wide_amount
			else:
				# 中路前锋直接插向球门方向
				return carrier_pos + attack_dir * forward_push

		Player.Role.MIDFIELD:
			# 中场：向前支援，但保持一定距离作为传球选项
			var mid_push := SUPPORT_MID_PUSH
			if is_wide_player:
				# 边中场稍微拉边
				var wide_amount := sign(spawn_y_offset) * SUPPORT_RUN_WING_WIDTH * 0.5
				return carrier_pos + attack_dir * mid_push + lateral_dir * wide_amount
			else:
				# 中路中场在球前方不远处接应
				return carrier_pos + attack_dir * mid_push

		Player.Role.DEFENSE:
			# 后卫：边后卫可以插上，中后卫留守
			if is_wide_player:
				# 边后卫：沿边路插上
				var fb_push := SUPPORT_FULLBACK_PUSH
				var wide_amount := sign(spawn_y_offset) * SUPPORT_RUN_WING_WIDTH
				return carrier_pos + attack_dir * fb_push + lateral_dir * wide_amount
			else:
				# 中后卫：留在后方，跟球保持距离
				var hold_back := SUPPORT_CENTRAL_HOLD_DIST
				return carrier_pos - attack_dir * hold_back * 0.5

		_:
			return carrier.position

	return carrier.position

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
