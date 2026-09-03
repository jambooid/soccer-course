class_name PlayerStateDiving
extends PlayerState

const DURATION_DIVE := 500

var time_start_dive := 0
var has_saved := false  ## 是否已触球（避免重复触发）

func _enter_tree() -> void:
	# 扑救方向：以当前位置为起点，侧向（y 方向）朝球扑出，
	# 同时加一点向前分量（朝向球场内部，即 heading 方向）
	var target := player.goalkeeper_dive_target if player.goalkeeper_dive_target != Vector2.ZERO else ball.position
	var lateral: float = sign(target.y - player.position.y)
	var dive_direction: Vector2 = (player.heading * 0.4 + Vector2(0, lateral)).normalized()
	if dive_direction.y > 0:
		animation_player.play("dive_down")
	else:
		animation_player.play("dive_up")
	player.velocity = dive_direction * player.speed
	time_start_dive = GameManager.get_match_time_ms()
	# 连接球检测区域，用于扑救触球
	ball_detection_area.body_entered.connect(_on_ball_entered.bind())

func _physics_process(_delta: float) -> void:
	if GameManager.get_match_time_ms() - time_start_dive > DURATION_DIVE:
		transition_state(Player.State.RECOVERING)

func _on_ball_entered(_body: Node) -> void:
	if has_saved:
		return
	if player.role != Player.Role.GOALIE:
		return
	has_saved = true

	ball.goalkeeper_interact(player)
