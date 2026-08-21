class_name GameStateData

var country_scored_on : String
var half : int = 1  # 1 = 上半场, 2 = 下半场

static func build() -> GameStateData:
	return GameStateData.new()

func set_country_scored_on(country: String) -> GameStateData:
	country_scored_on = country
	return self

func set_half(value: int) -> GameStateData:
	half = value
	return self
