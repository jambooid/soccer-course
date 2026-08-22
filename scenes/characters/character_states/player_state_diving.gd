class_name PlayerStateDiving
extends PlayerState

const DURATION_DIVE := 500

var time_start_dive := Time.get_ticks_msec()
var has_saved := false  ## 是否已触球（避免重复触发）

func _enter_tree() -> void:
	var target_dive := Vector2(player.spawn_position.x, ball.position.y)
	var direction := player.position.direction_to(target_dive)
	if direction.y > 0:
		animation_player.play("dive_down")
	else:
		animation_player.play("dive_up")
	player.velocity = direction * player.speed
	time_start_dive = Time.get_ticks_msec()
	# 连接球检测区域，用于扑救触球
	ball_detection_area.body_entered.connect(_on_ball_entered.bind())

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - time_start_dive > DURATION_DIVE:
		transition_state(Player.State.RECOVERING)

func _on_ball_entered(_body: Node) -> void:
	if has_saved:
		return
	if player.role != Player.Role.GOALIE:
		return
	# 守门员触球：将球扑出
	has_saved = true
	# 扑救方向：朝向球场前方（远离自己球门），加上侧向分量
	var forward := player.heading  # 守门员面朝球场方向
	# 侧向：球在守门员哪一侧就往哪一侧扑出
	var lateral_dir := sign(ball.position.y - player.position.y)
	var save_dir := (forward + Vector2(0, lateral_dir) * 0.5).normalized()
	# 如果球比较高，给一个向上的分量
	if ball.height > 10.0:
		save_dir.y -= 0.3
		save_dir = save_dir.normalized()
	ball.save_by(player, save_dir, 0.4)
