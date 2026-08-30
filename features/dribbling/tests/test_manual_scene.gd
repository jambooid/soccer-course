extends Node2D

@onready var ball: Ball = $Ball
@onready var player_high: Player = %PlayerHighTech
@onready var player_low: Player = %PlayerLowTech
@onready var debug_draw: Node2D = $DebugDraw
@onready var instructions: Label = $UI/Instructions

var debug_enabled := true
var initial_player_high_pos := Vector2.ZERO
var initial_player_low_pos := Vector2.ZERO
var initial_ball_pos := Vector2.ZERO

func _ready() -> void:
	print("=== 带球功能手动测试场景 ===")
	print("高技术球员 (WASD): technique=98, speed=80")
	print("低技术球员 (箭头): technique=30, speed=60")
	print("按 TAB 切换调试可视化")
	print("按 R 重置场景")
	print("按 ESC 退出")
	print()

	# 记录初始位置
	initial_player_high_pos = player_high.position
	initial_player_low_pos = player_low.position
	initial_ball_pos = ball.position

	# 设置球员的 kickoff_position 为当前位置，避免跑向 (0,0)
	player_high.kickoff_position = player_high.position
	player_low.kickoff_position = player_low.position

	# 禁用球员的 AI 行为（测试场景中不需要 AI）
	if player_high.current_ai_behavior:
		player_high.current_ai_behavior.queue_free()
		player_high.current_ai_behavior = null
	if player_low.current_ai_behavior:
		player_low.current_ai_behavior.queue_free()
		player_low.current_ai_behavior = null

	# 强制切换到 MOVING 状态，避免 RESETING 状态的移动行为
	player_high.switch_state(Player.State.MOVING)
	player_low.switch_state(Player.State.MOVING)

	# 确保调试绘制启用
	if debug_draw:
		debug_draw.visible = true

	# 让高技术球员先拿球
	await get_tree().create_timer(0.1).timeout
	player_high.control_ball()

func _input(event: InputEvent) -> void:
	# 切换调试可视化
	if event.is_action_pressed("ui_focus_next"):  # TAB
		debug_enabled = !debug_enabled
		if debug_draw:
			debug_draw.visible = debug_enabled
		print("调试可视化: ", "开启" if debug_enabled else "关闭")

	# 重置场景
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		reset_scene()
		print("场景已重置")

	# 退出
	if event.is_action_pressed("ui_cancel"):  # ESC
		get_tree().quit()

	# 切换球员控制 (1和2键)
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			player_high.control_ball()
			print("切换到高技术球员 (tech=98)")
		elif event.keycode == KEY_2:
			player_low.control_ball()
			print("切换到低技术球员 (tech=30)")

func reset_scene() -> void:
	## 重置球员和球到初始状态
	# 重置球员位置和速度
	player_high.position = initial_player_high_pos
	player_high.velocity = Vector2.ZERO
	player_high.height = 0.0
	player_high.height_velocity = 0.0

	player_low.position = initial_player_low_pos
	player_low.velocity = Vector2.ZERO
	player_low.height = 0.0
	player_low.height_velocity = 0.0

	# 重置球位置和速度
	ball.position = initial_ball_pos
	ball.velocity = Vector2.ZERO
	ball.height = 0.0
	ball.height_velocity = 0.0

	# 释放当前球权
	if ball.carrier:
		ball.carrier = null
		ball.switch_state(Ball.State.FREEFORM, BallStateData.build())

	# 确保球员回到 MOVING 状态
	player_high.switch_state(Player.State.MOVING)
	player_low.switch_state(Player.State.MOVING)

	# 让高技术球员重新控球
	await get_tree().create_timer(0.1).timeout
	player_high.control_ball()

func _process(_delta: float) -> void:
	# 更新调试信息
	if debug_enabled and ball and player_high:
		var carrier = ball.carrier
		if carrier and is_instance_valid(carrier):
			var info := ""
			info += "当前控球: %s (tech=%.0f)\n" % [
				"高技术" if carrier == player_high else "低技术",
				carrier.technique
			]
			info += "球员速度: %.1f px/s\n" % carrier.velocity.length()
			info += "球速: %.1f px/s\n" % ball.velocity.length()
			info += "球距离: %.1f px\n" % carrier.position.distance_to(ball.position)

			var max_dist := DribblePhysics.get_max_control_distance(carrier.technique)
			info += "最大可控距离: %.1f px\n" % max_dist

			# 显示在屏幕上
			if instructions:
				var base_text := instructions.text.split("\n\n测试状态:")[0]
				instructions.text = base_text + "\n\n测试状态:\n" + info
