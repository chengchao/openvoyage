## FacilityScene（设施合成场景：标题 + 店员 + 菜单壳 + 退出）测试。
extends GutTest


func _scene(slot := 1) -> FacilityScene:
	var s := FacilityScene.new()
	s.setup(FacilityType.of(slot))
	add_child_autofree(s)
	return s


func test_title_shows_facility_name() -> void:
	var s := _scene(1)  # 酒馆
	assert_eq(s.facility_name(), "酒館")
	assert_string_contains(s.title_text(), "酒館")
	assert_eq(s.facility_type().key, &"tavern", "持有设施类型，供 M5 据 key 载入功能")


func test_has_shopkeeper_sprite() -> void:
	var s := _scene()
	assert_not_null(s.shopkeeper_texture(), "应有店主画（占位）")


func test_bank_menu_comes_with_the_game() -> void:
	var labels := _scene(8).menu_labels()  # 银行
	assert_eq(labels.size(), 5, "銀行 4 项 + 離開，不需要任何外部数据")
	assert_eq(labels[4], "離開", "末项恒为離開")
	assert_eq(Array(labels.slice(0, 4)), Array(FacilityActions.labels(&"bank")))


func test_menu_fits_inside_the_panel_for_every_facility() -> void:
	for ft in FacilityType.catalog():
		var s := _scene(ft.slot)
		await wait_frames(2)
		var last: Label = s._menu_items[-1]
		var panel := last.get_parent().get_parent() as Control
		assert_lte(last.get_global_rect().end.y, panel.get_global_rect().end.y, "%s 的菜单超出面板" % ft.key)


func test_cancel_emits_exit_requested() -> void:
	var s := _scene()
	watch_signals(s)
	s._request_exit()
	assert_signal_emitted(s, "exit_requested")


# --- 菜单选择（光标导航 + 选定） ---

func _fmenu_scene() -> FacilityScene:
	return _scene(8)  # 银行：4 项 + 離開


func test_selection_starts_at_first_item() -> void:
	var s := _fmenu_scene()
	assert_eq(s.selected_index(), 0)
	assert_eq(s.selected_label(), FacilityActions.labels(&"bank")[0])


func test_move_selection_wraps() -> void:
	var s := _fmenu_scene()  # 5 项，末项離開
	s.move_selection(-1)  # 从 0 上移 → 末项
	assert_eq(s.selected_index(), 4)
	assert_eq(s.selected_label(), "離開")
	s.move_selection(1)  # 下移 → 回首项
	assert_eq(s.selected_index(), 0)


func test_activate_leave_emits_exit() -> void:
	var s := _fmenu_scene()
	s.move_selection(-1)  # 选「離開」
	watch_signals(s)
	s.activate_selected()
	assert_signal_emitted(s, "exit_requested")


func test_activate_item_emits_menu_selected() -> void:
	var s := _fmenu_scene()  # 光标在首项
	watch_signals(s)
	s.activate_selected()
	assert_signal_emitted_with_parameters(s, "menu_selected", [0, FacilityActions.labels(&"bank")[0]])


func test_shows_greeting_dialogue_on_entry() -> void:
	var s := _scene(1)  # 酒馆
	assert_true(s.has_dialogue(), "进门应弹出店主寒暄对话框")
	assert_eq(s.spoken_line(), FacilityActions.greeting(&"tavern"), "寒暄是这家店自己的招呼语")


func test_closing_greeting_removes_dialogue() -> void:
	var s := _scene(1)
	s._dialogue.closed.emit()  # 关闭寒暄
	assert_false(s.has_dialogue(), "关闭后回到菜单")


# --- 玩家输入（经视口派发，与真机一致） ---

func _cancel() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	return ev


## 把一次左键点击交给该菜单项（GUT 自身界面盖在视口上，push_input 的鼠标事件到不了被测场景）。
func _click(s: FacilityScene, label: String) -> void:
	var item: Label = s._menu_items[s.menu_labels().find(label)]
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	item.gui_input.emit(ev)


func test_one_escape_leaves_even_while_greeting_is_open() -> void:
	var s := _scene(1)
	assert_true(s.has_dialogue(), "前提：寒暄对话框开着")
	watch_signals(s)
	get_viewport().push_input(_cancel())
	assert_signal_emitted(s, "exit_requested", "按一次 ESC 就离开设施")


func test_clicking_leave_exits() -> void:
	var s := _fmenu_scene()
	watch_signals(s)
	_click(s, "離開")
	assert_signal_emitted(s, "exit_requested", "鼠标点「離開」离开设施")


func test_clicking_a_menu_item_selects_it() -> void:
	var s := _fmenu_scene()
	watch_signals(s)
	var second := FacilityActions.labels(&"bank")[1]
	_click(s, second)
	assert_signal_emitted_with_parameters(s, "menu_selected", [1, second])
