class_name Goal
extends Node2D

const CROSSBAR_HEIGHT := 30.0  ## 球门横梁等效高度，超过此高度的球不算进球（2.5D 高度检测）

@onready var back_net_area := %BackNetArea
@onready var scoring_area := %ScoringArea
@onready var targets := %Targets

var country := ""

func _ready() -> void:
	back_net_area.body_entered.connect(on_ball_enter_back_net.bind())

func initialize(context_country: String) -> void:
	country = context_country

func on_ball_enter_back_net(ball: Ball) -> void:
	ball.stop()
	# 球必须完全进入球网且高度低于横梁才算进球
	if ball.height > CROSSBAR_HEIGHT:
		return  # 球高出横梁，从球门上方飞过，不算进球
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
