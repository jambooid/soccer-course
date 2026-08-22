class_name GameStateInPlay
extends GameState

## 比赛进行中的基类
## 封装通用逻辑：倒计时、进球检测
## 子类覆写 _on_time_up() 和 _get_half_index() 等实现差异化行为

func _enter_tree() -> void:
	GameEvents.team_scored.connect(_on_team_scored.bind())

func _process(delta: float) -> void:
	manager.time_left -= delta
	if manager.is_time_up():
		_on_time_up()

func _on_team_scored(country_scored_on: String) -> void:
	## 进球时的默认处理：切到 SCORED 状态
	## 子类可以覆写（如加时赛进球直接结束）
	transition_state(GameManager.State.SCORED, GameStateData.build()
		.set_country_scored_on(country_scored_on)
		.set_half(_get_half_index()))

func _on_time_up() -> void:
	## 时间到的处理，子类必须覆写
	pass

func _get_half_index() -> int:
	## 返回当前半场索引（1=上半场，2=下半场，3=加时）
	## 用于传给 SCORED 状态的 half 字段
	return 1
