extends Node

## 统一的球场坐标常量（Autoload 单例）
##
## 【像素无关性设计】
##
## 核心理念：
## - 定义"参考尺寸"（REFERENCE_*），所有游戏参数基于此尺寸调试
## - 定义"实际尺寸"（WIDTH/HEIGHT），运行时使用的真实尺寸
## - 通过 SCALE_FACTOR 自动缩放所有"相对距离/速度"
## - 集中管理所有游戏常量，避免散落在各处
##
## 使用方法：
##   PitchConstants.AI.SHOT_DISTANCE      # 访问 AI 相关常量
##   PitchConstants.BALL.KICKOFF_DISTANCE # 访问球相关常量
##   PitchConstants.scaled(150.0)         # 手动缩放自定义值
##
## 要改变球场尺寸，只需修改 WIDTH 和 HEIGHT，所有相对值会自动缩放。
##
## 注意：此文件作为 Autoload 注册（名为 PitchConstants），
## 不要加 class_name，否则会与 autoload 名冲突导致编译错误。

# ========================================
# 基准尺寸（参考设计值）
# ========================================
## 游戏最初设计时的球场尺寸
## 所有硬编码的距离/速度常量都是基于这个尺寸调试出来的
const REFERENCE_WIDTH := 850.0
const REFERENCE_HEIGHT := 360.0

# ========================================
# 实际尺寸（可配置）
# ========================================
## 运行时实际使用的球场尺寸
## 修改这两个值即可缩放整个游戏世界
## 建议保持与 REFERENCE 的宽高比一致，以避免变形
const WIDTH := 850.0
const HEIGHT := 360.0

# ========================================
# 缩放因子（自动计算，只读）
# ========================================
## 水平缩放因子：WIDTH / REFERENCE_WIDTH
## 所有相对距离、速度、加速度都会乘以这个系数
const SCALE_FACTOR := WIDTH / REFERENCE_WIDTH

## 垂直缩放因子：HEIGHT / REFERENCE_HEIGHT
## 目前主要用于验证宽高比是否一致
const SCALE_FACTOR_Y := HEIGHT / REFERENCE_HEIGHT

# ========================================
# 基础几何常量
# ========================================
const CENTER_X := WIDTH * 0.5   ## 球场水平中心
const CENTER_Y := HEIGHT * 0.5  ## 球场垂直中心
const MIN_X := 0.0              ## 球场左边界
const MAX_X := WIDTH            ## 球场右边界
const MIN_Y := 0.0              ## 球场上边界
const MAX_Y := HEIGHT           ## 球场下边界

# ========================================
# 语义化位置常量（推荐使用）
# ========================================
## 用语义化常量代替魔法数字，提高代码可读性
const HALFPITCH_X := CENTER_X   ## 中线 X 坐标（半场分界线）

# ========================================
# 球门相关
# ========================================
## 这些值是基于 850×360 设计时测量的
## 理想情况应该从场景中的 Goal 节点读取，这里保留用于向后兼容
const GOAL_HOME_X := 32.0
const GOAL_AWAY_X := 818.0
const GOAL_Y := 220.0
const CROSSBAR_HEIGHT := 30.0  ## 横梁等效高度（2.5D 物理）

# ========================================
# 2.5D 物理：重力
# ========================================
## 竖直方向的重力加速度（px/s²）
## 缩放策略：与水平尺度同步缩放，保持抛物线轨迹的相对形状
const GRAVITY := 600.0 * SCALE_FACTOR

# ========================================
# 2.5D 物理：高度阈值
# ========================================
## 这些是竖直方向的高度值（px），用于判断球员/球的交互
## 当前策略：不缩放（假设球员精灵大小固定）
const MAX_BALL_HEIGHT := 50.0

const HEIGHT_BALL_CONTROL_MAX := 10.0   ## 胸部停球 vs 直接控球的阈值
const HEIGHT_KICKED_PICKUP_MAX := 12.0   ## KICKED 状态下可捡球的最大高度
const HEIGHT_FREEFORM_PICKUP_MAX := 25.0 ## FREEFORM 状态下可捡球的最大高度
const HEIGHT_SAVED_GOALIE_CATCH := 15.0  ## SAVED 状态门将可抱球的最大高度
const HEIGHT_SAVED_PLAYER_PICKUP := 8.0  ## SAVED 状态球员可捡球的最大高度
const HEIGHT_DEFLECTED_PICKUP_MAX := 10.0 ## DEFLECTED 状态可捡球的最大高度
const HEIGHT_GOALIE_CATCH_MAX := 25.0    ## 门将 AI 认为可抱球的最大高度
const HEIGHT_HEADER_MIN := 5.0           ## 头球最低高度
const HEIGHT_HEADER_MAX := 30.0          ## 头球最高高度
const HEIGHT_VOLLEY_MIN := 1.0           ## 凌空/倒钩最低高度
const HEIGHT_VOLLEY_MAX := 25.0          ## 凌空/倒钩最高高度

