extends Node

const DURATION_IMPACT_PAUSE := 100
const DURATION_GAME_SEC := 2 * 60

enum State {IN_PLAY, SCORED, RESET, KICKOFF, OVERTIME, GAMEOVER}

var current_match : Match = null
var current_state : GameState = null
var player_setup : Array[String] = ["FRANCE", ""]
var state_factory := GameStateFactory.new()
var time_left : float
var time_since_paused := Time.get_ticks_msec()

## === 控球权管理 ===
var possession_home : float = 0.0
var possession_away : float = 0.0
var possession_country : String = ""
var possession_last_switch_ms := 0

func _init() -> void:
	process_mode = ProcessMode.PROCESS_MODE_ALWAYS

func _ready() -> void:
	GameEvents.impact_received.connect(on_impact_received.bind())
	GameEvents.ball_possessed_by.connect(on_ball_possessed_by.bind())
	GameEvents.ball_released.connect(on_ball_released.bind())

func _process(_delta: float) -> void:
	if get_tree().paused and Time.get_ticks_msec() - time_since_paused > DURATION_IMPACT_PAUSE:
		get_tree().paused = false

func start_game() -> void:
	time_left = DURATION_GAME_SEC
	switch_state(State.RESET)

func switch_state(state: State, data: GameStateData = GameStateData.new()) -> void:
	if current_state != null:
		current_state.queue_free()
	current_state = state_factory.get_fresh_state(state)
	current_state.setup(self, data)
	current_state.state_transition_requested.connect(switch_state.bind())
	current_state.name = "GameStateMachine: " + str(state)
	call_deferred("add_child", current_state)
	
func is_coop() -> bool:
	return player_setup[0] == player_setup[1]

func is_single_player() -> bool:
	return player_setup[1].is_empty()

func is_time_up() -> bool:
	return time_left <= 0

func get_winner_country() -> String:
	assert(not current_match.is_tied())
	return current_match.winner

func increase_score(country_scored_on: String) -> void:
	current_match.increase_score(country_scored_on)
	GameEvents.score_changed.emit()

func on_impact_received(_impact_position: Vector2, is_high_impact: bool) -> void:
	if is_high_impact:
		time_since_paused = Time.get_ticks_msec()
		get_tree().paused = true

## === 控球权管理方法 ===

func on_ball_possessed_by(player: Player) -> void:
	if current_match == null:
		return
	_accumulate_possession()
	var new_country := player.country
	if new_country != possession_country:
		possession_country = new_country
		GameEvents.possession_changed.emit(new_country)
	possession_last_switch_ms = Time.get_ticks_msec()

func on_ball_released() -> void:
	# 球被释放时先累计当前控球方的时间
	_accumulate_possession()
	possession_country = ""
	possession_last_switch_ms = 0

func _accumulate_possession() -> void:
	if possession_country == "" or possession_last_switch_ms == 0:
		return
	var elapsed := (Time.get_ticks_msec() - possession_last_switch_ms) / 1000.0
	if current_match == null:
		return
	if possession_country == current_match.country_home:
		possession_home += elapsed
	else:
		possession_away += elapsed

func set_possession(country: String) -> void:
	## 显式设置控球方（供 ball.carrier 变化时主动调用）
	_accumulate_possession()
	possession_country = country
	possession_last_switch_ms = Time.get_ticks_msec()

func get_possession_ratio(country: String) -> float:
	## 获取指定球队的控球率（0.0-1.0）
	var total := possession_home + possession_away
	if total <= 0:
		return 0.5
	if country == current_match.country_home:
		return possession_home / total
	elif country == current_match.country_away:
		return possession_away / total
	return 0.0

func reset_possession() -> void:
	## 重置控球统计（开球时调用）
	possession_home = 0.0
	possession_away = 0.0
	possession_country = ""
	possession_last_switch_ms = 0
