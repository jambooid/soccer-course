class_name MatchSnapshot
extends RefCounted

## Copy-only data passed to presentation systems. It has no gameplay methods.

var tick := 0
var phase := MatchFlow.Phase.KICKOFF
var half := 1
var clock := 0.0
var score_home := 0
var score_away := 0
var selected_player_id := -1
var carrier_id := -1
var players: Array = []
var ball: Dictionary = {}
var radar: Array = []
var event_label := ""

func _init(source: Dictionary = {}) -> void:
	if source.is_empty():
		return
	tick = int(source.get("tick", 0))
	phase = int(source.get("phase", MatchFlow.Phase.KICKOFF))
	half = int(source.get("half", 1))
	clock = float(source.get("clock", 0.0))
	score_home = int(source.get("score_home", 0))
	score_away = int(source.get("score_away", 0))
	selected_player_id = int(source.get("selected_player_id", -1))
	carrier_id = int(source.get("carrier_id", -1))
	players = source.get("players", []).duplicate(true)
	ball = source.get("ball", {}).duplicate(true)
	radar = source.get("radar", []).duplicate(true)
	event_label = str(source.get("event_label", ""))

func copy() -> MatchSnapshot:
	return MatchSnapshot.new(to_dict())

func to_dict() -> Dictionary:
	return {"tick": tick, "phase": phase, "half": half, "clock": clock,
		"score_home": score_home, "score_away": score_away,
		"selected_player_id": selected_player_id, "carrier_id": carrier_id,
		"players": players.duplicate(true), "ball": ball.duplicate(true),
		"radar": radar.duplicate(true), "event_label": event_label}
