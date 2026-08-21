class_name GameStateFirstHalf
extends GameState

## 上半场比赛状态
## 计时、进球后切 SCORED，时间到后切 HALFTIME

func _enter_tree() -> void:
	GameEvents.team_scored.connect(on_team_scored.bind())
	manager.current_half = 1
	# 重置时间为半场时长（开球后重置，避免庆祝时间被扣掉的问题）
	if manager.time_left <= 0:
		manager.time_left = GameManager.DURATION_HALF_SEC

func _process(delta: float) -> void:
	manager.time_left -= delta
	if manager.is_time_up():
		SoundPlayer.play(SoundPlayer.Sound.WHISTLE)
		transition_state(GameManager.State.HALFTIME, state_data)

func on_team_scored(country_scored_on: String) -> void:
	transition_state(GameManager.State.SCORED, GameStateData.build()
		.set_country_scored_on(country_scored_on)
		.set_half(1))
