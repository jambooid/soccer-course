extends SceneTree
## 深入测试：加载主场景，程序化推进游戏流程
## 用法: godot --headless --path . -s res://tools/test_gameplay.gd

var phase := 0
var phase_timer := 0.0
var soccer_game = null
var main_scene_packed = null

const MAIN_SCENE_PATH = "res://scenes/soccer_game.tscn"

func _init():
	print("=== Gameplay Deep Test ===")

func _process(delta):
	phase_timer += delta

	match phase:
		0:
			# 阶段 0: 加载主场景
			if phase_timer > 0.3:
				_load_main_scene()
				phase = 1
				phase_timer = 0.0

		1:
			# 阶段 1: 主菜单
			if phase_timer > 1.0:
				print("\n--- Phase 1: Main Menu ---")
				_print_screens()
				_go_to_team_selection()
				phase = 2
				phase_timer = 0.0

		2:
			# 阶段 2: 选队后直接进入比赛
			if phase_timer > 1.0:
				print("\n--- Phase 2: Team Selection → Start Match ---")
				_print_screens()
				_setup_and_start_match()
				phase = 3
				phase_timer = 0.0

		3:
			# 阶段 3: 比赛初期检查
			if phase_timer > 2.0:
				print("\n--- Phase 3: Early Match ---")
				_check_game_state()
				phase = 4
				phase_timer = 0.0

		4:
			# 阶段 4: 运行 15 秒看实时比赛
			if phase_timer > 15.0:
				print("\n--- Phase 4: After 15s Gameplay ---")
				_check_game_state()
				_check_player_states()
				_finalize()

func _load_main_scene():
	print("Loading main scene: ", MAIN_SCENE_PATH)
	main_scene_packed = load(MAIN_SCENE_PATH)
	if main_scene_packed == null:
		print("[FATAL] Cannot load main scene!")
		quit(1)
		return
	soccer_game = main_scene_packed.instantiate()
	get_root().add_child(soccer_game)
	print("[OK] Main scene loaded and added to root")

func _print_screens():
	if not soccer_game:
		return
	var screen_found = false
	for child in soccer_game.get_children():
		if child.has_signal("screen_transition_requested") or child.has_method("setup"):
			print("  Screen: ", child.name, " (", child.get_class(), ")")
			if child.script:
				print("    Path: ", child.script.resource_path)
			screen_found = true
	if not screen_found:
		print("  No screen found. Children of soccer_game:")
		for child in soccer_game.get_children():
			print("    - ", child.name, " (", child.get_class(), ")")

func _go_to_team_selection():
	print("  Transitioning to TEAM_SELECTION...")
	if soccer_game.has_method("switch_screen"):
		var sd = load("res://scenes/screens/screen_data.gd").new()
		# 获取 ScreenType 枚举值
		var team_sel_type = soccer_game.SCREENTYPE_TEAM_SELECTION if "SCREENTYPE_TEAM_SELECTION" in soccer_game else 1
		# 试试直接用索引
		var screen_type = soccer_game.get("ScreenType") if soccer_game.has("ScreenType") else null
		if screen_type:
			team_sel_type = screen_type.TEAM_SELECTION
		soccer_game.switch_screen.call_deferred(team_sel_type, sd)
		print("  Done")
	else:
		print("  No switch_screen method")

func _setup_and_start_match():
	print("  Setting up match: FRANCE vs BRAZIL (single player)...")
	GameManager.player_setup = ["FRANCE", ""]
	print("  player_setup: ", GameManager.player_setup)

	# 进入游戏界面
	if soccer_game.has_method("switch_screen"):
		var sd = load("res://scenes/screens/screen_data.gd").new()
		# 使用 SoccerGame.ScreenType.IN_GAME 枚举值
		var in_game_type := soccer_game.ScreenType.IN_GAME
		soccer_game.switch_screen.call_deferred(in_game_type, sd)
		print("  Transitioning to IN_GAME...")

func _check_game_state():
	print("  GameManager state:")
	if GameManager.current_match:
		var m = GameManager.current_match
		print("    Match: ", m.country_home, " vs ", m.country_away)
		print("    Score: ", m.goals_home, " - ", m.goals_away)
		print("    Winner: ", m.winner)
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

func _check_player_states():
	# 统计场上球员状态
	var actors = get_first_node_in_group("actors_container")
	if actors:
		var all_players = get_nodes_in_group("player")
		print("\n  Players (", all_players.size(), "):")
		var state_counts = {}
		for p in all_players:
			if p.has("current_state") and p.current_state:
				var sname = p.current_state.name.replace("PlayerStateMachine: ", "")
				state_counts[sname] = state_counts.get(sname, 0) + 1
		for s in state_counts.keys():
			print("    ", s, ": ", state_counts[s])

func _finalize():
	print("\n=== Test Complete ===")
	print("Game ran through full lifecycle.")
	quit(0)
