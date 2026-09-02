class_name ActorsContainer
extends Node2D

const DURATION_WEIGHT_CACHE := 200
const TeamTacticsScript := preload("res://utils/team_tactics.gd")
const PLAYER_PREFAB := preload("res://scenes/characters/player.tscn")
const SPARK_PREFAB := preload("res://scenes/spark/spark.tscn")

## === AI LOD 分级 ===
const LOD_CORE_COUNT := 3     ## 核心层人数（最近的 2-3 人，每 50ms 决策）
const LOD_MID_COUNT := 7      ## 中间层人数（中间的 6-8 人，每 200ms 决策）
## 远端 = 其余球员（每 1000ms 决策）

@export var ball : Ball
@export var goal_home : Goal
@export var goal_away : Goal

@onready var kickoffs : Node2D = %KickOffs
@onready var spawns : Node2D = %Spawns

var is_checking_for_kickoff_readiness := false
var squad_home : Array[Player] = []
var squad_away : Array[Player] = []
var time_since_last_cache_refresh := Time.get_ticks_msec()

func _init() -> void:
	GameEvents.team_reset.connect(on_team_reset.bind())
	GameEvents.kickoff_started.connect(on_kickoff_started.bind())
	GameEvents.impact_received.connect(on_impact_received.bind())
	GameEvents.ball_possession_stable.connect(_on_ball_possession_stable.bind())

func _ready() -> void:
	add_to_group("actors_container")
	squad_home = spawn_players(GameManager.current_match.country_home, goal_home)
	goal_home.initialize(GameManager.current_match.country_home)
	spawns.scale.x = -1
	kickoffs.scale.x = -1
	squad_away = spawn_players(GameManager.current_match.country_away, goal_away)
	goal_away.initialize(GameManager.current_match.country_away)
	setup_control_schemes()

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - time_since_last_cache_refresh > DURATION_WEIGHT_CACHE:
		time_since_last_cache_refresh = Time.get_ticks_msec()
		set_on_duty_weights()
	if is_checking_for_kickoff_readiness:
		check_for_kickoff_readiness()

func spawn_players(country: String, own_goal: Goal) -> Array[Player]:
	var player_nodes : Array[Player] = []
	var players := DataLoader.get_squad(country)
	var target_goal := goal_home if own_goal == goal_away else goal_away
	for i in players.size():
		var player_position := spawns.get_child(i).global_position as Vector2
		var player_data := players[i] as PlayerResource
		var kickoff_position := player_position
		if i > 4:
			kickoff_position = kickoffs.get_child(i - 5).global_position as Vector2
		var player := spawn_player(player_position, kickoff_position, own_goal, target_goal, player_data, country)
		player_nodes.append(player)
		add_child(player)
	return player_nodes

func spawn_player(player_position: Vector2, kickoff_position: Vector2, own_goal: Goal, target_goal: Goal, player_data: PlayerResource, country: String) -> Player:
	var player : Player = PLAYER_PREFAB.instantiate()
	player.initialize(player_position, kickoff_position, ball, own_goal, target_goal, player_data, country)
	player.swap_requested.connect(on_player_swap_request.bind())
	return player

func set_on_duty_weights() -> void:
	for squad in [squad_away, squad_home]:
		var opponents := squad_home if squad == squad_away else squad_away
		var cpu_players : Array[Player] = squad.filter(
			func(p: Player): return p.control_scheme == Player.ControlScheme.CPU and p.role != Player.Role.GOALIE
		)
		cpu_players.sort_custom(func(p1: Player, p2: Player):
			return p1.position.distance_squared_to(ball.position) < p2.position.distance_squared_to(ball.position))

		for i in range(cpu_players.size()):
			cpu_players[i].weight_on_duty_steering = 1 - ease(float(i)/10.0, 0.1)
			# 同时分配 LOD 级别：影响 AI 决策频率
			var lod_level: int
			if i < LOD_CORE_COUNT:
				lod_level = AIBehavior.LODLevel.CORE
			elif i < LOD_CORE_COUNT + LOD_MID_COUNT:
				lod_level = AIBehavior.LODLevel.MID
			else:
				lod_level = AIBehavior.LODLevel.FAR
			if cpu_players[i].current_ai_behavior != null:
				cpu_players[i].current_ai_behavior.set_lod_level(lod_level)
		_apply_defensive_tactics(squad, opponents)

func _apply_defensive_tactics(squad: Array[Player], opponents: Array[Player]) -> void:
	var is_defending := ball.carrier == null or ball.carrier.country != squad[0].country
	for player in squad:
		player.tactical_role = ""
		player.tactical_target = player.spawn_position
	if not is_defending:
		_apply_attacking_tactics(squad)
		return
	var player_data: Array[Dictionary] = []
	for player in squad:
		if player.role != Player.Role.GOALIE:
			player_data.append({"id": player.jersey_number, "position": player.position,
				"spawn_position": player.spawn_position})
	var defensive_goal := squad[0].own_goal.get_center_target_position()
	var assignments := TeamTacticsScript.build_defensive_assignments(
		player_data, ball.position, defensive_goal)
	for player in squad:
		if assignments.has(player.jersey_number):
			var assignment: Dictionary = assignments[player.jersey_number]
			player.tactical_role = str(assignment.role)
			player.tactical_target = assignment.target

