## AmountEntry（金额输入模态：上下 ±小步、左右 ±大步、确定/取消）测试。
extends GutTest


func _entry(maxv := 5000, initial := 0) -> AmountEntry:
	var e := AmountEntry.new()
	e.setup("存入多少？", maxv, initial)
	add_child_autofree(e)
	return e


func test_setup_clamps_initial_into_range() -> void:
	assert_eq(_entry(1000, 9999).amount(), 1000, "初值不超过上限")
	assert_eq(_entry(1000, -50).amount(), 0, "初值不低于 0")


func test_adjust_clamps_to_zero_and_max() -> void:
	var e := _entry(300, 0)
	e.adjust(-100)
	assert_eq(e.amount(), 0, "不低于 0")
	e.adjust(100000)
	assert_eq(e.amount(), 300, "不超过上限")


func test_adjust_steps() -> void:
	var e := _entry(10000, 0)
	e.adjust(AmountEntry.STEP_SMALL)
	assert_eq(e.amount(), 100)
	e.adjust(AmountEntry.STEP_BIG)
	assert_eq(e.amount(), 1100)


func test_confirm_emits_amount() -> void:
	var e := _entry(5000, 0)
	e.adjust(AmountEntry.STEP_BIG)
	watch_signals(e)
	e.confirm()
	assert_signal_emitted_with_parameters(e, "confirmed", [1000])


func test_cancel_emits() -> void:
	var e := _entry()
	watch_signals(e)
	e.cancel()
	assert_signal_emitted(e, "cancelled")


# --- 鼠标：面板上的按钮 ---

func _button(e: AmountEntry, text: String) -> Button:
	for b in e.find_children("*", "Button", true, false):
		if b.text == text:
			return b
	return null


func test_buttons_adjust_by_small_and_large_step() -> void:
	var e := _entry(5000, 0)
	_button(e, "+1000").pressed.emit()
	_button(e, "+100").pressed.emit()
	_button(e, "-100").pressed.emit()
	assert_eq(e.amount(), 1000)
	_button(e, "-1000").pressed.emit()
	assert_eq(e.amount(), 0)


func test_buttons_confirm_and_cancel() -> void:
	var e := _entry(5000, 300)
	watch_signals(e)
	_button(e, "確定").pressed.emit()
	assert_signal_emitted_with_parameters(e, "confirmed", [300])
	_button(e, "取消").pressed.emit()
	assert_signal_emitted(e, "cancelled")


func test_clicked_button_does_not_steal_the_enter_key() -> void:
	var e := _entry()
	for b in e.find_children("*", "Button", true, false):
		assert_eq(b.focus_mode, Control.FOCUS_NONE, "%s 拿到焦点后 Enter 会变成再按它一次" % b.text)


func test_buttons_fit_inside_the_panel_on_screen() -> void:
	var e := _entry(99999, 0)
	await wait_frames(2)
	var panel: Panel = e.find_children("*", "Panel", true, false)[0]
	var screen := Rect2(Vector2.ZERO, e.get_viewport().get_visible_rect().size)
	assert_true(screen.encloses(panel.get_global_rect()), "面板 %s 超出屏幕" % panel.get_global_rect())
	for b in e.find_children("*", "Button", true, false):
		assert_true(panel.get_global_rect().encloses(b.get_global_rect()),
			"%s %s 超出面板 %s" % [b.text, b.get_global_rect(), panel.get_global_rect()])
