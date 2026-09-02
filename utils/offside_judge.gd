class_name OffsideJudge
extends RefCounted

## 越位判定工具
## 规则（简化版，遵循 WE2000 风格）：
## 1. 传球瞬间，攻方球员比倒数第二名防守球员更靠近对方球门 → 越位位置
## 2. 守门员算一名防守球员
## 3. 处在越位位置的球员如果接到球（或参与进攻）→ 判罚越位
## 4. 本方半场内不会越位
## 5. 球门球、角球、掷界外球（本游戏无）不越位

## 越位判定的宽容度（像素），避免误判
const OFFSIDE_TOLERANCE := 2.0

## 在传球瞬间判断指定球员是否处于越位位置
## passer: 传球者
## attackers: 攻方所有球员数组（不包括传球者自己，由调用方决定）
## defenders: 守方所有球员数组
## ball_pos: 传球瞬间球的位置
## attacking_dir_x: 进攻方向（1 = 向右攻，-1 = 向左攻）
## pitch_center_x: 球场中线的 x 坐标（用于判断本方半场）
## 返回 {is_offside: bool, offender: Player, offside_position: Vector2}
static func check_offside_at_pass(
	passer,
	attackers: Array,
	defenders: Array,
	ball_pos: Vector2,
	attacking_dir_x: int,
	pitch_center_x: float = 0.0
) -> Dictionary:
	# 找倒数第二名防守球员的位置（第二最后方的防守者 = 越位线）
	var second_last_def_x := _get_second_last_defender_x(defenders, attacking_dir_x)

	# 球的位置也是越位线的参考：球员不能比球更靠近对方球门
	var ball_x := ball_pos.x

	# 越位线 = 更靠后的那个（倒数第二防守者 和 球 两者中离对方球门更远的那个）
	var offside_line_x: float
	if attacking_dir_x == 1:
		# 向右进攻 → 越位线在左边 = x 更小的那个
		offside_line_x = min(second_last_def_x, ball_x)
	else:
		# 向左进攻 → 越位线在右边 = x 更大的那个
		offside_line_x = max(second_last_def_x, ball_x)

	# 找最越位的攻方球员
	var worst_offender = null
	var worst_offside_amount := 0.0

	for attacker in attackers:
		if attacker == null or attacker == passer:
			continue
		if int(attacker.role) == 0:
			continue  # 门将不会越位

		var attacker_x: float = attacker.global_position.x

		var is_in_offside_position := false
		var offside_amount := 0.0

		if attacking_dir_x == 1:
			# 向右攻：越位 = attacker_x > offside_line_x（更靠近右球门）
			offside_amount = attacker_x - offside_line_x
			# 加上宽容度
			if offside_amount > OFFSIDE_TOLERANCE:
				is_in_offside_position = true
		else:
			# 向左攻：越位 = attacker_x < offside_line_x（更靠近左球门）
			offside_amount = offside_line_x - attacker_x
			if offside_amount > OFFSIDE_TOLERANCE:
				is_in_offside_position = true

		if is_in_offside_position:
			# 检查是否在本方半场（本方半场内不越位）
			if _is_in_own_half(attacker_x, attacking_dir_x, pitch_center_x):
				continue

			if offside_amount > worst_offside_amount:
				worst_offside_amount = offside_amount
				worst_offender = attacker

	if worst_offender != null:
		return {
			"is_offside": true,
			"offender": worst_offender,
			"offside_position": worst_offender.global_position
		}
	return {"is_offside": false, "offender": null, "offside_position": Vector2.ZERO}

## 获取倒数第二名防守球员的 x 坐标
static func _get_second_last_defender_x(defenders: Array, attacking_dir_x: int) -> float:
	if defenders.size() == 0:
		return 0.0

	# 收集所有防守球员的 x 坐标
	var x_positions: Array[float] = []
	for defender in defenders:
		if defender == null:
			continue
		x_positions.append(defender.global_position.x)

	if x_positions.size() == 0:
		return 0.0

	if x_positions.size() == 1:
		return x_positions[0]

	# 排序（按进攻方向判断"最靠后"）
	if attacking_dir_x == 1:
		# 向右攻 → 防守者越靠左（x 越小）越靠后
		# 倒数第二 = 第二小的 x
		x_positions.sort()
		return x_positions[0] if x_positions.size() < 2 else x_positions[1]
	else:
		# 向左攻 → 防守者越靠右（x 越大）越靠后
		# 倒数第二 = 第二大的 x
		x_positions.sort()
		return x_positions[x_positions.size() - 1] if x_positions.size() < 2 else x_positions[x_positions.size() - 2]

## 判断是否在本方半场
static func _is_in_own_half(player_x: float, attacking_dir_x: int, pitch_center_x: float) -> bool:
	if attacking_dir_x == 1:
		# 向右攻 → 本方半场是 x < pitch_center_x（中线左侧）
		return player_x < pitch_center_x
	else:
		# 向左攻 → 本方半场是 x > pitch_center_x（中线右侧）
		return player_x > pitch_center_x

## 判断传球目标是否越位（简化版：直接检查目标位置是否越位）
static func is_target_offside(
	target_pos: Vector2,
	defenders: Array,
	ball_pos: Vector2,
	attacking_dir_x: int,
	pitch_center_x: float = 0.0
) -> bool:
	var second_last_def_x := _get_second_last_defender_x(defenders, attacking_dir_x)
	var offside_line_x: float

	if attacking_dir_x == 1:
		offside_line_x = min(second_last_def_x, ball_pos.x)
		var offside_amount = target_pos.x - offside_line_x
		return offside_amount > OFFSIDE_TOLERANCE and target_pos.x > pitch_center_x
	else:
		offside_line_x = max(second_last_def_x, ball_pos.x)
		var offside_amount = offside_line_x - target_pos.x
		return offside_amount > OFFSIDE_TOLERANCE and target_pos.x < pitch_center_x
