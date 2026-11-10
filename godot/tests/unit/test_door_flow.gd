## 进门流程：剧情优先 → 设施 → 银行存取（与港口渲染方式无关）。
extends GutTest

const MARKET := 0
const TAVERN := 1
const BANK := 8


func _flow() -> DoorFlow:
	var f := DoorFlow.new()
	add_child_autofree(f)
	return f


func _story_flow(slot: int) -> DoorFlow:
	var f := _flow()
	var events := {
		"scenario": 1,
		"chapters": [{"index": 0, "entries": [
			{"trigger_id": "%04x" % slot, "label": "L0"},
		], "script": [
			{"label": "L0"},
			{"op": "window", "arg": 1},
			{"op": "portrait", "kao": 6},
			{"op": "say", "text": "snr1/0"},
			{"op": "wait"},
			{"op": "end"},
		]}],
	}
	var st := GameState.new(1, 0)
	st.set_name("n", "阿明")
	f.inject_story(EventScript.new(events, PackedStringArray(["〔店主〕\n$n，請進！"])), st)
	return f


## 进设施并关掉进门寒暄，露出可交互菜单。
func _inside(slot: int, f: DoorFlow = null) -> DoorFlow:
	f = f if f != null else _flow()
	f.open(slot)
	if f.facility_scene._dialogue != null:
		f.facility_scene._dialogue.closed.emit()
	return f


func test_door_without_story_enters_facility() -> void:
	var f := _flow()
	f.open(TAVERN)
	assert_false(f.is_in_cutscene())
	assert_true(f.is_in_facility())


func test_exit_returns_to_port() -> void:
	var f := _inside(TAVERN)
	f.facility_scene._request_exit()
	assert_false(f.is_busy(), "退出后不再占用输入")


func test_story_at_door_plays_before_facility() -> void:
	var f := _story_flow(TAVERN)
	f.open(TAVERN)
	assert_true(f.is_in_cutscene(), "门登记了事件→先演剧情")
	assert_false(f.is_in_facility(), "剧情演完前不进设施")
	assert_eq(f.director.current_line()["body"], "阿明，請進！", "$n 代入并显示")


func test_story_finish_then_enters_facility() -> void:
	var f := _story_flow(TAVERN)
	f.open(TAVERN)
	f.director.advance()
	assert_false(f.is_in_cutscene(), "剧情结束")
	assert_true(f.is_in_facility(), "剧情演完→照常进设施菜单")


func test_story_for_other_port_is_ignored() -> void:
	var f := _story_flow(TAVERN)
	f.port_id = 3
	f.open(TAVERN)
	assert_false(f.is_in_cutscene(), "事件键带港号，别的港不触发")
	assert_true(f.is_in_facility())


func test_bank_deposit_moves_gold_to_bank() -> void:
	var f := _inside(BANK)
	f.facility_scene.menu_selected.emit(0, "存款")
	assert_not_null(f.amount_entry, "存款应弹金额输入")
	f.amount_entry.adjust(AmountEntry.STEP_BIG)
	f.amount_entry.confirm()
	assert_eq(f.player_state.gold, World.STARTING_GOLD - 1000)
	assert_eq(f.player_state.bank, 1000)
	assert_null(f.amount_entry, "确认后金额模态关闭")


func test_bank_withdraw_moves_bank_to_gold() -> void:
	var f := _flow()
	f.player_state = PlayerState.new(0, 800)
	_inside(BANK, f)
	f.facility_scene.menu_selected.emit(1, "提款")
	f.amount_entry.adjust(AmountEntry.STEP_SMALL * 3)
	f.amount_entry.confirm()
	assert_eq(f.player_state.gold, 300)
	assert_eq(f.player_state.bank, 500)


func test_bank_cancel_leaves_funds_unchanged() -> void:
	var f := _inside(BANK)
	f.facility_scene.menu_selected.emit(0, "存款")
	f.amount_entry.adjust(AmountEntry.STEP_BIG)
	f.amount_entry.cancel()
	assert_eq(f.player_state.gold, World.STARTING_GOLD, "取消不动钱")
	assert_null(f.amount_entry)


func test_unimplemented_menu_item_says_not_open_yet() -> void:
	var f := _inside(TAVERN)
	f.facility_scene.menu_selected.emit(0, "賭博")
	assert_null(f.amount_entry, "非银行不弹金额输入")
	assert_true(f.facility_scene.has_dialogue(), "以一句反馈占位")


