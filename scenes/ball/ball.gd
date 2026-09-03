class_name Ball
extends AnimatableBody2D

const BallTrajectoryScript := preload("res://utils/ball_trajectory.gd")
const BallInteractionResolverScript := preload("res://utils/ball_interaction_resolver.gd")
const GoalkeeperInteractionPolicyScript := preload("res://utils/goalkeeper_interaction_policy.gd")

## 球物理常量（使用 PitchConstants 集中管理）
const BOUNCINESS := PitchConstants.BALL.BOUNCINESS
const DISTANCE_HIGH_PASS := PitchConstants.BALL.DISTANCE_HIGH_PASS
const DURATION_TUMBLE_LOCK := PitchConstants.BALL.DURATION_TUMBLE_LOCK
const DURATION_PASS_LOCK := PitchConstants.BALL.DURATION_PASS_LOCK
const KICKOFF_TEAM_LOCK_MS := PitchConstants.BALL.KICKOFF_TEAM_LOCK_MS
const TUMBLE_HEIGHT_VELOCITY := PitchConstants.BALL.TUMBLE_HEIGHT_VELOCITY

enum State {CARRIED, FREEFORM, SHOT, KICKED, SAVED, DEFLECTED, HELD_BY_GOALKEEPER, DRIBBLING}

@export var friction_air : float
@export var friction_ground : float

@onready var animation_player : AnimationPlayer = %AnimationPlayer
@onready var ball_sprite : Sprite2D = %BallSprite
@onready var player_detection_area : Area2D = %PlayerDetectionArea
@onready var player_proximity_area : Area2D = %PlayerProximityArea
@onready var scoring_raycast : RayCast2D = %ScoringRaycast
@onready var shot_particles : GPUParticles2D = %ShotParticles

var carrier : Player = null
var current_state : BallState = null
var height := 0.0
var height_velocity := 0.0
var spawn_position := Vector2.ZERO
var state_factory := BallStateFactory.new()
var velocity := Vector2.ZERO
var dribble_touch_events: Array[Dictionary] = []
var _recapture_lock_player : Player = null
var _recapture_lock_until_ms := 0
var _pickup_enabled := true
var _pickup_country := ""
var _pickup_country_until_ms := 0

func _ready() -> void:
	switch_state(State.FREEFORM)
	spawn_position = position
	GameEvents.team_reset.connect(on_team_reset.bind())

func _process(_delta: float) -> void:
	ball_sprite.position = Vector2.UP * height
	scoring_raycast.rotation = velocity.angle()
	
func switch_state(state: Ball.State, data: BallStateData = BallStateData.new()) -> void:
	if current_state != null:
		current_state.queue_free()
	current_state = state_factory.get_fresh_state(state)
	current_state.setup(self, data, player_detection_area, carrier, animation_player, ball_sprite, shot_particles)
	current_state.state_transition_requested.connect(switch_state.bind())
	current_state.name = "BallStateMachine: " + str(state)
	call_deferred("add_child", current_state)

func apply_impulse(impulse: Vector2) -> void:
	## 直接施加速度冲量（用于带球触球）
	velocity = impulse

func shoot(shot_velocity : Vector2) -> void:
	velocity = shot_velocity
	carrier = null
	switch_state(Ball.State.SHOT)

func tumble(tumble_velocity: Vector2, p_kicker: Player = null) -> void:
	velocity = tumble_velocity
	var kicker_ref := p_kicker if p_kicker != null else carrier
	carrier = null
	height_velocity = TUMBLE_HEIGHT_VELOCITY
	switch_state(Ball.State.KICKED, BallStateData.build()
		.set_lock_duration(DURATION_TUMBLE_LOCK)
		.set_kicker(kicker_ref))

func pass_to(destination: Vector2, lock_duration: int = DURATION_PASS_LOCK, p_kicker: Player = null) -> void:
	var direction := position.direction_to(destination)
	var distance := position.distance_to(destination)
	if distance < 0.1:
		return
	var intensity := BallTrajectoryScript.velocity_for_ground_target(position, destination, PitchConstants.BALL.KICKED_GROUND_FRICTION).length()
	velocity = intensity * direction
	height = 0.0
	height_velocity = 0.0
	if distance > DISTANCE_HIGH_PASS:
		height_velocity = PitchConstants.GRAVITY * distance / (1.85 * intensity)
	var kicker_ref := p_kicker if p_kicker != null else carrier
	carrier = null
	switch_state(Ball.State.KICKED, BallStateData.build()
		.set_lock_duration(lock_duration)
		.set_kicker(kicker_ref))

