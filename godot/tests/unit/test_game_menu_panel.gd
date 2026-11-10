## GameMenuPanel：游戏内选单面板的导航、选定与详情。
extends GutTest

const INFO := 0
const FLEET := 1
const SYSTEM := 3
const STATUS := 3


func _panel(session := PortSession.new()) -> GameMenuPanel:
	session.open_menu()
	var p := GameMenuPanel.new()
	p.setup(session)
	add_child_autofree(p)
	return p


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	get_viewport().push_input(ev)


func test_opens_on_first_category_and_item() -> void:
	var p := _panel()
	assert_eq(p.category_index(), 0)
	assert_eq(p.item_index(), 0)
	assert_eq(Array(p.category_labels()), ["情報", "艦隊", "隨身物", "系統"])
	assert_eq(p.item_labels().size(), 10)
	assert_eq(p.item_labels()[STATUS], "主角情報")


func test_navigation_wraps() -> void:
	var p := _panel()
	p.move_category(-1)
	assert_eq(p.category_index(), SYSTEM)
	p.move_category(1)
	assert_eq(p.category_index(), INFO)
	p.move_item(-1)
	assert_eq(p.item_index(), 9)
	p.move_item(1)
	assert_eq(p.item_index(), 0)


func test_switching_category_resets_item_cursor_and_list() -> void:
	var p := _panel()
	p.move_item(4)
	p.move_category(1)
	assert_eq(p.item_index(), 0)
	assert_eq(p.item_labels().size(), 6)
	assert_eq(p.item_labels()[0], "更換船長")


func test_activate_requests_only_items_with_actions() -> void:
	var p := _panel()
	watch_signals(p)
	p.activate()
	p.move_category(FLEET)
	p.activate()
	assert_signal_not_emitted(p, "action_requested", "尚未開放的项不发动作")
	p.move_category(SYSTEM - FLEET)
	p.move_item(3)
	p.activate()
	assert_signal_emitted_with_parameters(p, "action_requested", [&"title"])


func test_detail_follows_cursor() -> void:
	var s := PortSession.new()
	var p := _panel(s)
	assert_eq(p.detail_text(), s.menu_detail(INFO, 0))
	p.move_item(STATUS)
	assert_eq(p.detail_text(), s.menu_detail(INFO, STATUS))
	assert_string_contains(p.detail_text(), s.balance_line())
	p.move_category(FLEET)
	assert_string_contains(p.detail_text(), PortSession.NOT_OPEN_YET)


func test_keyboard_drives_the_cursor() -> void:
	var p := _panel()
	watch_signals(p)
	_press("ui_right")
	assert_eq(p.category_index(), FLEET)
	_press("ui_left")
	_press("ui_down")
	_press("ui_down")
	_press("ui_down")
	_press("ui_up")
	assert_eq([p.category_index(), p.item_index()], [INFO, 2])
	_press("ui_down")
	_press("ui_accept")
	assert_signal_emitted_with_parameters(p, "action_requested", [&"status"])
	assert_signal_not_emitted(p, "close_requested")


func test_cancel_requests_close() -> void:
	var p := _panel()
	watch_signals(p)
	_press("ui_cancel")
	assert_signal_emitted(p, "close_requested")


## GUT 自身界面盖在视口上，push_input 的鼠标事件到不了被测场景，直接交给该行。
func _click(p: GameMenuPanel, text: String) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	for label: Label in p.find_children("*", "Label", true, false):
		if label.text == text and not label.is_queued_for_deletion():
			label.gui_input.emit(ev)
			return
	fail_test("找不到「%s」" % text)


func test_clicking_a_tab_selects_it_and_clicking_an_item_activates_it() -> void:
	var p := _panel()
	watch_signals(p)
	_click(p, "系統")
	assert_eq(p.category_index(), SYSTEM)
	assert_signal_not_emitted(p, "action_requested")
	_click(p, "回到標題")
	assert_eq(p.item_index(), 3)
	assert_signal_emitted_with_parameters(p, "action_requested", [&"title"])


func test_activating_save_shows_the_confirmation_at_once() -> void:
	var path := "user://test_tmp/game_menu_panel.json"
	var s := PortSession.new()
	s.save_path = path
	var p := _panel(s)
	p.action_requested.connect(func(action: StringName) -> void:
		if action == &"save":
			s.save_game())
	p.move_category(SYSTEM)
	p.move_item(1)
	p.activate()
	assert_string_contains(p._detail.text, "進度已儲存", "详情栏在选定后立即刷新")
	DirAccess.remove_absolute(path)
