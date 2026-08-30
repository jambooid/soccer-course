class_name BallStateDribbling
extends BallState

## 物理推球式带球状态
## 核心机制：球有独立的速度和位置，通过摩擦力减速，球员通过周期性触球推动球前进
## 替换 CARRIED 状态的 lerp 跟随式带球，实现真实的惯性和物理感

## 接球宽限期（秒）：刚进入 DRIBBLING 的短暂时间内
## - 失控距离临时 × 宽限期倍率
## - 抢断概率临时 × 抢断宽限倍率
## - 宽限期结束后发出 ball_possession_stable 信号（用于自动切换球员）
## 确保接球第一下不会因为物理原因立刻丢球
const GRACE_PERIOD_SEC := 0.5  ## 从 0.3 延长到 0.5，确保球权稳定后再切换球员
const GRACE_CONTROL_DIST_MULT := 1.5
const GRACE_INTERCEPT_MULT := 0.5

## 急转时球的额外前冲倍率（模拟趟大）
const CUTBACK_BALL_KICK_MULT := 1.2

# 触球冷却（秒）
var touch_cooldown := 0.0
# 抢断检测帧计数（每 3 帧检测一次，降低性能消耗）
var intercept_check_frame := 0
var grace_period_timer := 0.0  ## 接球宽限期剩余时间
var _incoming_velocity := Vector2.ZERO  ## 进入状态前的入射速度（用于停球质量）

func _enter_tree() -> void:
	if carrier == null:
		transition_state(Ball.State.FREEFORM, BallStateData.build())
		return

	# 保存入射速度（在修改前记录）
	_incoming_velocity = ball.velocity

	ball.carrier = carrier
	GameEvents.ball_possessed.emit(carrier.fullname)
	GameEvents.ball_possessed_by.emit(carrier)

	# 带球时球在地面
	ball.height = 0.0
	ball.height_velocity = 0.0

	# 排除与携带者的物理碰撞（带球时球穿过携带者身体）
	ball.add_collision_exception_with(carrier)

	# 停球质量：根据入射速度和 technique 计算停球后的速度
	var incoming_speed := _incoming_velocity.length()
	if incoming_speed > DribblePhysics.IDLE_SPEED_THRESHOLD:
		# 有明显入射速度 → 应用停球质量计算
		var control_dir := carrier.heading
		ball.velocity = DribblePhysics.compute_first_touch_velocity(
			_incoming_velocity, control_dir, carrier.technique
		)
	else:
		# 入射速度很低（如从 FREEFORM 慢慢滚过来）→ 给一个同向初速度
		var current_speed := carrier.velocity.length()
		if ball.velocity.length() < current_speed * 0.3 and current_speed > DribblePhysics.IDLE_SPEED_THRESHOLD:
			ball.velocity = _get_player_direction() * current_speed * 0.8

	# 启动宽限期
	grace_period_timer = GRACE_PERIOD_SEC

func _process(delta: float) -> void:
	if not is_instance_valid(carrier):
		_release_ball()
		return

	# 1. 冷却计时 + 宽限期计时
	var prev_grace := grace_period_timer
	touch_cooldown = max(0.0, touch_cooldown - delta)
	grace_period_timer = max(0.0, grace_period_timer - delta)

	# 宽限期刚结束 → 发出稳定控球信号（用于自动切换球员）
	if prev_grace > 0.0 and grace_period_timer <= 0.0:
		GameEvents.ball_possession_stable.emit(carrier)

	# 预计算：有效技术值 & 球员当前方向 & 带球模式（多处复用）
	var effective_tech := carrier.technique
	var player_dir := _get_player_direction()
	var mode := carrier.dribble_mode

	# 2. 应用地面摩擦力（指数衰减）
	ball.velocity = DribblePhysics.apply_friction(ball.velocity, delta)

	# 2.5 静止/低速控球：球不会滚远，保持在脚边
	# 当球员速度很低时，给球一个轻微的"吸回"速度调整，
	# 让球稳定在触球区内而不是越滚越远
	var current_speed := carrier.velocity.length()
	if current_speed < DribblePhysics.IDLE_SPEED_THRESHOLD:
		var to_ball_idle := ball.position - carrier.position
		var forward_dist := to_ball_idle.dot(player_dir)
		# 球在前方且超过了理想距离 → 轻轻往回拉
		var zone_len := DribblePhysics.get_touch_zone_length(effective_tech, mode)
		var ideal_idle_dist := DribblePhysics.TOUCH_ZONE_FRONT_OFFSET + zone_len * 0.3
		if forward_dist > ideal_idle_dist:
			var pull_speed: float = min(ball.velocity.length(), 30.0)  # 最大拉回速度
			var pull_dir := (carrier.position - ball.position).normalized()
			ball.velocity = ball.velocity.lerp(pull_dir * pull_speed, 0.3)  # 从 0.1 提高到 0.3，增强吸附

	# 3. 物理移动 + 墙壁反弹
	var collision := ball.move_and_collide(ball.velocity * delta)
	if collision != null:
		# 弹开球但保持带球状态（撞墙后仍可能在可控范围内）
		var normal := collision.get_normal()
		ball.velocity = ball.velocity.bounce(normal) * ball.BOUNCINESS
		SoundPlayer.play(SoundPlayer.Sound.BOUNCE)

	# 4. 失控检测：球在球员前方且距离超过可控范围
	#    身后的球不算失控（球员可以转身回追）
	var to_ball := ball.position - carrier.position
	var dist := to_ball.length()
	var max_control := DribblePhysics.get_max_control_distance(effective_tech, mode)
	# 宽限期内失控距离放大
	if grace_period_timer > 0.0:
		max_control *= GRACE_CONTROL_DIST_MULT
	if dist > max_control and to_ball.dot(player_dir) > 0:
		_release_ball()
		return

	# 5. 触球检测
	if touch_cooldown <= 0.0:
		if DribblePhysics.is_ball_in_touch_zone(
			ball.position, carrier.position, player_dir, effective_tech, mode
		):
			var new_vel := DribblePhysics.compute_touch_impulse(
				ball.velocity, carrier.velocity, carrier.speed, effective_tech, mode
			)
			# 只在推球方向与球员移动方向一致时触球
			if new_vel.dot(player_dir) > ball.velocity.dot(player_dir):
				ball.velocity = new_vel
				touch_cooldown = DribblePhysics.get_min_touch_interval(effective_tech, mode)

	# 6. 播放球滚动动画
	set_ball_animation_from_velocity()

	# 7. 自动抢断检测（每 3 帧跑一次，降低性能消耗）
	intercept_check_frame += 1
	if intercept_check_frame >= 3:
		intercept_check_frame = 0
		_check_auto_intercept(delta * 3.0)

