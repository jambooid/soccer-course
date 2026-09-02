class_name DribbleTurnReplay
extends RefCounted

const DribblePhysicsScript := preload("res://utils/dribble_physics.gd")
const DribbleTouchControllerScript := preload("res://utils/dribble_touch_controller.gd")

## Fixed-tick replay fixture: turning changes movement intent only. Ball motion
## is advanced by friction and recorded touch impulses, never turn correction.
static func run(seed: int, directions: Array[Vector2], initial_ball_velocity: Vector2, max_control: float) -> Dictionary:
	var controller := DribbleTouchControllerScript.new(seed)
	var player_position := Vector2.ZERO
	var ball_position := Vector2(6.0, 0.0)
	var ball_velocity := initial_ball_velocity
	var player_direction := Vector2.RIGHT
	var loss_tick := -1
	for input_direction in directions:
		var turning := input_direction.length_squared() > 0.0 and player_direction.angle_to(input_direction) > deg_to_rad(30.0)
		if input_direction.length_squared() > 0.0:
			player_direction = input_direction.normalized()
		var player_velocity := player_direction * 90.0
		player_position += player_velocity / 60.0
		ball_velocity = DribblePhysicsScript.apply_friction(ball_velocity, 1.0 / 60.0)
		ball_position += ball_velocity / 60.0
		var touch := controller.advance(1.0 / 60.0, ball_position, player_position, player_direction,
			ball_velocity, player_velocity, 100.0, 70.0, DribblePhysics.Mode.JOG, not turning)
		if not touch.is_empty():
			ball_velocity = touch.velocity
		if loss_tick < 0 and ball_position.distance_to(player_position) > max_control \
				and (ball_position - player_position).dot(player_direction) > 0.0:
			loss_tick = controller.tick
	return {"touches": controller.events.duplicate(true), "loss_tick": loss_tick}
