class_name BallStateDribbling
extends BallState

const BallTrajectoryScript := preload("res://utils/ball_trajectory.gd")
const DribbleTouchControllerScript := preload("res://utils/dribble_touch_controller.gd")

## 物理推球式带球状态
## 核心机制：球有独立的速度和位置，通过摩擦力减速，球员通过周期性触球推动球前进
## 替换 CARRIED 状态的 lerp 跟随式带球，实现真实的惯性和物理感

## 带球常量（使用 PitchConstants 集中管理）
const GRACE_PERIOD_SEC := PitchConstants.BALL.DRIBBLING_GRACE_PERIOD_SEC
const GRACE_CONTROL_DIST_MULT := PitchConstants.BALL.DRIBBLING_GRACE_CONTROL_DIST_MULT
const GRACE_INTERCEPT_MULT := PitchConstants.BALL.DRIBBLING_GRACE_INTERCEPT_MULT
const CUTBACK_BALL_KICK_MULT := PitchConstants.BALL.DRIBBLING_CUTBACK_BALL_KICK_MULT

# 抢断检测帧计数（每 3 帧检测一次，降低性能消耗）
var intercept_check_frame := 0
var grace_period_timer := 0.0  ## 接球宽限期剩余时间
var _incoming_velocity := Vector2.ZERO  ## 进入状态前的入射速度（用于停球质量）
var _touch_controller

func _enter_tree() -> void:
	if carrier == null:
		transition_state(Ball.State.FREEFORM, BallStateData.build())
		return

	# 保存入射速度（在修改前记录）
	_incoming_velocity = ball.velocity
	_touch_controller = DribbleTouchControllerScript.new(
		carrier.jersey_number * 104729 + int(ball.spawn_position.x * 31.0 + ball.spawn_position.y))

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
		ball.velocity = _touch_controller.first_touch(_incoming_velocity, control_dir, carrier.technique)
	else:
		# 入射速度很低（如从 FREEFORM 慢慢滚过来）→ 给一个同向初速度
		var current_speed := carrier.velocity.length()
		if ball.velocity.length() < current_speed * 0.3 and current_speed > DribblePhysics.IDLE_SPEED_THRESHOLD:
			ball.velocity = _get_player_direction() * current_speed * 0.8

	# 启动宽限期
	grace_period_timer = GRACE_PERIOD_SEC

