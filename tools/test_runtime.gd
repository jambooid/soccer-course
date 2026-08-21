extends Node2D
## 运行时错误检测：启动完整游戏流程并捕获所有错误

var phase := 0
var phase_timer := 0.0
var soccer_game = null

const MAIN_SCENE_PATH = "res://scenes/soccer_game.tscn"

func _ready():
	print("=== Runtime Error Detection Test ===")
	call_deferred("_start")

func _start():
	_load_main_scene()

func _process(delta):
	phase_timer += delta

	match phase:
		1:
			if phase_timer > 1.5:
				print("\n--- Phase 1: Main Menu ---")
				_go_to_team_selection()
				phase = 2
				phase_timer = 0.0

		2:
			if phase_timer > 1.5:
				print("\n--- Phase 2: Setup match and enter game ---")
				_setup_and_start_match()
				phase = 3
				phase_timer = 0.0

		3:
			# 等待游戏场景加载和 RESET -> KICKOFF 转换
			if phase_timer > 3.0:
				print("\n--- Phase 3: Kickoff state ---")
				_check_game_state()
				_check_players_count()
				_check_ball_basic()
				# 直接进入比赛状态（模拟开球）
				_start_play()
				phase = 4
				phase_timer = 0.0

		4:
			# 运行 10 秒比赛
			if phase_timer > 10.0:
				print("\n--- Phase 4: After 10s Gameplay ---")
				_check_game_state()
				_check_players_detailed()
				_check_ball_detailed()
				phase = 5
				phase_timer = 0.0

		5:
			# 运行到 30 秒
			if phase_timer > 20.0:
				print("\n--- Phase 5: After 30s Gameplay ---")
				_check_game_state()
				_check_players_detailed()
				_check_ball_detailed()
				phase = 6
				phase_timer = 0.0

		6:
			# 运行到 60 秒（半场结束）
			if phase_timer > 30.0:
				print("\n--- Phase 6: After 60s (should be halftime) ---")
				_check_game_state()
				_check_players_detailed()
				_check_ball_detailed()
				_finalize()

func _load_main_scene():
	print("Loading main scene: ", MAIN_SCENE_PATH)
	var packed = load(MAIN_SCENE_PATH)
	if packed == null:
		print("[FATAL] Cannot load main scene!")
		get_tree().quit(1)
		return
	soccer_game = packed.instantiate()
	add_child(soccer_game)
	phase = 1
	print("[OK] Main scene loaded")

func _go_to_team_selection():
	print("Transitioning to TEAM_SELECTION...")
	if soccer_game and soccer_game.has_method("switch_screen"):
		var sd = load("res://scenes/screens/screen_data.gd").new()
		soccer_game.switch_screen(soccer_game.ScreenType.TEAM_SELECTION, sd)
		print("[OK] Transitioning to team selection")

func _setup_and_start_match():
	GameManager.player_setup = ["FRANCE", "GERMANY"]
	var match_class = load("res://scenes/screens/tournament/match.gd")
	GameManager.current_match = match_class.new("GERMANY", "FRANCE")
	print("Match created: ", GameManager.current_match.country_home, " vs ", GameManager.current_match.country_away)
	print("player_setup: ", GameManager.player_setup)

	if soccer_game and soccer_game.has_method("switch_screen"):
		var sd = load("res://scenes/screens/screen_data.gd").new()
		soccer_game.switch_screen(soccer_game.ScreenType.IN_GAME, sd)
		print("[OK] Transitioning to IN_GAME")

func _start_play():
	# 模拟开球：发出哨声并切换到比赛状态
	print("Starting play (transition to FIRST_HALF)...")
	SoundPlayer.play(SoundPlayer.Sound.WHISTLE)
	var gsd = load("res://scenes/game_manager/game_states/game_state_data.gd")
	GameManager.switch_state(GameManager.State.FIRST_HALF, gsd.build().set_half(1))
	GameEvents.kickoff_started.emit()
	print("[OK] Play started")

func _get_actors():
	return get_tree().get_first_node_in_group("actors_container")

func _check_game_state():
	print("  GameManager state:")
	if GameManager.current_match:
		var m = GameManager.current_match
		print("    Match: ", m.country_home, " vs ", m.country_away)
		print("    Score: ", m.goals_home, " - ", m.goals_away)
		print("    Winner: '", m.winner, "'")
	else:
		print("    current_match: null")
	print("    current_half: ", GameManager.current_half)
	print("    time_left: ", GameManager.time_left)
	if GameManager.current_state:
		print("    game_state: ", GameManager.current_state.name)
	else:
		print("    game_state: null")
	print("    possession_home: ", GameManager.possession_home)
	print("    possession_away: ", GameManager.possession_away)

func _check_players_count():
	var actors = _get_actors()
	if not actors:
		print("\n  Players: ActorsContainer not found")
		return
	var home_count = actors.squad_home.size() if actors.squad_home else 0
	var away_count = actors.squad_away.size() if actors.squad_away else 0
	print("\n  Players: home=", home_count, " away=", away_count, " total=", home_count + away_count)

func _check_players_detailed():
	var actors = _get_actors()
	if not actors:
		print("\n  Players: ActorsContainer not found")
		return

	var all_players: Array = []
	all_players.append_array(actors.squad_home)
	all_players.append_array(actors.squad_away)
	print("\n  Players (", all_players.size(), "):")
	var state_counts = {}
	var null_count = 0
	for p in all_players:
		if p == null or not is_instance_valid(p):
			null_count += 1
			continue
		if p.current_state:
			var sname = p.current_state.name
			state_counts[sname] = state_counts.get(sname, 0) + 1
	if null_count > 0:
		print("    null/invalid: ", null_count)
	print("  Player states:")
	for s in state_counts.keys():
		print("    ", s, ": ", state_counts[s])

func _check_ball_basic():
	var actors = _get_actors()
	if not actors or not actors.ball:
		print("\n  Ball: NOT FOUND")
		return
	var b = actors.ball
	print("\n  Ball: pos=", b.position, " vel=", b.velocity)

func _check_ball_detailed():
	var actors = _get_actors()
	if not actors or not actors.ball:
		print("\n  Ball: NOT FOUND")
		return
	var b = actors.ball
	print("\n  Ball:")
	print("    pos: ", b.position)
	print("    vel: ", b.velocity)
	print("    speed: ", b.velocity.length())
	print("    height: ", b.height)
	var carrier_name = "none"
	if b.carrier:
		carrier_name = b.carrier.name
	print("    carrier: ", carrier_name)
	if b.current_state:
		print("    state: ", b.current_state.name)

func _finalize():
	print("\n===============================================")
	print("=== TEST COMPLETE ===")
	print("Check output above for SCRIPT ERROR lines.")
	print("===============================================")
	get_tree().quit(0)