func test_market_buy_goes_through_pick_list_and_amount() -> void:
	var f := _inside(MARKET)
	var good: Dictionary = Market.goods(0)[0]
	f.facility_scene.menu_selected.emit(0, "採購貨物")
	assert_not_null(f.pick_list, "採購应弹选货列表")
	assert_null(f.amount_entry)
	f.pick_list.confirm()
	assert_null(f.pick_list, "选定后选货列表关闭")
	assert_not_null(f.amount_entry, "接着输入数量")
	_press("ui_up")
	assert_eq(f.amount_entry.amount(), 1, "货物按件数调，不是按百")
	_press("ui_right")
	assert_eq(f.amount_entry.amount(), 11)
	f.amount_entry.confirm()
	assert_eq(f.player_state.cargo, {good["key"]: 11})
	assert_eq(f.player_state.gold, World.STARTING_GOLD - 11 * good["buy"])
	assert_true(f.facility_scene.has_dialogue(), "店主报出成交")


func test_escape_in_pick_list_returns_to_facility_menu() -> void:
	var f := _inside(MARKET)
	f.facility_scene.menu_selected.emit(0, "採購貨物")
	_press("ui_cancel")
	assert_null(f.pick_list)
	assert_true(f.is_in_facility(), "ESC 只关选货列表，不离开设施")
	assert_null(f.game_menu)


func test_keys_in_pick_list_do_not_move_the_facility_menu() -> void:
	var f := _inside(MARKET)
	f.facility_scene.menu_selected.emit(0, "採購貨物")
	var before := f.facility_scene.selected_index()
	_press("ui_down")
	assert_eq(f.pick_list.selected_index(), 1)
	assert_eq(f.facility_scene.selected_index(), before)


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	get_viewport().push_input(ev)


func test_escape_while_walking_opens_menu_and_it_stays_open() -> void:
	var f := _flow()
	_press("ui_cancel")
	assert_not_null(f.game_menu, "ESC 打开选单，同一次按键不会又把它关掉")
	assert_true(f.is_busy(), "选单开着时港口不走动")
	assert_false(f.is_in_facility())


func test_escape_in_menu_closes_it() -> void:
	var f := _flow()
	_press("ui_cancel")
	_press("ui_cancel")
	assert_null(f.game_menu)
	assert_false(f.is_busy())


func test_doors_do_not_open_under_the_menu() -> void:
	var f := _flow()
	f.open_menu()
	f.open(TAVERN)
	assert_null(f.facility_scene)
	assert_not_null(f.game_menu)


func test_escape_out_of_facility_does_not_open_menu() -> void:
	var f := _inside(TAVERN)
	_press("ui_cancel")
	assert_false(f.is_busy(), "回到港口")
	assert_null(f.game_menu, "同一次 ESC 不再开选单")


func test_menu_not_available_inside_facility() -> void:
	var f := _inside(TAVERN)
	f.open_menu()
	assert_null(f.game_menu)
	assert_true(f.is_in_facility())


func test_unopened_menu_item_keeps_menu_open() -> void:
	var f := _flow()
	f.open_menu()
	f.game_menu.move_category(1)
	f.game_menu.activate()
	assert_not_null(f.game_menu)
	f.close_menu()
	assert_null(f.game_menu)


func test_saving_from_the_game_menu_writes_the_save_file() -> void:
	var path := "user://test_tmp/door_flow.json"
	DirAccess.remove_absolute(path)
	var f := _flow()
	f.session.save_path = path
	f.player_state.deposit(400)
	f.open_menu()
	f.game_menu.move_category(3)
	f.game_menu.move_item(1)
	_press("ui_accept")
	assert_eq(SaveFile.load(path).player.bank, 400)
	assert_string_contains(f.game_menu.detail_text(), "進度已儲存")
	DirAccess.remove_absolute(path)


func test_loading_with_no_save_stays_in_the_menu_and_says_so() -> void:
	var path := "user://test_tmp/door_flow.json"
	DirAccess.remove_absolute(path)
	var f := _flow()
	f.session.save_path = path
	f.open_menu()
	f.game_menu.move_category(3)
	f.game_menu.move_item(2)
	_press("ui_accept")
	assert_not_null(f.game_menu, "没有存档：留在选单")
	assert_string_contains(f.game_menu.detail_text(), "還沒有存檔")
