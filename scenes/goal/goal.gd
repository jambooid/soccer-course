class_name Goal
extends Node2D

const CROSSBAR_HEIGHT := PitchConstants.CROSSBAR_HEIGHT  ## 球门横梁等效高度（引用统一常量）

@onready var back_net_area := %BackNetArea
@onready var scoring_area := %ScoringArea
@onready var targets := %Targets

var country := ""
var goal_facing_dir := Vector2.RIGHT  ## 球门开口朝向（球场内部方向）

func _ready() -> void:
	scoring_area.body_entered.connect(on_ball_enter_scoring_area.bind())
	# 根据 scale.x 判断球门朝向（scale.x = -1 表示水平翻转，开口朝左）
	if scale.x < 0:
		goal_facing_dir = Vector2.LEFT
	else:
		goal_facing_dir = Vector2.RIGHT

func initialize(context_country: String) -> void:
	country = context_country

func on_ball_enter_scoring_area(body: Node) -> void:
	if not (body is Ball):
		return
	var ball: Ball = body
	# 球必须高度低于横梁才算进球
	if ball.height > CROSSBAR_HEIGHT:
		return  # 球高出横梁，从球门上方飞过，不算进球
	# 球的运动方向必须朝向球门内部（即与 goal_facing_dir 相反方向）
	# 球门开口朝向球场内部，球从球场飞入球门 = 速度方向与 goal_facing_dir 相反
	if ball.velocity == Vector2.ZERO:
		return  # 球静止，不算进球
	if ball.velocity.dot(-goal_facing_dir) <= 0:
		return  # 球不是飞向球门内部，从后方或侧面进来的，不算
	ball.stop()
	SoundPlayer.play(SoundPlayer.Sound.WHISTLE)
	GameEvents.team_scored.emit(country)

func get_random_target_position() -> Vector2:
	return targets.get_child(randi_range(0, targets.get_child_count() - 1)).global_position

func get_center_target_position() -> Vector2:
	return targets.get_child(int(targets.get_child_count() / 2.0)).global_position

func get_top_target_position() -> Vector2:
	return targets.get_child(0).global_position

func get_bottom_target_position() -> Vector2:
	return targets.get_child(targets.get_child_count() - 1).global_position

func get_scoring_area() -> Area2D:
	return scoring_area
