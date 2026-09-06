class_name ReplayBuffer
extends RefCounted

## Fixed-size snapshot history. It never owns or mutates simulation state.

var capacity := 360
var _frames: Array[MatchSnapshot] = []

func _init(max_frames: int = 360) -> void:
	capacity = maxi(max_frames, 1)

func append(snapshot: MatchSnapshot) -> void:
	_frames.append(snapshot.copy())
	while _frames.size() > capacity:
		_frames.pop_front()

func clear() -> void:
	_frames.clear()

func size() -> int:
	return _frames.size()

func snapshot_frames(before: int = 180, after: int = 0) -> Array[MatchSnapshot]:
	if _frames.is_empty():
		return []
	var start := maxi(0, _frames.size() - maxi(before, 1))
	var finish := mini(_frames.size(), _frames.size() + maxi(after, 0))
	var result: Array[MatchSnapshot] = []
	for index in range(start, finish):
		result.append(_frames[index].copy())
	return result

func latest() -> MatchSnapshot:
	if _frames.is_empty():
		return null
	return _frames.back().copy()
