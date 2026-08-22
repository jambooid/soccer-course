class_name GameStateFirstHalf
extends GameStateInPlay

## 上半场比赛状态
## 计时、进球后切 SCORED，时间到后切 HALFTIME

func _enter_tree() -> void:
	super._enter_tree()
	manager.current_half = 1
	# 重置时间为半场时长（开球后重置，避免庆祝时间被扣掉的问题）
	if manager.time_left <= 0:
		manager.time_left = GameManager.DURATION_HALF_SEC

func _on_time_up() -> void:
	SoundPlayer.play(SoundPlayer.Sound.WHISTLE)
	transition_state(GameManager.State.HALFTIME, state_data)

func _get_half_index() -> int:
	return 1
