class_name KeyUtils

enum Action {LEFT, RIGHT, UP, DOWN, SHOOT, SHORT_PASS, LONG_PASS, THROUGH_PASS, SPRINT, SPECIAL}

const ACTIONS_MAP : Dictionary = {
	Player.ControlScheme.P1: {
		Action.LEFT: "p1_left",
		Action.RIGHT: "p1_right",
		Action.UP: "p1_up",
		Action.DOWN: "p1_down",
		Action.SHOOT: "p1_shoot",
		Action.SHORT_PASS: "p1_pass",
		Action.LONG_PASS: "p1_long_pass",
		Action.THROUGH_PASS: "p1_through_pass",
		Action.SPRINT: "p1_sprint",
		Action.SPECIAL: "p1_special",
	},
	Player.ControlScheme.P2: {
		Action.LEFT: "p2_left",
		Action.RIGHT: "p2_right",
		Action.UP: "p2_up",
		Action.DOWN: "p2_down",
		Action.SHOOT: "p2_shoot",
		Action.SHORT_PASS: "p2_pass",
		Action.LONG_PASS: "p2_long_pass",
		Action.THROUGH_PASS: "p2_through_pass",
		Action.SPRINT: "p2_sprint",
		Action.SPECIAL: "p2_special",
	},
}

static func get_input_vector(scheme: Player.ControlScheme) -> Vector2:
	var map : Dictionary = ACTIONS_MAP[scheme]
	return Input.get_vector(map[Action.LEFT], map[Action.RIGHT], map[Action.UP], map[Action.DOWN])

static func is_action_pressed(scheme: Player.ControlScheme, action: Action) -> bool:
	return Input.is_action_pressed(ACTIONS_MAP[scheme][action])

static func is_action_just_pressed(scheme: Player.ControlScheme, action: Action) -> bool:
	return Input.is_action_just_pressed(ACTIONS_MAP[scheme][action])

static func is_action_just_released(scheme: Player.ControlScheme, action: Action) -> bool:
	return Input.is_action_just_released(ACTIONS_MAP[scheme][action])

## 从输入缓冲中消耗一个动作（如果存在且在窗口内）
## 这是 is_action_just_pressed 的"缓冲版"，用于动画状态中接受输入的帧
static func consume_action_buffer(scheme: Player.ControlScheme, action: Action) -> bool:
	var action_name: String = ACTIONS_MAP[scheme][action]
	return InputBuffer.consume(action_name)

## 检查缓冲中是否有动作（不消耗）
static func has_action_buffered(scheme: Player.ControlScheme, action: Action) -> bool:
	var action_name: String = ACTIONS_MAP[scheme][action]
	return InputBuffer.has(action_name)

## 从缓冲中消耗多个动作中的任意一个，返回被消耗的 action 名（空字符串表示都没有）
static func consume_any_buffer(scheme: Player.ControlScheme, actions: Array) -> int:
	var action_names: Array = []
	for action in actions:
		action_names.append(ACTIONS_MAP[scheme][action])
	var consumed_name := InputBuffer.consume_any(action_names)
	if consumed_name == "":
		return -1
	# 反查是哪个 action
	for i in range(actions.size()):
		if ACTIONS_MAP[scheme][actions[i]] == consumed_name:
			return actions[i]
	return -1

## 清空缓冲（用于状态切换等硬切割场景）
static func clear_buffer() -> void:
	InputBuffer.clear()
