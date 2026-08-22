class_name GameStateOvertime
extends GameStateInPlay

## 加时赛状态（金球制）
## 进球直接结束比赛 → GAMEOVER
## 时间到打平 → GAMEOVER（M4 再做点球大战）

const OVERTIME_DURATION_SEC := 30  ## 加时 30 秒（街机节奏）

func _enter_tree() -> void:
	super._enter_tree()
	manager.time_left = float(OVERTIME_DURATION_SEC)

func _on_team_scored(country_scored_on: String) -> void:
	## 加时赛金球制：进球直接结束
	manager.increase_score(country_scored_on)
	transition_state(GameManager.State.GAMEOVER)

func _on_time_up() -> void:
	## 加时赛时间到还是平局 → 结束（M4 加点球大战）
	transition_state(GameManager.State.GAMEOVER)

func _get_half_index() -> int:
	return 3
