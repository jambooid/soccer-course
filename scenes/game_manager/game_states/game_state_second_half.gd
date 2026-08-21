class_name GameStateSecondHalf
extends GameState

## 下半场比赛状态
## 计时、进球后切 SCORED，时间到后判定胜负

func _enter_tree() -> void:
	GameEvents.team_scored.connect(on_team_scored.bind())
	manager.current_half = 2

func _process(delta: float) -> void:
	manager.time_left -= delta
	if manager.is_time_up():
		if manager.current_match.is_tied():
			transition_state(GameManager.State.OVERTIME)
		else:
			transition_state(GameManager.State.GAMEOVER)

func on_team_scored(country_scored_on: String) -> void:
	transition_state(GameManager.State.SCORED, GameStateData.build()
		.set_country_scored_on(country_scored_on)
		.set_half(2))