## === 三种传球 ===

func short_pass(destination: Vector2, p_kicker: Player, lock_duration: int = DURATION_PASS_LOCK) -> void:
	## 短传：贴地直线，速度适中，精准
	var distance := position.distance_to(destination)
	if distance < 0.1:
		return
	velocity = BallTrajectoryScript.velocity_for_ground_target(
		position, destination, PitchConstants.BALL.KICKED_GROUND_FRICTION)
	height = 0.0
	height_velocity = 0.0
	carrier = null
	switch_state(State.KICKED, BallStateData.build()
		.set_lock_duration(lock_duration)
		.set_kicker(p_kicker))

func long_pass(destination: Vector2, p_kicker: Player, power: float = 1.0, lock_duration: int = DURATION_PASS_LOCK) -> void:
	## 长传：高空抛物线，距离远
	var distance := position.distance_to(destination)
	if distance < 0.1:
		return
	power = clamp(power, 0.3, 1.5)
	var air_friction := PitchConstants.BALL.KICKED_GROUND_FRICTION \
		* PitchConstants.BALL.KICKED_AIR_FRICTION_MULT
	var travel_speed := lerpf(150.0, 260.0, (power - 0.3) / 1.2)
	var flight_time := distance / travel_speed
	velocity = BallTrajectoryScript.velocity_for_ground_target_at_time(
		position, destination, air_friction, flight_time)
	height = 0.0
	# Launch and landing share the selected flight time, so the horizontal solver
	# and vertical arc reach the receiving area together.
	height_velocity = PitchConstants.GRAVITY * flight_time * 0.5
	carrier = null
	switch_state(State.KICKED, BallStateData.build()
		.set_lock_duration(lock_duration)
		.set_kicker(p_kicker))

func through_pass(destination: Vector2, p_kicker: Player, power: float = 1.0, lock_duration: int = DURATION_PASS_LOCK) -> void:
	## 直塞：贴地快速直线，穿透力强
	var distance := position.distance_to(destination)
	if distance < 0.1:
		return
	power = clamp(power, 0.7, 1.3)
	var travel_speed := lerpf(160.0, 280.0, (power - 0.7) / 0.6)
	velocity = BallTrajectoryScript.velocity_for_ground_target_at_time(
		position, destination, PitchConstants.BALL.KICKED_GROUND_FRICTION, distance / travel_speed)
	height = 0.0
	height_velocity = 0.0
	carrier = null
	switch_state(State.KICKED, BallStateData.build()
		.set_lock_duration(lock_duration)
		.set_kicker(p_kicker))

## === 守门员相关 ===

func save_by(goalie: Player, direction: Vector2, speed_factor: float = 0.4) -> void:
	## 被门将扑出：球改变方向并减速
	velocity = direction * velocity.length() * speed_factor
	if height < 5.0:
		height_velocity = 240.0  ## px/s，低球扑救后向上弹起
	carrier = null
	switch_state(State.SAVED, BallStateData.build().set_kicker(goalie))

func deflect_by(deflector: Player, new_velocity: Vector2) -> void:
	## 折射：球碰到身体改变方向
	velocity = new_velocity
	carrier = null
	switch_state(State.DEFLECTED, BallStateData.build().set_kicker(deflector))

func hold_by_goalkeeper(goalie: Player) -> void:
	if not can_goalkeeper_collect(goalie):
		return
	_hold_by_goalkeeper(goalie)

func can_goalkeeper_collect(goalie: Player) -> bool:
	return _goalkeeper_interaction(goalie, false).get("kind", -1) \
		== BallInteractionResolverScript.Kind.COLLECT

func goalkeeper_interact(goalie: Player, allow_deflect: bool = true) -> void:
	var resolved := _goalkeeper_interaction(goalie, allow_deflect)
	if resolved.is_empty():
		return
	if int(resolved.kind) == BallInteractionResolverScript.Kind.COLLECT:
		_hold_by_goalkeeper(goalie)
	elif int(resolved.kind) == BallInteractionResolverScript.Kind.DEFLECT:
		var normal := (position - goalie.position).normalized()
		if normal == Vector2.ZERO:
			normal = -velocity.normalized()
		deflect_by(goalie, BallTrajectoryScript.bounce_velocity(velocity, normal, 0.4))

