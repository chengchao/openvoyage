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