func _apply_attacking_tactics(squad: Array[Player]) -> void:
	if ball.carrier == null:
		return
	var player_data: Array[Dictionary] = []
	for player in squad:
		if player.role != Player.Role.GOALIE:
			player_data.append({"id": player.jersey_number, "position": player.position,
				"spawn_position": player.spawn_position})
	var attacking_dir := 1 if ball.carrier.target_goal.position.x > ball.carrier.position.x else -1
	var assignments := TeamTacticsScript.build_attacking_assignments(
		player_data, ball.position, attacking_dir, ball.carrier.jersey_number)
	for player in squad:
		if assignments.has(player.jersey_number):
			var assignment: Dictionary = assignments[player.jersey_number]
			player.tactical_role = str(assignment.role)
			player.tactical_target = assignment.target
func on_player_swap_request(requester: Player) -> void:
	var squad := squad_home if requester.country == squad_home[0].country else squad_away
	var cpu_players : Array[Player] = squad.filter(
		func(p: Player): return p.control_scheme == Player.ControlScheme.CPU and p.role != Player.Role.GOALIE
	)
	if cpu_players.is_empty():
		return
	# 切换到离球最近的 CPU 队友（无条件，总能切换）
	cpu_players.sort_custom(func(p1: Player, p2: Player):
		return p1.position.distance_squared_to(ball.position) < p2.position.distance_squared_to(ball.position))
	var closest_cpu_to_ball : Player = cpu_players[0]
	var player_control_scheme := requester.control_scheme
	requester.set_control_scheme(Player.ControlScheme.CPU)
	closest_cpu_to_ball.set_control_scheme(player_control_scheme)

func check_for_kickoff_readiness() -> void:
	for squad in [squad_home, squad_away]:
		for player : Player in squad:
			if not player.is_ready_for_kickoff():
				return
	setup_control_schemes()
	is_checking_for_kickoff_readiness = false
	GameEvents.kickoff_ready.emit()
	
func setup_control_schemes() -> void:
	reset_control_schemes()
	var p1_country := GameManager.player_setup[0]
	if GameManager.is_coop():
		var player_squad := squad_home if squad_home[0].country == p1_country else squad_away
		# 控制最后两个进攻球员（通常是前锋）
		var last_idx := player_squad.size() - 1
		player_squad[last_idx - 1].set_control_scheme(Player.ControlScheme.P1)
		player_squad[last_idx].set_control_scheme(Player.ControlScheme.P2)
	elif GameManager.is_single_player():
		var player_squad := squad_home if squad_home[0].country == p1_country else squad_away
		# 控制最后一个球员（中锋/主要前锋）
		var last_idx := player_squad.size() - 1
		player_squad[last_idx].set_control_scheme(Player.ControlScheme.P1)
	else: # versus
		var p1_squad := squad_home if squad_home[0].country == p1_country else squad_away
		var p2_squad := squad_home if p1_squad == squad_away else squad_away
		var p1_last := p1_squad.size() - 1
		var p2_last := p2_squad.size() - 1
		p1_squad[p1_last].set_control_scheme(Player.ControlScheme.P1)
		p2_squad[p2_last].set_control_scheme(Player.ControlScheme.P2)

func reset_control_schemes() -> void:
	for squad in [squad_home, squad_away]:
		for player: Player in squad:
			player.set_control_scheme(Player.ControlScheme.CPU)

func on_team_reset() -> void:
	is_checking_for_kickoff_readiness = true

func on_kickoff_started() -> void:
	var kickoff_country := GameManager.current_match.country_home
	if GameManager.current_state != null \
			and GameManager.current_state.state_data != null \
			and not GameManager.current_state.state_data.country_scored_on.is_empty():
		kickoff_country = GameManager.current_state.state_data.country_scored_on

	var squad := squad_home if squad_home[0].country == kickoff_country else squad_away
	var candidates : Array[Player] = squad.filter(
		func(p: Player): return p.role != Player.Role.GOALIE
	)
	candidates.sort_custom(func(p1: Player, p2: Player):
		return p1.position.distance_squared_to(ball.spawn_position) \
			< p2.position.distance_squared_to(ball.spawn_position))
	if candidates.is_empty():
		return
	ball.start_kickoff(candidates[0])

func on_impact_received(impact_position: Vector2, _is_high_impact: bool) -> void:
	var spark := SPARK_PREFAB.instantiate()
	spark.position = impact_position
	add_child(spark)

## === 控球权自动切换（PossessionManager）===

