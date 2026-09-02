extends SceneTree
## 全面冒烟测试：逐场景加载并检查错误
## 用法: godot --headless --path . -s res://tools/test_runner.gd

var current_test := 0
var test_timer := 0.0
var test_results := []
var finalized := false

const TEST_HOME_COUNTRY := "GERMANY"
const TEST_AWAY_COUNTRY := "FRANCE"

const TESTS = [
	{"name": "MainMenuScreen", "scene_path": "res://scenes/screens/main_menu/main_menu_screen.tscn"},
	{"name": "TeamSelectionScreen", "scene_path": "res://scenes/screens/team_selection/team_selection_screen.tscn"},
	{"name": "TournamentScreen", "scene_path": "res://scenes/screens/tournament/tournament_screen.tscn"},
	{"name": "WorldScreen", "scene_path": "res://scenes/screens/world/world_screen.tscn"},
]

func _init():
	print("=== Game Smoke Test ===")

func _process(delta):
	test_timer += delta

	match current_test:
		0:
			if test_timer > 0.5:
				_run_next_test()
		_:
			# 每个测试运行 1 秒，然后切换
			if test_timer > 1.0:
				_check_current_scene()
				_unload_current()
				if current_test < TESTS.size():
					_run_next_test()
				else:
					_finalize()

func _run_next_test():
	if current_test >= TESTS.size():
		_finalize()
		return

	var test = TESTS[current_test]
	current_test += 1
	test_timer = 0.0

	print("\n--- Test ", current_test, "/", TESTS.size(), ": ", test.name, " ---")

	var scene_path = test.scene_path
	if not ResourceLoader.exists(scene_path):
		print("[FAIL] Scene not found: ", scene_path)
		test_results.append({"name": test.name, "status": "MISSING"})
		call_deferred("_run_next_test_skip")
		return

	var packed_scene = load(scene_path)
	if packed_scene == null:
		print("[FAIL] Failed to load scene: ", scene_path)
		test_results.append({"name": test.name, "status": "LOAD_FAILED"})
		call_deferred("_run_next_test_skip")
		return

	var instance = packed_scene.instantiate()
	if instance == null:
		print("[FAIL] Failed to instantiate scene: ", scene_path)
		test_results.append({"name": test.name, "status": "INSTANTIATE_FAILED"})
		call_deferred("_run_next_test_skip")
		return

	_setup_test_context(instance, test.name)
	get_root().add_child(instance)
	print("[OK] Loaded and instantiated: ", test.name)
	test_results.append({"name": test.name, "status": "LOADED", "node": instance})

func _setup_test_context(instance: Node, test_name: String) -> void:
	# Screens are normally created through SoccerGame.switch_screen(), which calls
	# setup() before adding the node. The smoke test adds them directly, so provide
	# the same minimum context here instead of testing an impossible null state.
	if instance is Screen:
		var context_data := ScreenData.build()
		if test_name == "TournamentScreen":
			context_data.set_tournament(Tournament.new())
		(instance as Screen).setup(null, context_data)

	# WorldScreen creates actors during _ready(), which requires a match already
	# selected in the real game flow.
	if test_name == "WorldScreen":
		GameManager.player_setup = [TEST_AWAY_COUNTRY, ""]
		GameManager.current_match = Match.new(TEST_HOME_COUNTRY, TEST_AWAY_COUNTRY)

func _run_next_test_skip():
	current_test += 1
	test_timer = 0.0
	if current_test >= TESTS.size():
		_finalize()

func _check_current_scene():
	# 检查当前场景是否还有效（运行 1 秒后没崩就算过）
	var idx = current_test - 1
	if idx >= 0 and idx < test_results.size():
		var result = test_results[idx]
		if result.status == "LOADED":
			if result.node and is_instance_valid(result.node):
				result.status = "PASS"
				print("[OK] ", result.name, " survived 1s runtime")

func _unload_current():
	var idx = current_test - 1
	if idx >= 0 and idx < test_results.size():
		var result = test_results[idx]
		if result.has("node") and result.node and is_instance_valid(result.node):
			# The runner exits immediately after the last test. Free synchronously so
			# queued nodes do not survive into SceneTree cleanup.
			result.node.free()
			result.erase("node")

func _finalize():
	if finalized:
		return
	finalized = true
	_cleanup_test_context()
	print("\n=== Test Results ===")
	var passed = 0
	var failed = 0
	for r in test_results:
		var status_str = r.status
		if status_str == "PASS":
			passed += 1
			print("  ✓ ", r.name)
		else:
			failed += 1
			print("  ✗ ", r.name, " [", status_str, "]")

	print("\nPassed: ", passed, "/", TESTS.size())
	if failed > 0:
		print("FAILED: ", failed)
		quit(1)
	else:
		print("All tests passed!")
		quit(0)

func _cleanup_test_context() -> void:
	# WorldScreen starts a GameManager state asynchronously. Dispose of it before
	# quitting so the runner does not leave state-machine nodes in ObjectDB.
	if is_instance_valid(GameManager.current_state):
		GameManager.current_state.free()
	GameManager.current_state = null
	GameManager.current_match = null
