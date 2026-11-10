## GoodsPick（选货模态：上下移光标、确定/取消）测试。
extends GutTest


func _pick() -> GoodsPick:
	var p := GoodsPick.new()
	p.setup("要買哪一種？", PackedStringArray(["葡萄酒", "食鹽", "砂糖"]))
	add_child_autofree(p)
	return p


func test_cursor_starts_on_first_row_and_wraps() -> void:
	var p := _pick()
	assert_eq(p.selected_index(), 0)
	p.move(-1)
	assert_eq(p.selected_index(), 2, "首项往上回绕到末项")
	p.move(1)
	assert_eq(p.selected_index(), 0)


func test_confirm_emits_the_selected_row() -> void:
	var p := _pick()
	p.move(1)
	watch_signals(p)
	p.confirm()
	assert_signal_emitted_with_parameters(p, "picked", [1])


func test_cancel_emits() -> void:
	var p := _pick()
	watch_signals(p)
	p.cancel()
	assert_signal_emitted(p, "cancelled")
