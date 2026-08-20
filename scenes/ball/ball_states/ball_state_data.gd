class_name BallStateData

var lock_duration : int
var kicker : Player = null

static func build() -> BallStateData:
	return BallStateData.new()

func set_lock_duration(duration: int) -> BallStateData:
	lock_duration = duration
	return self

func set_kicker(p_kicker: Player) -> BallStateData:
	kicker = p_kicker
	return self
