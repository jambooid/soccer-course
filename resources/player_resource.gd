class_name PlayerResource
extends Resource

@export var full_name : String
@export var number : int = 0
@export var skin_color : Player.SkinColor
@export var role : Player.Role

## 七维属性（0-100 范围）
@export var speed : float = 50.0        ## 奔跑最大速度
@export var power : float = 50.0        ## 射门力度、传球距离、身体对抗
@export var technique : float = 50.0    ## 传球精度、控球能力、停球质量
@export var shooting : float = 50.0     ## 射门精度、射门力量控制
@export var defense : float = 50.0      ## 抢断成功率、防守站位
@export var jump : float = 50.0         ## 争顶高度、头球能力
@export var stamina : float = 50.0      ## 全场持续跑动的能力

func _init(player_name: String = "", player_skin: Player.SkinColor = Player.SkinColor.MEDIUM,
		player_role: Player.Role = Player.Role.MIDFIELD,
		player_speed: float = 50.0, player_power: float = 50.0) -> void:
	full_name = player_name
	skin_color = player_skin
	role = player_role
	speed = player_speed
	power = player_power
