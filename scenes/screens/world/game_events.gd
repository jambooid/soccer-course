extends Node

## 全局信号总线
## 球权相关：ball_possessed（历史遗留，参数为球员名字字符串）和 ball_possessed_by（新API（参数为 Player 对象）
## 新代码优先使用 ball_possessed_by，ball_possessed 保留用于向后兼容
## ball_possession_stable: 宽限期结束后的稳定控球信号（用于自动切换球员）
signal ball_possessed(player_name: String)
signal ball_possessed_by(player: Player)
signal ball_possession_stable(player: Player)  ## 稳定控球（宽限期结束后）
signal dribble_touch(event: Dictionary)
signal ball_released
signal possession_changed(country: String)  ## 控球方变更
signal game_over(country_winner: String)
signal kickoff_ready
signal kickoff_started
signal impact_received(impact_position: Vector2, is_high_impact: bool)
signal score_changed
signal team_reset
signal team_scored(country_scored_on: String)
signal offside_called(offender: Player, offside_position: Vector2)  ## 越位判罚
signal halftime_started  ## 上半场结束、中场休息开始
signal second_half_started  ## 下半场开始
