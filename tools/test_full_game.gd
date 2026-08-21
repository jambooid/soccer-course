extends Node2D
## 完整游戏流程测试：运行完整场比赛，检查所有阶段

var phase := 0
var phase_timer := 0.0
var soccer_game = null
var goals_seen := 0

const MAIN_SCENE_PATH = "res://scenes/soccer_game.tscn"

func _ready():
	print("=== Full Game Flow Test ===")
	GameEvents.team_scored.connect(_on_team_scored.bind())
	call_deferred("_start")

func _on_team_scored(country):
	goals_seen += 1
	print("  >>> GOAL! scored on: ", country, " (total goals: ", goals_seen, ")")

func _start():
	_load_main_scene()

func _process(delta):
	phase_timer += delta

	match phase:
		1:
			if phase_timer > 1.0:
				_setup_and_start_match()
				phase = 2
				phase_timer = 0.0

		2:
			# 等待加载并开球
			if phase_timer > 3.0:
				print("\n--- Kickoff -> First Half ---")
				_start_play()
				phase = 3
				phase_timer = 0.0

		3:
			# 检查比赛是否在运行
			if phase_timer > 5.0:
				print("\n--- 5s in: Check gameplay ---")
				_check_basic()
				phase = 4
				phase_timer = 0.0

		4:
			# 等待半场结束（60秒半场，加上一些缓冲）
			if phase_timer > 60.0:
				print("\n--- ~60s: Should be halftime ---")
				_check_basic()
				if GameManager.current_state and "HALFTIME" in GameManager.current_state.name:
					print("[OK] Halftime reached!")
					# 等待然后进入下半场
					phase = 5
					phase_timer = 0.0
				else:
					print("[WARN] Not in halftime yet, waiting more...")
					phase_timer = 55.0  # 再等 5 秒

		5:
			# 半场休息，等 3 秒后开始下半场
			if phase_timer > 3.0:
				print("\n--- Starting second half ---")
				_start_second_half()
				phase = 6
				phase_timer = 0.0

		6:
			# 下半场运行 60 秒
			if phase_timer > 60.0:
				print("\n--- ~60s second half: Should be game over ---")
				_check_basic()
				_finalize()

func _load_main_scene():
	print("Loading main scene...")
	var packed = load(MAIN_SCENE_PATH)
	soccer_game = packed.instantiate()
	add_child(soccer_game)
	phase = 1
	print("[OK] Main scene loaded")

func _setup_and_start_match():
	GameManager.player_setup = ["FRANCE", "GERMANY"]
	var match_class = load("res://scenes/screens/tournament/match.gd")
	GameManager.current_match = match_class.new("GERMANY", "FRANCE")
	print("Match: GERMANY (home) vs FRANCE (away)")

	var sd = load("res://scenes/screens/screen_data.gd").new()
	soccer_game.switch_screen(soccer_game.ScreenType.IN_GAME, sd)
	print("[OK] Entering IN_GAME")

func _start_play():
	var gsd = load("res://scenes/game_manager/game_states/game_state_data.gd")
	GameManager.switch_state(GameManager.State.FIRST_HALF, gsd.build().set_half(1))
	GameEvents.kickoff_started.emit()
	print("[OK] First half started")

func _start_second_half():
	var gsd = load("res://scenes/game_manager/game_states/game_state_data.gd")
	GameManager.switch_state(GameManager.State.SECOND_HALF, gsd.build().set_half(2))
	GameEvents.kickoff_started.emit()
	print("[OK] Second half started")

func _check_basic():
	var m = GameManager.current_match
	print("  Score: ", m.country_home, " ", m.goals_home, " - ", m.goals_away, " ", m.country_away)
	print("  Half: ", GameManager.current_half, "  Time left: ", GameManager.time_left)
	print("  State: ", GameManager.current_state.name if GameManager.current_state else "null")
	print("  Possession: ", GameManager.possession_home, " / ", GameManager.possession_away)

	var actors = get_tree().get_first_node_in_group("actors_container")
	if actors:
		var ball = actors.ball
		if ball:
			print("  Ball: pos=", ball.position, " speed=", ball.velocity.length(), " carrier=", ball.carrier.name if ball.carrier else "none")

func _finalize():
	print("\n===============================================")
	print("=== FULL GAME TEST COMPLETE ===")
	print("Total goals scored: ", goals_seen)
	print("Final score: ", GameManager.current_match.goals_home, " - ", GameManager.current_match.goals_away)
	print("Check output above for SCRIPT ERROR lines.")
	print("===============================================")
	get_tree().quit(0)