func _exit_tree() -> void:
	# 恢复与前携带者的碰撞
	if is_instance_valid(carrier):
		ball.remove_collision_exception_with(carrier)
	# 只有当球的当前携带者是自己时才清空 carrier
	# 防止抢断/球权易主时（DRIBBLING → DRIBBLING 自状态切换），
	# 旧状态的退出意外清空新状态已经设置的 carrier
	if ball.carrier == carrier:
		ball.carrier = null
	GameEvents.ball_released.emit()

# 获取球员当前方向：速度方向（速度足够大时），否则用 heading
func _get_player_direction() -> Vector2:
	if carrier.velocity.length() > 5.0:
		return carrier.velocity.normalized()
	return carrier.heading

# 释放球，切换到 FREEFORM 状态
func _release_ball() -> void:
	ball.carrier = null
	transition_state(Ball.State.FREEFORM, BallStateData.build())

# 自动抢断检测：使用概率式 InterceptResolver
# 从 player_proximity_area 中筛选对方球员，计算抢断概率并按概率判定
func _check_auto_intercept(delta: float) -> void:
	if not is_instance_valid(carrier):
		return
	# 使用 ball 的 player_proximity_area 获取附近球员
	var area := ball.player_proximity_area
	if area == null:
		return

	# 筛选候选防守者
	var candidates: Array[Player] = []
	for body in area.get_overlapping_bodies():
		if not (body is Player):
			continue
		var p: Player = body
		# 只考虑对手球员
		if p.country == carrier.country:
			continue
		# 门将有专门的抱球逻辑，不走自动断球
		if p.role == Player.Role.GOALIE:
			continue
		# 不在控球状态的球员才能断球（正在做其他动作时不行）
		if not p.can_carry_ball():
			continue
		candidates.append(p)

	if candidates.is_empty():
		return

	# 找到概率最高的防守者
	var result := InterceptResolver.find_best_interceptor_probability(
		candidates, carrier, ball.position, ball.velocity
	)

	if result.is_empty():
		return

	var best_defender: Player = result.player
	var probability: float = result.probability

	# 宽限期内抢断概率降低
	if grace_period_timer > 0.0:
		probability *= GRACE_INTERCEPT_MULT

	# 概率判定：probability 是每秒概率，delta 是时间窗口，概率 × delta 是实际判定阈值
	var chance := probability * delta
	if randf() < chance:
		_trigger_intercept(best_defender, probability)

# 抢断成功：球权转移给防守者，直接切换到新携带者的 DRIBBLING 状态
# 参考 FREEFORM 状态的 on_player_enter 模式：先设置 ball.carrier，再 transition_state
func _trigger_intercept(defender: Player, _quality: float) -> void:
	if not is_instance_valid(defender):
		return

	# 给球一个轻微的朝向防守者的速度，模拟被捅走的感觉
	var to_defender := (defender.position - ball.position).normalized()
	if to_defender == Vector2.ZERO:
		to_defender = Vector2.RIGHT
	ball.velocity = to_defender * max(ball.velocity.length() * 0.5, 30.0)

	# 设置新携带者（setup 会在 switch_state 中捕获这个值，传给新状态）
	ball.carrier = defender
	defender.control_ball()

	# 状态切换：旧 DRIBBLING 的 _exit_tree 会清理旧碰撞排除并释放信号，
	# 新 DRIBBLING 的 _enter_tree 会设置新碰撞排除并占用信号。
	transition_state(Ball.State.DRIBBLING, BallStateData.build())

## 急转时给球额外前冲（模拟趟大效果）
## 由 PlayerStateMoving 在检测到大角度急转时调用
func apply_cutback_kick() -> void:
	if ball.velocity.length() > 10.0:
		# 沿当前球速方向额外加速，增加失控风险
		ball.velocity *= CUTBACK_BALL_KICK_MULT

# 离脚检测：委托给 InterceptResolver.check_auto_intercept 判断
# DRIBBLING 状态下球不是一直"粘脚"，而是周期性触球，所以总是认为球是"离脚"的
# （与 CARRIED 状态的触球/离脚窗口不同，DRIBBLING 全程都是物理独立运动）
func is_ball_free() -> bool:
	return true
