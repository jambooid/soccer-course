extends SceneTree

const HUD := preload("res://scenes/world3d/match_hud.gd")
const Director := preload("res://scenes/world3d/camera_director.gd")
const Event := preload("res://utils/match_event.gd")

var passed := 0
var failed := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var hud := HUD.new()
	root.add_child(hud)
	await process_frame
	hud.update_from_snapshot({"score_home": 2, "score_away": 1, "half": 2,
		"clock": 45.0, "selected_player_id": 9, "event_label": "GOAL KICK",
		"radar": [{"id": 1, "home": true, "position": Vector3(20, 0, 18)}],
		"ball": {"position": Vector3(42.5, 0, 18)}}, false, 0.0, 1.0)
	_expect(_inside(hud.score_label.get_global_rect(), Rect2(0, 0, 560, 360)),
		"score panel stays inside the 560x360 internal safe area")
	_expect(not hud.score_label.get_global_rect().intersects(hud.event_label.get_global_rect()),
		"score and event labels do not overlap")
	_expect(not hud.player_label.get_global_rect().intersects(hud.radar.get_global_rect()),
		"selected-player panel and radar do not overlap")
	_expect(hud.radar.get_global_rect().end.x <= 560.0 and hud.radar.get_global_rect().end.y <= 360.0,
		"radar remains in the 16:9 output safe area")
	var director := Director.new()
	director.consume_event(Event.new("goal", 1, {"position": Vector3(85, 0, 18)}))
	_expect(director.shot == director.Shot.GOAL_FOCUS, "goal event enters the goal-focus shot")
	director.set_replay(true)
	_expect(director.shot == director.Shot.REPLAY, "replay takes camera ownership")
	director.set_replay(false)
	_expect(director.shot == director.Shot.BROADCAST, "replay returns camera to broadcast")
	hud.free()
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _inside(rect: Rect2, bounds: Rect2) -> bool:
	return bounds.encloses(rect)

func _expect(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("  [PASS] %s" % label)
	else:
		failed += 1
		print("  [FAIL] %s" % label)