func _goalkeeper_interaction(goalie: Player, allow_deflect: bool) -> Dictionary:
	if goalie == null or not can_be_picked_up_by(goalie):
		return {}
	var goal_center := goalie.own_goal.get_center_target_position()
	var area_extent := PitchConstants.AI.GOALIE_RUSH_OUT_DISTANCE
	var in_penalty_area := absf(position.x - goal_center.x) <= area_extent \
		and absf(position.y - goal_center.y) <= area_extent
	var teammate_carrier := carrier != null and carrier != goalie and carrier.country == goalie.country
	var intent := GoalkeeperInteractionPolicyScript.resolve(goalie.jersey_number, {
		"in_penalty_area": in_penalty_area,
		"release_locked": is_recapture_locked_for(goalie),
		"teammate_carrier": teammate_carrier,
		"height": height,
		"speed": velocity.length(),
		"distance": goalie.position.distance_to(position),
		"allow_deflect": allow_deflect,
	})
	return BallInteractionResolverScript.resolve([intent]) if not intent.is_empty() else {}

func _hold_by_goalkeeper(goalie: Player) -> void:
	## 门将抱住球
	# 扑救时球状态和门将动作状态可能在同一帧同时报告接球。
	# 保持该操作幂等，避免旧 HELD 节点退出时清掉新状态的 carrier。
	if carrier == goalie and current_state is BallStateHeldByGoalkeeper:
		return
	carrier = goalie
	switch_state(State.HELD_BY_GOALKEEPER)

func release_with_throw(target_pos: Vector2) -> void:
	## 门将手抛球发球
	if current_state == null:
		return
	current_state.release_with_throw(target_pos)

func release_with_kick(target_pos: Vector2) -> void:
	## 门将大脚开球
	if current_state == null:
		return
	current_state.release_with_kick(target_pos)

func lock_recapture_for(context_player: Player, duration_ms: int) -> void:
	## 仅阻止发球队员本人立即重新获得球权，不影响其他球员接球。
	_recapture_lock_player = context_player
	_recapture_lock_until_ms = GameManager.get_match_time_ms() + duration_ms

func is_recapture_locked_for(context_player: Player) -> bool:
	if GameManager.get_match_time_ms() >= _recapture_lock_until_ms:
		_recapture_lock_player = null
		_recapture_lock_until_ms = 0
		return false
	return context_player == _recapture_lock_player

func clear_recapture_lock() -> void:
	_recapture_lock_player = null
	_recapture_lock_until_ms = 0

func can_be_picked_up_by(context_player: Player) -> bool:
	if not _pickup_enabled:
		return false
	if not _pickup_country.is_empty():
		if GameManager.get_match_time_ms() >= _pickup_country_until_ms:
			_clear_pickup_country_lock()
		elif context_player.country != _pickup_country:
			return false
	return true

func is_pickup_enabled() -> bool:
	return _pickup_enabled

func prepare_for_kickoff() -> void:
	## 中场/进球重置期间固定足球，直到正式开球前不允许任何球员获得球权。
	position = spawn_position
	velocity = Vector2.ZERO
	height = 0.0
	height_velocity = 0.0
	carrier = null
	clear_recapture_lock()
	_clear_pickup_country_lock()
	_pickup_enabled = false
	switch_state(State.FREEFORM)

func start_kickoff(kicker: Player) -> void:
	## 确定性地把中圈球权交给开球队，避免对称站位造成随机归属。
	if not is_instance_valid(kicker):
		return
	position = spawn_position
	velocity = Vector2.ZERO
	height = 0.0
	height_velocity = 0.0
	carrier = null
	_pickup_enabled = true
	_pickup_country = kicker.country
	_pickup_country_until_ms = GameManager.get_match_time_ms() + KICKOFF_TEAM_LOCK_MS
	carrier = kicker
	switch_state(State.DRIBBLING)

func _clear_pickup_country_lock() -> void:
	_pickup_country = ""
	_pickup_country_until_ms = 0

func stop() -> void:
	velocity = Vector2.ZERO

