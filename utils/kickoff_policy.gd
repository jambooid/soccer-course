class_name KickoffPolicy
extends RefCounted

static func should_start(ticks_waited: int, timeout_ticks: int, input_requested: bool) -> bool:
	return input_requested or ticks_waited >= timeout_ticks
