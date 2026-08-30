extends Node

## 统一的球场坐标常量（Autoload 单例）
##
## 【像素无关性设计】
##
## 核心理念：
## - 定义"参考尺寸"（REFERENCE_*），所有游戏参数基于此尺寸调试
## - 定义"实际尺寸"（WIDTH/HEIGHT），运行时使用的真实尺寸
## - 通过 SCALE_FACTOR 自动缩放所有"相对距离/速度"
## - 区分"绝对尺度"（身体接触）和"相对尺度"（场地比例）
##
## 使用方法：
##   const SHOT_DISTANCE := PitchConstants.scaled(150.0)      # 相对：随场地缩放
##   const TACKLE_DISTANCE := PitchConstants.absolute(15.0)   # 绝对：不缩放
##   const SPRINT_MULTIPLIER := 1.6                           # 无量纲：本身就是比例
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
# 球门相关（场景依赖，需谨慎）
# ========================================
## ⚠️ 这些值是基于 850×360 设计时，从场景中测量得到的
## 如果改变场地尺寸，理想做法是在运行时从 Goal 节点读取位置
## 而不是硬编码。这里保留是为了向后兼容。
const GOAL_HOME_X := 32.0
const GOAL_AWAY_X := 818.0
const GOAL_Y := 220.0
const CROSSBAR_HEIGHT := 30.0  ## 横梁等效高度（2.5D 物理）

# ========================================
# 2.5D 物理：重力
# ========================================
## 竖直方向的重力加速度（px/s²）
##
## 缩放策略：与水平尺度同步缩放，保持抛物线轨迹的相对形状
## 例如：场地宽度翻倍 → 重力也翻倍 → 球的飞行时间不变，但覆盖距离翻倍
const GRAVITY := 600.0 * SCALE_FACTOR

# ========================================
# 2.5D 物理：高度阈值
# ========================================
## 这些是竖直方向的高度值（px），用于判断球员/球的交互
##
## ⚠️ 是否缩放存在争议：
## - 不缩放：认为高度是绝对的（球员身高不变），适合精灵大小不变的情况
## - 缩放：认为整个 3D 空间同步缩放，适合精灵也会缩放的情况
##
## 当前策略：不缩放（假设球员精灵大小固定）
## 如需缩放，在每个常量后乘以 SCALE_FACTOR
const MAX_BALL_HEIGHT := 50.0           ## 球的最大合理高度（超过视为出界）

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
# 辅助函数：缩放工具
# ========================================

## 将基于参考尺寸设计的"相对距离"缩放到当前场地
##
## 用途：AI 判断距离、战术位置、传球范围等与场地尺寸成比例的值
## 示例：const SHOT_DISTANCE := PitchConstants.scaled(150.0)
##
## 当 WIDTH=850 时，返回 150.0
## 当 WIDTH=1700 时，返回 300.0
static func scaled(reference_distance: float) -> float:
	return reference_distance * SCALE_FACTOR


## 将基于参考尺寸设计的"相对速度"（px/s）缩放到当前场地
##
## 用途：移动速度、球速等，保持"跑完全场的时间"相对一致
## 示例：const RUN_SPEED := PitchConstants.scaled_speed(100.0)
##
## 物理一致性：速度与距离同步缩放，保持运动学相似
static func scaled_speed(reference_speed: float) -> float:
	return reference_speed * SCALE_FACTOR


## 将基于参考尺寸设计的"相对加速度"（px/s²）缩放到当前场地
##
## 用途：摩擦力、加速度等，保持物理感一致
## 示例：const GROUND_FRICTION := PitchConstants.scaled_accel(60.0)
##
## 物理一致性：加速度与距离同步缩放，保持减速距离比例一致
static func scaled_accel(reference_accel: float) -> float:
	return reference_accel * SCALE_FACTOR


## 标记为绝对距离，不缩放（语义化函数，增强代码可读性）
##
## 用途：球员身体接触范围、碰撞检测等与物理尺寸相关的值
## 示例：const TACKLE_DISTANCE := PitchConstants.absolute(15.0)
##
## 注意：这个函数只是直接返回原值，但它的存在表明"我们知道可以缩放，
## 但我们*选择*不缩放，因为这是绝对距离"，提高代码意图的清晰度。
static func absolute(value: float) -> float:
	return value


## 计算从世界坐标到小地图坐标的缩放因子
##
## 参数：minimap_size - 小地图的 UI 尺寸（像素）
## 返回：Vector2(x_scale, y_scale)
##
## 用途：RadarMinimap 等 UI 组件将世界坐标映射到屏幕坐标
static func get_minimap_scale(minimap_size: Vector2) -> Vector2:
	return Vector2(
		minimap_size.x / WIDTH,
		minimap_size.y / HEIGHT
	)


## 检查当前缩放是否保持了原始宽高比
##
## 返回：true 如果 SCALE_FACTOR == SCALE_FACTOR_Y（允许 1% 误差）
##
## 用途：启动时验证配置，避免场地变形
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
# 运行时验证（可选）
# ========================================
func _ready() -> void:
	# 启动时检查配置是否合理
	if not is_aspect_ratio_preserved():
		push_warning("PitchConstants: 宽高比不一致！场地可能变形。")
		push_warning("  X 缩放: %.2f, Y 缩放: %.2f" % [SCALE_FACTOR, SCALE_FACTOR_Y])

	# 调试模式下打印缩放信息（可注释掉）
	if OS.is_debug_build():
		print_scale_info()
