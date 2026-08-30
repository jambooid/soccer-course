extends Node

## 统一的球场坐标常量（Autoload 单例）
## 所有涉及球场尺寸、位置的代码都应该引用这里的常量，
## 避免硬编码散落在各处导致不一致。
## 注意：此文件作为 Autoload 注册（名为 PitchConstants），
## 不要加 class_name，否则会与 autoload 名冲突导致编译错误。

# 球场尺寸（世界坐标，单位：像素）
const WIDTH := 850.0
const HEIGHT := 360.0
const CENTER_X := WIDTH * 0.5  ## 425.0
const CENTER_Y := HEIGHT * 0.5  ## 180.0

# 球场边界
const MIN_X := 0.0
const MAX_X := WIDTH
const MIN_Y := 0.0
const MAX_Y := HEIGHT

# 球门相关
const GOAL_HOME_X := 32.0
const GOAL_AWAY_X := 818.0
const GOAL_Y := 220.0
const CROSSBAR_HEIGHT := 30.0  ## px，2.5D 横梁等效高度

# 2.5D 物理（竖直方向）
const GRAVITY := 600.0        ## px/s²，竖直重力加速度（球和球员共用）
const MAX_BALL_HEIGHT := 50.0 ## px，球的最大合理高度（超过视为出界/高炮）

# 球-球员交互的高度阈值（统一管理）
const HEIGHT_BALL_CONTROL_MAX := 10.0   ## px，胸部停球 vs 直接控球的阈值
const HEIGHT_KICKED_PICKUP_MAX := 12.0   ## px，KICKED 状态下可捡球的最大高度
const HEIGHT_FREEFORM_PICKUP_MAX := 25.0 ## px，FREEFORM 状态下可捡球的最大高度
const HEIGHT_SAVED_GOALIE_CATCH := 15.0  ## px，SAVED 状态门将可抱球的最大高度
const HEIGHT_SAVED_PLAYER_PICKUP := 8.0  ## px，SAVED 状态球员可捡球的最大高度
const HEIGHT_DEFLECTED_PICKUP_MAX := 10.0 ## px，DEFLECTED 状态可捡球的最大高度
const HEIGHT_GOALIE_CATCH_MAX := 25.0    ## px，门将 AI 认为可抱球的最大高度
const HEIGHT_HEADER_MIN := 5.0           ## px，头球最低高度
const HEIGHT_HEADER_MAX := 30.0          ## px，头球最高高度
const HEIGHT_VOLLEY_MIN := 1.0           ## px，凌空/倒钩最低高度
const HEIGHT_VOLLEY_MAX := 25.0          ## px，凌空/倒钩最高高度