# ========================================
# AI 行为常量（集中管理）
# ========================================
class AI:
	## 场地球员 AI
	const SHOT_DISTANCE := SCALE_FACTOR * 150.0          ## 相对：射门触发距离
	const TACKLE_DISTANCE := 15.0                        ## 绝对：铲球身体接触范围
	const SUPPORT_CENTRAL_HOLD_DIST := SCALE_FACTOR * 80.0   ## 相对：后腰保持距离
	const SUPPORT_RUN_ACTIVATION_DIST := SCALE_FACTOR * 200.0 ## 相对：跑位激活距离
	const SPRINT_TECH_THRESHOLD := 60.0                  ## 无量纲：技术阈值
	const SPRINT_DIST_TO_GOAL_MAX := HALFPITCH_X         ## 语义：过中线才冲刺

	## 门将 AI
	const GOALIE_CATCH_RADIUS := 20.0                    ## 绝对：手臂抱球范围
	const GOALIE_RUSH_OUT_DISTANCE := SCALE_FACTOR * 120.0   ## 相对：最大出击距离
	const GOALIE_RUSH_OUT_TRIGGER_DIST := SCALE_FACTOR * 150.0 ## 相对：触发出击距离
	const GOALIE_DISTRIBUTION_KICK_DIST := SCALE_FACTOR * 150.0 ## 相对：大脚开球距离
	const GOALIE_DIVING_SAVE_DISTANCE := SCALE_FACTOR * 60.0  ## 相对：飞身扑救距离

# ========================================
# 球物理常量（集中管理）
# ========================================
class BALL:
	## 基础参数
	const BOUNCINESS := 0.8                              ## 无量纲：反弹系数
	const DISTANCE_HIGH_PASS := SCALE_FACTOR * 90.0     ## 相对：高弧度传球阈值
	const KICKOFF_PASS_DISTANCE := 30.0                 ## 绝对：开球短传距离
	const TUMBLE_HEIGHT_VELOCITY := SCALE_FACTOR * 180.0 ## 相对：被撞弹起速度

	## 时间锁定（不缩放）
	const DURATION_TUMBLE_LOCK := 200                   ## ms：撞击后锁定时间
	const DURATION_PASS_LOCK := 500                     ## ms：传球后锁定时间

	## KICKED 状态
	const KICKED_AIR_FRICTION_MULT := 0.3               ## 无量纲：空气阻力系数
	const KICKED_GROUND_FRICTION := SCALE_FACTOR * 60.0 ## 相对：地面摩擦加速度
	const KICKED_TRANSITION_SPEED := SCALE_FACTOR * 20.0 ## 相对：转为 FREEFORM 速度阈值
	const KICKED_MAX_BOUNCES := 3                       ## 整数：最大弹跳次数

	## SHOT 状态
	const SHOT_DURATION_MS := 1500                      ## ms：射门持续时间
	const SHOT_HEIGHT := 8.0                            ## 绝对：射门初始高度（视觉）
	const SHOT_SPRITE_SCALE := 0.8                      ## 无量纲：精灵缩放
	const SHOT_AIR_FRICTION_MULT := 0.2                 ## 无量纲：空气阻力系数
	const SHOT_GROUND_FRICTION := SCALE_FACTOR * 120.0  ## 相对：地面摩擦加速度
	const SHOT_DROP_MS := 600                           ## ms：延迟下落时间
	const SHOT_GOALIE_CATCH_SPEED := SCALE_FACTOR * 180.0 ## 相对：门将能抱住的速度阈值

	## FREEFORM 状态
	const FREEFORM_AUTO_CAPTURE_DIST := 15.0            ## 绝对：主动接球距离
	const FREEFORM_AUTO_CAPTURE_CHECK_INTERVAL := 3     ## 帧数：检测间隔

	## CARRIED 状态（带球）
	const CARRIED_TOUCH_INTERVAL_MIN := 0.14            ## 秒：最小触球间隔
	const CARRIED_TOUCH_INTERVAL_MAX := 0.32            ## 秒：最大触球间隔
	const CARRIED_TOUCH_OFFSET_MIN := 8.0               ## 绝对：最小带球偏移
	const CARRIED_TOUCH_OFFSET_MAX := 20.0              ## 绝对：最大带球偏移
	const CARRIED_FREE_BALL_RATIO := 0.7                ## 无量纲：离脚窗口比例
	const CARRIED_SPEED_MULTIPLIER := 1.15              ## 无量纲：球速倍数
	const CARRIED_FOLLOW_LERP_FACTOR := 12.0            ## 无量纲：跟随 lerp 系数

	## DRIBBLING 状态（新带球系统）
	const DRIBBLING_GRACE_PERIOD_SEC := 0.5             ## 秒：球权稳定宽限期
	const DRIBBLING_GRACE_CONTROL_DIST_MULT := 1.5      ## 无量纲：宽限期控制距离倍数
	const DRIBBLING_GRACE_INTERCEPT_MULT := 0.5         ## 无量纲：宽限期拦截倍数
	const DRIBBLING_CUTBACK_BALL_KICK_MULT := 1.2       ## 无量纲：急转球踢出倍数

	## HELD_BY_GOALKEEPER 状态
	const HELD_DURATION_MAX_MS := 3000                  ## ms：最大持球时间
	const HELD_OFFSET_Y := -10.0                        ## 绝对：抱球垂直偏移
	const HELD_OFFSET_X := 6.0                          ## 绝对：抱球水平偏移

	## SAVED 状态
	const SAVED_TRANSITION_SPEED := SCALE_FACTOR * 25.0 ## 相对：转为其他状态的速度阈值
	const SAVED_MAX_DURATION_MS := 1500                 ## ms：最大持续时间

	## DEFLECTED 状态
	const DEFLECTED_TRANSITION_SPEED := SCALE_FACTOR * 30.0 ## 相对：转为其他状态的速度阈值
	const DEFLECTED_MAX_DURATION_MS := 1200             ## ms：最大持续时间
	const DEFLECTED_LOCK_DURATION_MS := 200             ## ms：初始锁定时间

