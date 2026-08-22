class_name GameStateSecondHalf
extends GameStateInPlay

## 下半场比赛状态
## 计时、进球后切 SCORED，时间到后判定胜负

func _enter_tree() -> void:
	super._enter_tree()
	manager.current_half = 2

func _on_time_up() -> void:
	if manager.current_match.is_tied():
		transition_state(GameManager.State.OVERTIME)
	else:
		transition_state(GameManager.State.GAMEOVER)

func _get_half_index() -> int:
	return 2
