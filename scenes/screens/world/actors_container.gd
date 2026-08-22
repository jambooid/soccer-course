class_name ActorsContainer
extends Node2D

const DURATION_WEIGHT_CACHE := 200
const PLAYER_PREFAB := preload("res://scenes/characters/player.tscn")
const SPARK_PREFAB := preload("res://scenes/spark/spark.tscn")

## === 控球权自动切换（PossessionManager）===
const SWAP_COOLDOWN_MS := 400          ## 自动切换冷却时间，防止频繁跳变
const DEFENSE_SWAP_DIST_THRESHOLD := 25.0  ## 防守时切换的距离阈值（当前球员比最近的远多少才切）

@export var ball : Ball
@export var goal_home : Goal
@export var goal_away : Goal

@onready var kickoffs : Node2D = %KickOffs
@onready var spawns : Node2D = %Spawns

var is_checking_for_kickoff_readiness := false
var squad_home : Array[Player] = []
var squad_away : Array[Player] = []
var time_since_last_cache_refresh := Time.get_ticks_msec()
var _last_auto_swap_ms := 0  ## 上次自动切换时间（冷却用）

func _init() -> void:
	GameEvents.team_reset.connect(on_team_reset.bind())
	GameEvents.impact_received.connect(on_impact_received.bind())
	GameEvents.ball_possessed_by.connect(_on_ball_possessed.bind())

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
		_auto_swap_defender()  ## 防守时自动切换到离球最近的球员
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
		var cpu_players : Array[Player] = squad.filter(
			func(p: Player): return p.control_scheme == Player.ControlScheme.CPU and p.role != Player.Role.GOALIE
		)
		cpu_players.sort_custom(func(p1: Player, p2: Player):
			return p1.position.distance_squared_to(ball.position) < p2.position.distance_squared_to(ball.position))

		for i in range(cpu_players.size()):
			cpu_players[i].weight_on_duty_steering = 1 - ease(float(i)/10.0, 0.1)
	
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

func on_impact_received(impact_position: Vector2, _is_high_impact: bool) -> void:
	var spark := SPARK_PREFAB.instantiate()
	spark.position = impact_position
	add_child(spark)

## === 控球权自动切换（PossessionManager）===

func _on_ball_possessed(player: Player) -> void:
	## 己方球员获得球权 → 自动切换控制到该球员
	## 规则：
	## - 如果获得球权的是己方人类玩家，不切换（已经是人类控制）
	## - 如果获得球权的是己方 CPU 球员，把控制切给它
	## - 双人合作模式：P1/P2 各占一个球员，不抢夺
	if Time.get_ticks_msec() - _last_auto_swap_ms < SWAP_COOLDOWN_MS:
		return

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
			_last_auto_swap_ms = Time.get_ticks_msec()

func _auto_swap_defender() -> void:
	## 防守时自动切换：球在对方脚下或自由球时，控制离球最近的己方球员
	## 每 200ms 评估一次（和 weight cache 同步）
	if Time.get_ticks_msec() - _last_auto_swap_ms < SWAP_COOLDOWN_MS:
		return

	var p1_country := GameManager.player_setup[0]
	var p2_country := GameManager.player_setup[1]

	# 球在己方脚下 → 不切换（由 _on_ball_possessed 处理）
	if ball.carrier != null and ball.carrier.country == p1_country:
		return
	if not p2_country.is_empty() and ball.carrier != null and ball.carrier.country == p2_country:
		return

	# 对 P1 球队评估
	if not p1_country.is_empty():
		var p1_squad := squad_home if squad_home[0].country == p1_country else squad_away
		_auto_swap_defender_for_scheme(p1_squad, Player.ControlScheme.P1)

	# 对 P2 球队评估（仅对战模式）
	if not p2_country.is_empty() and not GameManager.is_coop():
		var p2_squad := squad_home if squad_home[0].country == p2_country else squad_away
		_auto_swap_defender_for_scheme(p2_squad, Player.ControlScheme.P2)

func _auto_swap_defender_for_scheme(squad: Array[Player], scheme: int) -> void:
	## 对指定球队的指定控制方案进行防守自动切换
	# 找到当前被该方案控制的球员（非门将）
	var current_player: Player = null
	for p in squad:
		if p.control_scheme == scheme and p.role != Player.Role.GOALIE:
			current_player = p
			break
	if current_player == null:
		return

	# 找到离球最近的非门将球员
	var field_players : Array[Player] = squad.filter(
		func(p: Player): return p.role != Player.Role.GOALIE
	)
	if field_players.size() <= 1:
		return
	field_players.sort_custom(func(p1: Player, p2: Player):
		return p1.position.distance_squared_to(ball.position) < p2.position.distance_squared_to(ball.position))

	var closest := field_players[0]
	if closest == current_player:
		return  # 已经是最近的，不用切

	# 距离差超过阈值才切换，避免来回跳
	var current_dist := current_player.position.distance_to(ball.position)
	var closest_dist := closest.position.distance_to(ball.position)
	if current_dist - closest_dist < DEFENSE_SWAP_DIST_THRESHOLD:
		return

	# 不能切到已经被另一个人类玩家控制的球员（合作模式）
	if closest.control_scheme != Player.ControlScheme.CPU:
		return

	# 执行切换
	current_player.set_control_scheme(Player.ControlScheme.CPU)
	closest.set_control_scheme(scheme)
	_last_auto_swap_ms = Time.get_ticks_msec()

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
	_last_auto_swap_ms = Time.get_ticks_msec()

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

	# 球重置到中圈
	ball.position = Vector2(PITCH_CENTER_X, ball.position.y)
	ball.velocity = Vector2.ZERO
	if ball.has_method("set_state_freeform"):
		ball.set_state_freeform()

	# 重置控球权统计
	GameManager.reset_possession()


func handle_offside(offender: Player, offside_position: Vector2) -> void:
	## 处理越位判罚：球变为自由球，放在越位位置
	GameEvents.offside_called.emit(offender, offside_position)
	# 让球停在越位位置（FREEFORM 状态，速度为 0）
	ball.place_at(offside_position)
	SoundPlayer.play(SoundPlayer.Sound.WHISTLE)