# ========================================
# 玩家状态常量（集中管理）
# ========================================
class PLAYER:
	## 动画阈值
	const WALK_ANIM_THRESHOLD := 0.6                    ## 无量纲：走路动画速度阈值

	## MOVING 状态
	const MOVING_TURN_RATE_LOW_SPEED := 12.0            ## rad/s：低速转向速率
	const MOVING_TURN_RATE_HIGH_SPEED := 4.0            ## rad/s：高速转向速率
	const MOVING_CUTBACK_ANGLE_THRESHOLD := deg_to_rad(90.0) ## 弧度：急转角度阈值
	const MOVING_CUTBACK_SPEED_PENALTY := 0.6           ## 无量纲：急转速度衰减
	const MOVING_SPRINT_SPEED_MULTIPLIER := 1.6         ## 无量纲：冲刺速度倍数

	## PASSING 状态
	const PASSING_ASSIST_MAGNET_RANGE_SHORT := SCALE_FACTOR * 180.0  ## 相对：短传吸附范围
	const PASSING_ASSIST_MAGNET_RANGE_LONG := SCALE_FACTOR * 300.0   ## 相对：长传吸附范围
	const PASSING_ASSIST_MAGNET_RANGE_THROUGH := SCALE_FACTOR * 220.0 ## 相对：直塞吸附范围

	## HURT 状态
	const HURT_BALL_TUMBLE_SPEED := SCALE_FACTOR * 100.0 ## 相对：被撞击后球滚动速度

# ========================================
# 辅助函数：缩放工具
# ========================================

## 将基于参考尺寸设计的"相对距离"缩放到当前场地
static func scaled(reference_distance: float) -> float:
	return reference_distance * SCALE_FACTOR

## 将基于参考尺寸设计的"相对速度"（px/s）缩放到当前场地
static func scaled_speed(reference_speed: float) -> float:
	return reference_speed * SCALE_FACTOR

## 将基于参考尺寸设计的"相对加速度"（px/s²）缩放到当前场地
static func scaled_accel(reference_accel: float) -> float:
	return reference_accel * SCALE_FACTOR

## 标记为绝对距离，不缩放（语义化函数）
static func absolute(value: float) -> float:
	return value

## 计算从世界坐标到小地图坐标的缩放因子
static func get_minimap_scale(minimap_size: Vector2) -> Vector2:
	return Vector2(
		minimap_size.x / WIDTH,
		minimap_size.y / HEIGHT
	)

## 检查当前缩放是否保持了原始宽高比
static func is_aspect_ratio_preserved() -> bool:
	return abs(SCALE_FACTOR - SCALE_FACTOR_Y) < 0.01

## 调试信息：打印当前缩放配置
static func print_scale_info() -> void:
	print("=== PitchConstants Scale Info ===")
	print("Reference size: %.0f × %.0f" % [REFERENCE_WIDTH, REFERENCE_HEIGHT])
	print("Actual size: %.0f × %.0f" % [WIDTH, HEIGHT])
	print("Scale factor: %.2f (X) / %.2f (Y)" % [SCALE_FACTOR, SCALE_FACTOR_Y])
	print("Aspect ratio preserved: %s" % is_aspect_ratio_preserved())
	print("Gravity: %.1f px/s²" % GRAVITY)
	print("=================================")

# ========================================
# 运行时验证
# ========================================
func _ready() -> void:
	# 启动时检查配置是否合理
	if not is_aspect_ratio_preserved():
		push_warning("PitchConstants: 宽高比不一致！场地可能变形。")
		push_warning("  X 缩放: %.2f, Y 缩放: %.2f" % [SCALE_FACTOR, SCALE_FACTOR_Y])

	# 调试模式下打印缩放信息
	if OS.is_debug_build():
		print_scale_info()
