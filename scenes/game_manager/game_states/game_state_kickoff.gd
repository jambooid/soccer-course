class_name GameStateKickoff
extends GameState

var valid_control_schemes := []

func _enter_tree() -> void:
	var country_starting := state_data.country_scored_on
	if country_starting.is_empty():
		country_starting = manager.current_match.country_home
	if country_starting == manager.player_setup[0]:
		valid_control_schemes.append(Player.ControlScheme.P1)
	if country_starting == manager.player_setup[1]:
		valid_control_schemes.append(Player.ControlScheme.P2)
	if valid_control_schemes.size() == 0:
		valid_control_schemes.append(Player.ControlScheme.P1)

func _physics_process(_delta: float) -> void:
	for control_scheme : Player.ControlScheme in valid_control_schemes:
		if KeyUtils.is_action_just_pressed(control_scheme, KeyUtils.Action.SHORT_PASS):
			GameEvents.kickoff_started.emit()
			SoundPlayer.play(SoundPlayer.Sound.WHISTLE)
			# 根据当前半场跳转到对应状态
			var play_state := GameManager.State.FIRST_HALF if state_data.half == 1 else GameManager.State.SECOND_HALF
			transition_state(play_state, state_data)
