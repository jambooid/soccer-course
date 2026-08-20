extends Node

signal ball_possessed(player_name: String)
signal ball_possessed_by(player: Player)
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