func place_at(pos: Vector2) -> void:
	## Place ball at given position and switch to FREEFORM (for offside/free-kick resets)
	position = pos
	velocity = Vector2.ZERO
	height = 0.0
	height_velocity = 0.0
	carrier = null
	clear_recapture_lock()
	_pickup_enabled = true
	_clear_pickup_country_lock()
	switch_state(State.FREEFORM)


func can_air_interact() -> bool:
	return current_state != null and current_state.can_air_interact()

func is_ball_free() -> bool:
	## 球是否处于可被抢断的"离脚"窗口（带球步点系统）
	return current_state != null and current_state.is_ball_free()

## === 落地预测 API（解析式）===

func predict_landing_time() -> float:
	## 预测球落地所需时间（秒）。
	## 如果球已经在地面或正在上升且高度>0，返回 0（已落地）或上升到最高点再下落的总时间。
	## 使用闭式解：h + v0*t - 0.5*g*t² = 0
	if height <= 0.0 and height_velocity <= 0.0:
		return 0.0
	var g := PitchConstants.GRAVITY
	var h := height
	var v0 := height_velocity
	# 解 t = (v0 + sqrt(v0^2 + 2gh)) / g
	var discriminant := v0 * v0 + 2.0 * g * h
	if discriminant < 0.0:
		return 0.0
	var t := (v0 + sqrt(discriminant)) / g
	return max(t, 0.0)

func predict_landing_position() -> Vector2:
	## 预测球落地时的水平位置。
	## 简化假设：水平方向速度恒定（忽略空气阻力，M1 精度足够）。
	## 对于 AI 决策和落点提示已经够用。
	if height <= 0.0 and height_velocity <= 0.0:
		return position
	var t_land := predict_landing_time()
	# 水平方向匀速近似
	return position + velocity * t_land

func predict_position_at_time(t: float) -> Vector2:
	## 预测 t 秒后球的水平位置（匀速近似）。
	## 用于 AI 预判截球时机。
	return position + velocity * t

func predict_height_at_time(t: float) -> float:
	## 预测 t 秒后球的高度。
	## h(t) = h0 + v0*t - 0.5*g*t²
	var h := height + height_velocity * t - 0.5 * PitchConstants.GRAVITY * t * t
	return max(h, 0.0)

func can_air_connect(air_connect_min_height: float, air_connect_max_height: float) -> bool:
	return height >= air_connect_min_height and height <= air_connect_max_height

func is_headed_for_scoring_area(scoring_area: Area2D) -> bool:
	if not scoring_raycast.is_colliding():
		return false
	return scoring_raycast.get_collider() == scoring_area

func predict_goal_line_y(goal_x: float) -> float:
	## 预测球到达球门线（x=goal_x）时的 y 坐标
	## 使用匀速近似 + 摩擦力修正，返回球门线处的 y 值
	## 如果球不会到达球门线（速度不够或方向相反），返回 INF
	if abs(velocity.x) < 1.0:
		return INF

	var dx := goal_x - position.x
	# 球不是朝球门方向移动
	if dx * velocity.x <= 0:
		return INF

	# 估算到达球门线的时间（考虑地面摩擦减速）
	var speed_x: float = abs(velocity.x)
	var time_to_goal: float
	if friction_ground > 0.0:
		# v = v0 - a*t，s = v0*t - 0.5*a*t²
		# 简化：用平均速度估算时间
		var avg_speed: float = speed_x * 0.7  # 摩擦衰减后的平均速度近似
		time_to_goal = abs(dx) / max(avg_speed, 1.0)
	else:
		time_to_goal = abs(dx) / speed_x

	# 估算 y 方向的位移（考虑摩擦）
	var y_offset: float = velocity.y * time_to_goal * 0.7  # y 方向也有摩擦衰减
	return position.y + y_offset

func will_reach_goal_area(goal_x: float, goal_top_y: float, goal_bottom_y: float) -> bool:
	## 判断球是否会飞入球门范围内
	## goal_x: 球门线的 x 坐标
	## goal_top_y / goal_bottom_y: 球门上下沿的 y 坐标
	var goal_y: float = predict_goal_line_y(goal_x)
	if goal_y == INF:
		return false
	return goal_y >= goal_top_y and goal_y <= goal_bottom_y

func get_proximity_teammates_count(country: String) -> int:
	var players := player_proximity_area.get_overlapping_bodies()
	return players.filter(func(p: Player): return p.country == country).size()

func on_team_reset() -> void:
	prepare_for_kickoff()
