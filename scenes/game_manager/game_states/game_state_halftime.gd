class_name GameStateHalftime
extends GameState

## 中场休息状态
## 交换场地 → 短暂停顿 → 下半场开球

const DURATION_HALFTIME_MS := 3000  # 3 秒中场休息展示

var time_started := 0


func _enter_tree() -> void:
	time_started = Time.get_ticks_msec()
	GameEvents.halftime_started.emit()
	# 交换场地
	var actors := get_tree().get_first_node_in_group("actors_container")
	if actors != null and actors.has_method("swap_sides"):
		actors.swap_sides()


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - time_started > DURATION_HALFTIME_MS:
		# 下半场开始：重置时间，由客队开球（足球规则：下半场由上半场开球方的对方开球）
		manager.time_left = GameManager.DURATION_HALF_SEC
		var kickoff_country := manager.current_match.country_away
		transition_state(GameManager.State.RESET, GameStateData.build()
			.set_country_scored_on(kickoff_country)
			.set_half(2))
