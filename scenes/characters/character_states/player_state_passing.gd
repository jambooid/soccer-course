class_name PlayerStatePassing
extends PlayerState

## 辅助瞄准参数（按传球类型）
const ASSIST_MAGNET_ANGLE_SHORT := 40.0    ## 短传吸附角度（度）— 规格 40°
const ASSIST_MAGNET_ANGLE_LONG := 60.0     ## 长传吸附角度 — 规格 60°
const ASSIST_MAGNET_ANGLE_THROUGH := 30.0  ## 直塞吸附角度 — 规格 30°

## 吸附距离（使用 PitchConstants 集中管理）
const ASSIST_MAGNET_RANGE_SHORT := PitchConstants.PLAYER.PASSING_ASSIST_MAGNET_RANGE_SHORT
const ASSIST_MAGNET_RANGE_LONG := PitchConstants.PLAYER.PASSING_ASSIST_MAGNET_RANGE_LONG
const ASSIST_MAGNET_RANGE_THROUGH := PitchConstants.PLAYER.PASSING_ASSIST_MAGNET_RANGE_THROUGH

func _enter_tree() -> void:
	animation_player.play("kick")
	player.velocity = Vector2.ZERO
	SoundPlayer.play(SoundPlayer.Sound.PASS)

func on_animation_complete() -> void:
	var pass_type := state_data.pass_type
	var pass_target := state_data.pass_target

	# 如果没有指定目标 → 用辅助瞄准找一个队友
	if pass_target == null:
		pass_target = _find_assisted_target(pass_type)

	# 越位检查（在传球瞬间判断目标是否越位）
	if pass_target != null and _check_offside(pass_target):
		# 越位：球变成自由球，在越位位置
		var container := get_tree().get_first_node_in_group("actors_container")
		if container != null:
			container.handle_offside(pass_target, pass_target.position)
		transition_state(Player.State.MOVING)
		return

	# 还是没有目标 → 朝朝向方向踢出（无目标传球）
	if pass_target == null:
		_execute_pass(pass_type, ball.position + player.heading * 100.0)
	else:
		# 调整朝向
		var direction := player.position.direction_to(pass_target.position)
		if sign(player.heading.x) != sign(direction.x):
			player.heading *= -1
		# 计算目标位置（带提前量）
		var target_pos := _compute_lead_target(pass_target, pass_type)
		_execute_pass(pass_type, target_pos)

	transition_state(Player.State.MOVING)

func _execute_pass(p_type: int, target_pos: Vector2) -> void:
	## 执行具体类型的传球
	match p_type:
		PlayerStateData.PassType.SHORT:
			ball.short_pass(target_pos, player)
		PlayerStateData.PassType.LONG:
			ball.long_pass(target_pos, player)
		PlayerStateData.PassType.THROUGH:
			ball.through_pass(target_pos, player)
		_:
			ball.short_pass(target_pos, player)

func _find_assisted_target(p_type: int) -> Player:
	## 辅助瞄准：在朝向方向的锥形范围内找最近/最准的队友
	var magnet_angle := 0.0
	var magnet_range := 0.0
	match p_type:
		PlayerStateData.PassType.SHORT:
			magnet_angle = ASSIST_MAGNET_ANGLE_SHORT
			magnet_range = ASSIST_MAGNET_RANGE_SHORT
		PlayerStateData.PassType.LONG:
			magnet_angle = ASSIST_MAGNET_ANGLE_LONG
			magnet_range = ASSIST_MAGNET_RANGE_LONG
		PlayerStateData.PassType.THROUGH:
			magnet_angle = ASSIST_MAGNET_ANGLE_THROUGH
			magnet_range = ASSIST_MAGNET_RANGE_THROUGH

	var heading_dir := player.heading.normalized()
	var best_target: Player = null
	var best_score := -1.0  # 分数越高越好（角度越正前方 + 距离越近）

	# 在队友检测区域中找
	for body in teammate_detection_area.get_overlapping_bodies():
		if not (body is Player):
			continue
		var p: Player = body
		if p == player or p.country != player.country:
			continue
		var to_target := p.position - player.position
		var dist := to_target.length()
		if dist > magnet_range or dist < 5.0:
			continue
		# 计算与朝向方向的夹角
		var angle_to_target: float = heading_dir.angle_to(to_target.normalized())
		var angle_deg: float = abs(angle_to_target) * 180.0 / PI
		if angle_deg > magnet_angle:
			continue
		# 评分：角度越正前方越好，距离越近越好
		var angle_score: float = 1.0 - (angle_deg / magnet_angle)
		var dist_score: float = 1.0 - (dist / magnet_range)
		var score: float = angle_score * 0.7 + dist_score * 0.3
		if score > best_score:
			best_score = score
			best_target = p

	return best_target

func _compute_lead_target(target: Player, p_type: int) -> Vector2:
	## 计算传球提前量（预判队友跑动方向）
	var relative_vel := target.velocity
	match p_type:
		PlayerStateData.PassType.SHORT:
			# 短传提前量小
			return target.position + relative_vel * 0.3
		PlayerStateData.PassType.LONG:
			# 长传提前量大（滞空时间长）
			return target.position + relative_vel * 0.8
		PlayerStateData.PassType.THROUGH:
			# 直塞提前量大（球速快，要送到队友身前）
			return target.position + _velocity_to_goal(target) * 0.6
		_:
			return target.position + relative_vel * 0.4

func _velocity_to_goal(target: Player) -> Vector2:
	## 估算目标球员朝向对方球门的方向速度
	var goal_dir := target.position.direction_to(target.target_goal.position)
	var speed_proj := target.velocity.dot(goal_dir)
	return goal_dir * max(speed_proj, 0.0)

func _check_offside(target: Player) -> bool:
	## 检查传球目标是否越位
	## 通过 ActorsContainer 组查找，避免直接引用耦合
	var container := get_tree().get_first_node_in_group("actors_container")
	if container == null:
		return false
	if not container.has_method("check_pass_offside"):
		return false
	var result: Dictionary = container.check_pass_offside(player)
	return result.is_offside and result.offender == target

func find_teammate_in_view() -> Player:
	## 兼容旧方法（保留给其他引用）
	return _find_assisted_target(PlayerStateData.PassType.SHORT)
