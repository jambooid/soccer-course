extends Node
## 输入缓冲系统
## 玩家在动画播放期间按下的按键，会进入缓冲队列（窗口约 200ms）
## 当动画到达"可接受输入帧"时，检查缓冲队列，如果有有效输入则立即执行
## 目的：玩家不会因为"按早了几帧"而操作失效，提升操作跟手感

const BUFFER_WINDOW_MS := 200

# action_string → timestamp_ms
# 用 action 字符串作为 key（与 project.godot 中的 action 名一致）
var _buffer: Dictionary = {}


func _input(event: InputEvent) -> void:
    # 捕获所有按键按下事件，写入缓冲
    if event is InputEventKey and event.pressed and not event.echo:
        # 找出这个 key 对应的所有 action
        for action_name in InputMap.get_actions():
            if InputMap.action_has_event(action_name, event):
                press(action_name)


func press(action: String) -> void:
    _buffer[action] = GameManager.get_match_time_ms()


func consume(action: String) -> bool:
    if _buffer.has(action):
        if GameManager.get_match_time_ms() - _buffer[action] < BUFFER_WINDOW_MS:
            _buffer.erase(action)
            return true
        _buffer.erase(action)
    return false


func consume_any(actions: Array) -> String:
    for action in actions:
        if consume(action):
            return action
    return ""


func has(action: String) -> bool:
    if not _buffer.has(action):
        return false
    if GameManager.get_match_time_ms() - _buffer[action] >= BUFFER_WINDOW_MS:
        _buffer.erase(action)
        return false
    return true


func clear() -> void:
    _buffer.clear()


func clear_action(action: String) -> void:
    if _buffer.has(action):
        _buffer.erase(action)
