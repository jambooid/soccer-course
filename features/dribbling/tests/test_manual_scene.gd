extends Node2D

@onready var ball: Ball = $Ball
@onready var player_high: Player = %PlayerHighTech
@onready var player_low: Player = %PlayerLowTech
@onready var debug_draw: Node2D = $DebugDraw
@onready var instructions: Label = $UI/Instructions

var debug_enabled := true

func _ready() -> void:
	print("=== 带球功能手动测试场景 ===")
	print("高技术球员 (WASD): technique=98, speed=80")
	print("低技术球员 (箭头): technique=30, speed=60")
	print("按 TAB 切换调试可视化")
	print("按 ESC 退出")
	print()

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