func _physics_process(delta: float) -> void:
	if not is_instance_valid(carrier):
		_release_ball()
		return

	# 1. 宽限期计时
	var prev_grace := grace_period_timer
	grace_period_timer = max(0.0, grace_period_timer - delta)

	# 宽限期刚结束 → 发出稳定控球信号（用于自动切换球员）
	if prev_grace > 0.0 and grace_period_timer <= 0.0:
		GameEvents.ball_possession_stable.emit(carrier)

	# 预计算：有效技术值 & 球员当前方向 & 带球模式（多处复用）
	var effective_tech := carrier.technique
	var player_dir := _get_player_direction()
	var mode := carrier.dribble_mode
	var current_speed := carrier.velocity.length()  # 提前计算球员速度
	var movement_intended := _carrier_movement_intended()

	# 2. 应用地面摩擦力（指数衰减）
	ball.velocity = DribblePhysics.apply_friction(ball.velocity, delta)

	# 2.5 控球稳定约束
	#
	# DRIBBLING 的球仍然是独立的物理实体，但在没有抢断/碰撞时，
	# 球员应始终能把球留在自己的控制范围内。单纯依赖周期性触球会
	# 在停步或转身期间留下一个“无触球死区”：球继续沿旧惯性滚动，
	# 而球员已经减速/换向，下一帧就可能越过失控边界。
	# 低速和转身时使用强约束，高速时只施加轻微回拉，保留带球惯性。
	var turn_state: PlayerStateMoving = carrier.current_state as PlayerStateMoving
	if turn_state != null and turn_state.turn_active:
		# 转身是主动控球动作：收球到新方向的脚下，避免旧方向惯性把球甩开。
		var turn_ideal_pos := carrier.position + player_dir * 12.0
		var turn_follow_factor: float = 1.0 - pow(0.02, delta / maxf(turn_state.turn_duration, 0.01))
		ball.position = ball.position.lerp(turn_ideal_pos, clampf(turn_follow_factor, 0.0, 1.0))
		ball.velocity = Vector2.ZERO
	elif current_speed < DribblePhysics.IDLE_SPEED_THRESHOLD:
		# 停步时把球收回脚边，并让残余速度快速归零。
		var idle_ideal_pos := carrier.position + player_dir * 12.0
		var idle_offset := idle_ideal_pos - ball.position
		if idle_offset.length() > 3.0:
			ball.position = ball.position.lerp(idle_ideal_pos, 0.4)
		ball.velocity = ball.velocity.lerp(carrier.velocity, 0.5)
		if not movement_intended and ball.velocity.length() < DribblePhysics.IDLE_SPEED_THRESHOLD:
			ball.velocity = Vector2.ZERO
	else:
		# 正常跑动时只在明显偏离脚下时回拉，不覆盖触球冲量。
		var moving_ideal_pos := carrier.position + player_dir * 12.0
		var to_ideal := moving_ideal_pos - ball.position
		var deviation := to_ideal.length()
		if deviation > 8.0:
			ball.velocity += to_ideal.normalized() * deviation * 0.15

	# 3. 物理移动 + 墙壁反弹
	var collision := ball.move_and_collide(ball.velocity * delta)
	if collision != null:
		# 弹开球但保持带球状态（撞墙后仍可能在可控范围内）
		var normal := collision.get_normal()
		ball.velocity = BallTrajectoryScript.bounce_velocity(
			ball.velocity, normal, ball.BOUNCINESS)
		SoundPlayer.play(SoundPlayer.Sound.BOUNCE)

	# 4. 失控检测：球在球员前方且距离超过可控范围
	#    身后的球不算失控（球员可以转身回追）
	var to_ball := ball.position - carrier.position
	var dist := to_ball.length()
	var max_control := DribblePhysics.get_max_control_distance(effective_tech, mode)
	# 宽限期内失控距离放大
	if grace_period_timer > 0.0:
		max_control *= GRACE_CONTROL_DIST_MULT
	# 球虽然暂时越过边界，但如果正在回到球员身边，不应被判为丢球。
	# 这会过滤掉转身/急停时的单帧惯性超出；只有球仍在向外滚时才释放。
	var moving_away := ball.velocity.length() < 5.0 \
		or (dist > 0.001 and ball.velocity.dot(to_ball / dist) > 0.0)
	if dist > max_control and to_ball.dot(player_dir) > 0 and moving_away:
		_release_ball()
		return

	# 5. 触球冲量负责主动推进；上面的约束只负责防止无对抗时脱离控制。
	var touch: Dictionary = _touch_controller.advance(delta, ball.position, carrier.position,
		player_dir, ball.velocity, carrier.velocity, carrier.speed, effective_tech,
		mode, movement_intended)
	if not touch.is_empty():
		ball.velocity = touch.velocity
		ball.dribble_touch_events.append(touch.duplicate(true))
		GameEvents.dribble_touch.emit(touch)

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
	if carrier.current_state is PlayerStateMoving:
		return (carrier.current_state as PlayerStateMoving).get_dribble_direction()
	if carrier.velocity.length() > 5.0:
		return carrier.velocity.normalized()
	return carrier.heading

func _carrier_movement_intended() -> bool:
	# 人类输入在 PlayerStateMoving.is_moving 中记录；AI 没有该标记，使用当前速度判断。
	if carrier.control_scheme == Player.ControlScheme.CPU:
		return carrier.velocity.length() >= DribblePhysics.IDLE_SPEED_THRESHOLD
	if carrier.current_state is PlayerStateMoving:
		var moving_state := carrier.current_state as PlayerStateMoving
		return moving_state.is_moving and not moving_state.turn_active
	return carrier.velocity.length() >= DribblePhysics.IDLE_SPEED_THRESHOLD

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
