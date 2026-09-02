class_name PlayerStateRecovering
extends PlayerState

const DURATION_RECOVERY := 500
const ACCEPT_INPUT_WINDOW := 100  # 硬直结束前多少毫秒开始接受缓冲输入

var time_start_recovery := Time.get_ticks_msec()

func _enter_tree() -> void:
	time_start_recovery = Time.get_ticks_msec()
	player.velocity = Vector2.ZERO
	animation_player.play("recover")

func _physics_process(_delta: float) -> void:
	var elapsed := Time.get_ticks_msec() - time_start_recovery
	if elapsed > DURATION_RECOVERY:
		# 硬直结束，检查缓冲中是否有待执行的动作
		if player.control_scheme != Player.ControlScheme.CPU:
			_check_buffered_actions()
		transition_state(Player.State.MOVING)
	elif elapsed > DURATION_RECOVERY - ACCEPT_INPUT_WINDOW:
		# 在接受窗口内：如果有缓冲动作，提前结束恢复并执行
		if player.control_scheme != Player.ControlScheme.CPU and _check_buffered_actions():
			pass  # 已在 _check_buffered_actions 中切换状态

func _check_buffered_actions() -> bool:
	"""检查输入缓冲中的动作，有就执行对应状态转换。返回是否触发了转换。"""
	if player.has_ball():
		# 持球状态的缓冲动作（按优先级排列：射门 > 直塞 > 长传 > 短传）
		if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.SHOOT):
			transition_state(Player.State.PREPPING_SHOT)
			return true
		if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.THROUGH_PASS):
			transition_state(Player.State.PASSING, PlayerStateData.build()
				.set_pass_type(PlayerStateData.PassType.THROUGH))
			return true
		if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.LONG_PASS):
			transition_state(Player.State.PASSING, PlayerStateData.build()
				.set_pass_type(PlayerStateData.PassType.LONG))
			return true
		if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.SHORT_PASS):
			transition_state(Player.State.PASSING, PlayerStateData.build()
				.set_pass_type(PlayerStateData.PassType.SHORT))
			return true
	else:
		# 无球状态的缓冲动作
		if KeyUtils.consume_action_buffer(player.control_scheme, KeyUtils.Action.SHOOT):
			# 无球按射门 = 铲球
			transition_state(Player.State.TACKLING)
			return true
	return false
