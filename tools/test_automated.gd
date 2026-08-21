extends Node2D
## 自动化测试场景：程序化驱动游戏，检测运行时错误
## 设置为 main scene 运行: godot --headless --path . --main-pack res://tools/test_automated.gd (不行)
## 正确用法: 用这个脚本替换 soccer_game 的主场景运行

var phase := 0
var phase_timer := 0.0
var errors_log := []

func _ready():
	print("=== Automated Game Test ===")
	# 连接错误信号
	get_tree().connect("node_configuration_warning_changed", _on_warning)

func _process(delta):
	phase_timer += delta

	match phase:
		0:
			# 阶段 0: 创建 Match 并初始化 GameManager
			if phase_timer > 0.5:
				_setup_match()
				phase = 1
				phase_timer = 0.0

		1:
			# 阶段 1: 加载 world_screen
			if phase_timer > 0.5:
				_load_world_screen()
				phase = 2
				phase_timer = 0.0

		2:
			# 阶段 2: 等游戏初始化
			if phase_timer > 2.0:
				print("\n=== Phase 2: Game Started ===")
				_check_state("Kickoff")
				# 模拟开球按键
				_simulate_kickoff()
				phase = 3
				phase_timer = 0.0

		3:
			# 阶段 3: 运行 5 秒
			if phase_timer > 5.0:
				print("\n=== Phase 3: After 5s ===")
				_check_state("5s in")
				phase = 4
				phase_timer = 0.0

		4:
			# 阶段 4: 运行到 30 秒
			if phase_timer > 25.0:
				print("\n=== Phase 4: After 30s ===")
				_check_state("30s in")
				_check_players()
				_check_ball()
				_finalize()

func _setup_match():
	print("Setting up match: FRANCE vs GERMANY")
	var match_obj = Match.new("FRANCE", "GERMANY")
	GameManager.current_match = match_obj
	GameManager.player_setup = ["FRANCE", ""]
	print("  Match created: ", match_obj.country_home, " vs ", match_obj.country_away)

func _load_world_screen():
	print("Loading world screen...")
	var world_scene = load("res://scenes/screens/world/world_screen.tscn")
	if world_scene:
		var world = world_scene.instantiate()
		add_child(world)
		print("  World screen added")
	else:
		print("[ERROR] Cannot load world_screen.tscn")
		get_tree().quit(1)

func _simulate_kickoff():
	print("Simulating kickoff (P1 short pass)...")
	# 直接发出 kickoff 事件
	GameEvents.kickoff_started.emit()

func _check_state(label):
	print("--- ", label, " ---")
	if GameManager.current_match:
		var m = GameManager.current_match
		print("  Score: ", m.country_home, " ", m.goals_home, " - ", m.goals_away, " ", m.country_away)
	print("  Half: ", GameManager.current_half)
	print("  Time: ", GameManager.time_left)
	print("  State: ", GameManager.current_state.name if GameManager.current_state else "null")
	print("  Possession: ", GameManager.possession_home, " / ", GameManager.possession_away)

func _check_players():
	var players = get_tree().get_nodes_in_group("player")
	print("\n  Players (", players.size(), "):")
	var state_counts = {}
	var countries = {}
	for p in players:
		if p.has_method("get_country") or p.has("country"):
			countries[p.country] = countries.get(p.country, 0) + 1
		if p.current_state:
			var sn = p.current_state.name
			state_counts[sn] = state_counts.get(sn, 0) + 1
	for c in countries.keys():
		print("    ", c, ": ", countries[c], " players")
	print("  States:")
	for s in state_counts.keys():
		print("    ", s, ": ", state_counts[s])

func _check_ball():
	var balls = get_tree().get_nodes_in_group("ball")
	if balls.size() > 0:
		var b = balls[0]
		print("\n  Ball:")
		print("    pos: ", b.position)
		print("    vel: ", b.velocity)
		print("    height: ", b.height)
		print("    carrier: ", b.carrier.name if b.carrier else "none")
		print("    state: ", b.current_state.name if b.current_state else "null")

func _on_warning(node):
	pass

func _finalize():
	print("\n=== Test Complete ===")
	print("Errors logged: ", errors_log.size())
	for e in errors_log:
		print("  - ", e)
	get_tree().quit(0)
