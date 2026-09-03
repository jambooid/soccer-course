class_name AIBehavior
extends Node

const DURATION_AI_TICK_FREQUENCY := 200  ## 默认 AI tick 间隔（毫秒）
const LOD_CORE_TICK_MS := 50      ## 核心层 tick：50ms（约每 3 帧 @60fps）
const LOD_MID_TICK_MS := 200      ## 中间层 tick：200ms（约每 12 帧）
const LOD_FAR_TICK_MS := 1000     ## 远端层 tick：1000ms（约每 60 帧）

enum LODLevel { CORE, MID, FAR }

var ai_lod_level : int = LODLevel.MID  ## 当前 LOD 级别（默认中间层）

var ball : Ball = null
var opponent_detection_area : Area2D = null
var player : Player = null
var teammate_detection_area : Area2D = null
var time_since_last_ai_tick := 0

func _ready() -> void:
	# Deterministic staggering avoids every CPU thinking on the same frame while
	# keeping replays independent of global RNG state and process start timing.
	var stable_offset := 0
	if player != null:
		stable_offset = abs(player.jersey_number) % DURATION_AI_TICK_FREQUENCY
	time_since_last_ai_tick = GameManager.get_match_time_ms() + stable_offset

func setup(context_player: Player, context_ball: Ball, context_opponent_detection_area: Area2D, context_teammate_detection_area: Area2D) -> void:
	player = context_player
	ball = context_ball
	opponent_detection_area = context_opponent_detection_area
	teammate_detection_area = context_teammate_detection_area

func set_lod_level(level: int) -> void:
	## 设置 AI 的 LOD 级别，影响决策频率
	ai_lod_level = level

func _get_tick_interval_ms() -> int:
	## 获取当前 LOD 级别的 tick 间隔
	match ai_lod_level:
		LODLevel.CORE:
			return LOD_CORE_TICK_MS
		LODLevel.MID:
			return LOD_MID_TICK_MS
		LODLevel.FAR:
			return LOD_FAR_TICK_MS
		_:
			return LOD_MID_TICK_MS

func process_ai() -> void:
	if GameManager.get_match_time_ms() - time_since_last_ai_tick > _get_tick_interval_ms():
		time_since_last_ai_tick = GameManager.get_match_time_ms()
		perform_ai_movement()
		perform_ai_decisions()

func perform_ai_movement() -> void:
	pass

func perform_ai_decisions() -> void:
	pass

func get_bicircular_weight(position: Vector2, center_target: Vector2, inner_circle_radius: float, inner_circle_weight: float, outer_circle_radius: float, outer_circle_weight: float) -> float:
	var distance_to_center := position.distance_to(center_target)
	if distance_to_center > outer_circle_radius:
		return outer_circle_weight
	elif distance_to_center < inner_circle_radius:
		return inner_circle_weight
	else:
		var distance_to_inner_radius := distance_to_center - inner_circle_radius
		var close_range_distance := outer_circle_radius - inner_circle_radius
		return lerpf(inner_circle_weight, outer_circle_weight, distance_to_inner_radius / close_range_distance)

func is_ball_possessed_by_opponent() -> bool:
	return ball.carrier != null and ball.carrier.country != player.country

func is_ball_carried_by_teammate() -> bool:
	return ball.carrier != null and ball.carrier != player and ball.carrier.country == player.country

func has_opponents_nearby() -> bool:
	var players := opponent_detection_area.get_overlapping_bodies()
	return players.find_custom(func(p: Player): return p.country != player.country) > -1