func _on_ball_possession_stable(player: Player) -> void:
	## 己方球员稳定控球（宽限期结束后）→ 自动切换控制到该球员
	## 修复：从监听 ball_possessed_by 改为 ball_possession_stable
	## 避免在球权不稳定时过早切换球员
	## 规则：
	## - 如果获得球权的是己方人类玩家，不切换（已经是人类控制）
	## - 如果获得球权的是己方 CPU 球员，把控制切给它
	## - 双人合作模式：P1/P2 各占一个球员，不抢夺
	var p1_country := GameManager.player_setup[0]
	var p2_country := GameManager.player_setup[1]
	var is_p1_team := player.country == p1_country
	var is_p2_team := player.country == p2_country and not p2_country.is_empty()

	if not is_p1_team and not is_p2_team:
		return  # 对方球队获得球权，不管

	# 找出该球队中所有被人类控制的非门将球员
	var squad := squad_home if player.country == squad_home[0].country else squad_away
	var human_players : Array[Player] = squad.filter(
		func(p: Player): return p.control_scheme != Player.ControlScheme.CPU and p.role != Player.Role.GOALIE
	)

	if human_players.is_empty():
		return  # 这支队伍没有人类玩家（理论上不应该走到这里）

	# 情况 1：获得球权的球员已经是人类控制 → 不用切
	for hp in human_players:
		if hp == player:
			return

	# 情况 2：单人模式 → 把 P1 控制切给获球队员
	if GameManager.is_single_player() and is_p1_team:
		_swap_control_to(player, Player.ControlScheme.P1, squad)
		return

	# 情况 3：双人对战 → 各队各管各的
	if not GameManager.is_coop():
		if is_p1_team:
			_swap_control_to(player, Player.ControlScheme.P1, squad)
		elif is_p2_team:
			_swap_control_to(player, Player.ControlScheme.P2, squad)
		return

	# 情况 4：双人合作 → 两人都在同一队
	# 规则：距离球最远的那个人类玩家切换过去（保留离球近的那个）
	if GameManager.is_coop() and human_players.size() >= 2:
		# 找出离球更远的人类玩家，让他切换
		var farthest_human: Player = null
		var farthest_dist := -1.0
		for hp in human_players:
			var dist := hp.position.distance_squared_to(ball.position)
			if dist > farthest_dist:
				farthest_dist = dist
				farthest_human = hp
		if farthest_human != null and farthest_human != player:
			var scheme := farthest_human.control_scheme
			farthest_human.set_control_scheme(Player.ControlScheme.CPU)
			player.set_control_scheme(scheme)

func _swap_control_to(target: Player, scheme: int, squad: Array[Player]) -> void:
	## 将指定控制方案切换到目标球员
	# 先找到当前持有该方案的球员
	var current_holder: Player = null
	for p in squad:
		if p.control_scheme == scheme and p.role != Player.Role.GOALIE:
			current_holder = p
			break
	if current_holder == target:
		return  # 已经是这个人了
	if current_holder != null:
		current_holder.set_control_scheme(Player.ControlScheme.CPU)
	target.set_control_scheme(scheme)

## === 越位判定 ===

func check_pass_offside(passer: Player) -> Dictionary:
	## 判断传球是否造成越位，返回 OffsideJudge 的结果字典
	var attacker_squad := squad_home if passer.country == squad_home[0].country else squad_away
	var defender_squad := squad_away if attacker_squad == squad_home else squad_home

	# 进攻方向：根据传球者的 target_goal 位置推导（不受半场交换影响）
	var attacking_dir_x := 1 if passer.target_goal.position.x > passer.position.x else -1

	return OffsideJudge.check_offside_at_pass(
		passer,
		attacker_squad,
		defender_squad,
		ball.position,
		attacking_dir_x,
		PITCH_CENTER_X
	)

## === 半场交换场地 ===

const PITCH_CENTER_X := PitchConstants.CENTER_X  ## 球场中线 x 坐标（引用统一常量）

func swap_sides() -> void:
	## 半场结束时交换场地：所有球员以中线为轴左右镜像
	## 同时交换 own_goal / target_goal 引用，球员切到 RESETING 跑回开球位置
	for squad in [squad_home, squad_away]:
		for player in squad:
			# 镜像归位点
			player.spawn_position.x = PITCH_CENTER_X * 2 - player.spawn_position.x
			player.kickoff_position.x = PITCH_CENTER_X * 2 - player.kickoff_position.x
			# 交换球门引用（AI 和射门方向依赖此引用）
			var old_own: Goal = player.own_goal
			player.own_goal = player.target_goal
			player.target_goal = old_own
			# 翻转默认朝向
			player.heading.x *= -1
			# 所有球员切到 RESETING 状态，跑回开球位置
			player.switch_state(Player.State.RESETING,
				PlayerStateData.build().set_reset_position(player.kickoff_position))

	# 中场期间固定在标准开球点并禁止任何球员提前获得球权。
	ball.prepare_for_kickoff()

	# 重置控球权统计
	GameManager.reset_possession()


func handle_offside(offender: Player, offside_position: Vector2) -> void:
	## 处理越位判罚：球变为自由球，放在越位位置
	GameEvents.offside_called.emit(offender, offside_position)
	# 让球停在越位位置（FREEFORM 状态，速度为 0）
	ball.place_at(offside_position)
	SoundPlayer.play(SoundPlayer.Sound.WHISTLE)
