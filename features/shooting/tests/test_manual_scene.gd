extends Node2D

@onready var ball: Ball = $Ball
@onready var player_high: Player = %PlayerHighShooting
@onready var player_low: Player = %PlayerLowShooting
@onready var status_label: Label = $UI/Status
@onready var aim_label: Label = $UI/Aim

var active_player: Player
var debug_enabled := true
var initial_ball_position := Vector2.ZERO
var initial_high_position := Vector2.ZERO
var initial_low_position := Vector2.ZERO

func _ready() -> void:
	print("=== 射门功能手动测试场景 ===")
	print("高射门属性球员 (WASD/J): shooting=95, power=180")
	print("低射门属性球员 (方向键/7): shooting=35, power=130")
	print("按住射门键蓄力，松开后才播放射门动画")
	print("蓄力期间按方向键：保持蓄力并改变带球方向，释放时微调轨迹")

	initial_ball_position = ball.position
	initial_high_position = player_high.position
	initial_low_position = player_low.position
	_prepare_player(player_high)
	_prepare_player(player_low)
	await get_tree().create_timer(0.1).timeout
	_set_active_player(player_high)
	queue_redraw()

func _prepare_player(player: Player) -> void:
	player.kickoff_position = player.position
	if player.current_ai_behavior != null:
		player.current_ai_behavior.queue_free()
		player.current_ai_behavior = null
	player.switch_state(Player.State.MOVING)

func _set_active_player(next_player: Player) -> void:
	active_player = next_player
	if not is_instance_valid(active_player):
		return
	ball.carrier = active_player
	ball.position = active_player.position + Vector2.RIGHT * 12.0
	ball.velocity = Vector2.ZERO
	ball.height = 0.0
	ball.height_velocity = 0.0
	ball.switch_state(Ball.State.DRIBBLING, BallStateData.build())
	active_player.switch_state(Player.State.MOVING)
	status_label.text = "当前球员：%s" % _player_name(active_player)

func _player_name(player: Player) -> String:
	return "高射门属性 (95/180)" if player == player_high else "低射门属性 (35/130)"

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	elif event.is_action_pressed("ui_focus_next"):
		debug_enabled = not debug_enabled
		queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			_set_active_player(player_high)
		elif event.keycode == KEY_2:
			_set_active_player(player_low)
		elif event.keycode == KEY_R:
			_reset_scene()

func _reset_scene() -> void:
	player_high.position = initial_high_position
	player_low.position = initial_low_position
	player_high.velocity = Vector2.ZERO
	player_low.velocity = Vector2.ZERO
	player_high.height = 0.0
	player_low.height = 0.0
	ball.position = initial_ball_position
	ball.velocity = Vector2.ZERO
	ball.height = 0.0
	ball.height_velocity = 0.0
	ball.carrier = null
	ball.switch_state(Ball.State.FREEFORM, BallStateData.build())
	_prepare_player(player_high)
	_prepare_player(player_low)
	await get_tree().create_timer(0.1).timeout
	_set_active_player(player_high)

func _process(_delta: float) -> void:
	if not is_instance_valid(active_player):
		return
	var charge := active_player.charge_display
	var state_name := str(active_player.current_state.name) if active_player.current_state != null else "-"
	status_label.text = "当前球员：%s\n状态：%s\n蓄力：%3d%%  |  球速：%5.1f\n球权：%s" % [
		_player_name(active_player), state_name, roundi(charge * 100.0), ball.velocity.length(),
		"有球" if ball.carrier == active_player else "无球"
	]
	aim_label.text = "目标球门：自动辅助到右侧中路\n蓄力期间方向键：改变带球方向并微调轨迹"
	queue_redraw()

func _draw() -> void:
	if not debug_enabled or active_player == null or active_player.target_goal == null:
		return
	var goal := active_player.target_goal
	draw_line(active_player.position, goal.get_center_target_position(), Color(1.0, 1.0, 0.2, 0.75), 1.0)
	draw_circle(goal.get_center_target_position(), 3.0, Color.WHITE)
	draw_circle(goal.get_top_target_position(), 3.0, Color(0.3, 0.8, 1.0))
	draw_circle(goal.get_bottom_target_position(), 3.0, Color(1.0, 0.4, 0.3))
