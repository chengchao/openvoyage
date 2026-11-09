## 进门流程：剧情优先 → 设施 → 银行存取（与港口渲染方式无关）。
extends GutTest

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
	assert_eq(f.player_state.gold, DoorFlow.STARTING_GOLD - 1000)
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
	assert_eq(f.player_state.gold, DoorFlow.STARTING_GOLD, "取消不动钱")
	assert_null(f.amount_entry)


func test_unimplemented_menu_item_says_not_open_yet() -> void:
	var f := _inside(TAVERN)
	f.facility_scene.menu_selected.emit(0, "賭博")
	assert_null(f.amount_entry, "非银行不弹金额输入")
	assert_true(f.facility_scene.has_dialogue(), "以一句反馈占位")
