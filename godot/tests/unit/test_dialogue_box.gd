## DialogueBox 测试：逐字推进 + 按键全显/关闭（渲染无关的逻辑）。
extends GutTest


func _box() -> DialogueBox:
	var b := DialogueBox.new()
	b.setup([], [
		{"type": "text", "ch": "5"},
		{"type": "text", "ch": "金"},
		{"type": "newline"},
		{"type": "text", "ch": "幣"},
	])
	add_child_autofree(b)
	return b


func _press(action: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev


func test_starts_not_fully_revealed() -> void:
	var b := _box()
	assert_false(b.is_fully_revealed(), "刚开始尚未逐字显示完")


func test_reveal_all_shows_everything() -> void:
	var b := _box()
	b.reveal_all()
	assert_true(b.is_fully_revealed())
	assert_eq(b.reveal_count(), 4)


func test_text_tokens_splits_string_per_char() -> void:
	var t := DialogueBox.text_tokens("A酒")
	assert_eq(t.size(), 2)
	assert_eq(t[0], {"type": "text", "ch": "A"})
	assert_eq(t[1], {"type": "text", "ch": "酒"})


func test_first_key_reveals_all_second_closes() -> void:
	var b := _box()
	watch_signals(b)
	b._unhandled_input(_press("ui_accept"))   # 未显完 → 全显
	assert_true(b.is_fully_revealed())
	assert_signal_not_emitted(b, "closed")
	b._unhandled_input(_press("ui_accept"))   # 已显完 → 关闭
	assert_signal_emitted(b, "closed")


func test_text_tokens_turns_line_breaks_into_newline_tokens() -> void:
	var t := DialogueBox.text_tokens("甲\n乙")
	assert_eq(t.size(), 3)
	assert_eq(t[1]["type"], "newline", "多行回话（如行情表）要换行，不是画一个换行符")
	assert_eq(t[2]["ch"], "乙")
