## PortSession：港口玩法状态机（纯逻辑，不需要场景树/渲染）。
extends GutTest

const TAVERN := 1
const BANK := 8


func _story_session(slot: int, port_id := 0) -> PortSession:
	var events := {
		"scenario": 1,
		"chapters": [{"index": 0, "entries": [
			{"trigger_id": "%04x" % slot, "label": "L0"},
		], "script": [
			{"label": "L0"},
			{"op": "say", "text": "snr1/0"},
			{"op": "wait"},
			{"op": "end"},
		]}],
	}
	var s := PortSession.new()
	s.port_id = port_id
	s.event_script = EventScript.new(events, PackedStringArray(["〔店主〕\n請進！"]))
	s.game_state = GameState.new(1, 0)
	return s


func test_starts_walking() -> void:
	var s := PortSession.new()
	assert_eq(s.mode, PortSession.Mode.WALKING)
	assert_eq(s.slot, -1)


func test_door_without_story_opens_facility_menu() -> void:
	var s := PortSession.new()
	assert_true(s.enter_door(TAVERN))
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)
	assert_eq(s.slot, TAVERN)


func test_door_with_story_plays_cutscene_then_facility() -> void:
	var s := _story_session(TAVERN)
	s.enter_door(TAVERN)
	assert_eq(s.mode, PortSession.Mode.CUTSCENE)
	assert_not_null(s.interp, "剧情解释器已就绪，供表现层演出")
	assert_true(s.story_finished())
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)
	assert_eq(s.slot, TAVERN)
	assert_null(s.interp)


func test_story_keyed_to_another_port_is_ignored() -> void:
	var s := _story_session(TAVERN, 3)
	s.enter_door(TAVERN)
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)


func test_leave_returns_to_walking() -> void:
	var s := PortSession.new()
	s.enter_door(TAVERN)
	assert_true(s.leave())
	assert_eq(s.mode, PortSession.Mode.WALKING)
	assert_eq(s.slot, -1)


func test_deposit_goes_through_amount_entry() -> void:
	var s := PortSession.new()
	s.enter_door(BANK)
	assert_eq(s.choose(0), "", "存款进入金额输入，无即时反馈")
	assert_eq(s.mode, PortSession.Mode.AMOUNT_ENTRY)
	assert_eq(s.amount_cap, World.STARTING_GOLD, "存款上限 = 现金")
	assert_eq(s.confirm_amount(1000), "現金 %d　存款 1000" % (World.STARTING_GOLD - 1000))
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)
	assert_eq(s.player_state.bank, 1000)


func test_withdraw_cap_is_bank_balance() -> void:
	var s := PortSession.new()
	s.player_state = PlayerState.new(0, 800)
	s.enter_door(BANK)
	s.choose(1)
	assert_eq(s.amount_cap, 800)
	s.confirm_amount(300)
	assert_eq(s.player_state.gold, 300)
	assert_eq(s.player_state.bank, 500)


func test_nothing_to_move_reports_balance_and_stays_in_menu() -> void:
	var s := PortSession.new()
	s.enter_door(BANK)
	assert_eq(s.choose(1), "現金 %d　存款 0" % World.STARTING_GOLD, "没有存款可提")
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)


func test_cancel_amount_moves_no_money() -> void:
	var s := PortSession.new()
	s.enter_door(BANK)
	s.choose(0)
	assert_true(s.cancel_amount())
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)
	assert_eq(s.player_state.gold, World.STARTING_GOLD)


func test_amount_over_cap_is_rejected() -> void:
	var s := PortSession.new()
	s.enter_door(BANK)
	s.choose(0)
	assert_eq(s.confirm_amount(World.STARTING_GOLD + 1), "", "超过上限不搬钱")
	assert_eq(s.mode, PortSession.Mode.AMOUNT_ENTRY, "仍在输入")
	assert_eq(s.player_state.bank, 0)


func test_unimplemented_item_says_not_open_yet() -> void:
	var s := PortSession.new()
	s.enter_door(TAVERN)
	assert_eq(s.choose(0), "（此功能尚未開放）")
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)


func test_transitions_from_the_wrong_mode_are_refused() -> void:
	var s := PortSession.new()
	assert_false(s.leave(), "港口里没有设施可离开")
	assert_false(s.story_finished())
	assert_false(s.cancel_amount())
	assert_eq(s.choose(0), "")
	s.enter_door(TAVERN)
	assert_false(s.enter_door(BANK), "设施里不能再进另一扇门")
	assert_eq(s.slot, TAVERN)
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)


func test_menu_opens_from_walking_and_closes_back() -> void:
	var s := PortSession.new()
	assert_true(s.open_menu())
	assert_eq(s.mode, PortSession.Mode.GAME_MENU)
	assert_false(s.open_menu(), "已开着")
	assert_true(s.close_menu())
	assert_eq(s.mode, PortSession.Mode.WALKING)


func test_menu_is_refused_outside_walking() -> void:
	var s := PortSession.new()
	assert_false(s.close_menu(), "没开着选单")
	s.enter_door(TAVERN)
	assert_false(s.open_menu(), "设施里不开选单")
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)
	assert_false(s.close_menu())


func test_open_menu_blocks_port_actions() -> void:
	var s := PortSession.new()
	s.open_menu()
	assert_false(s.enter_door(TAVERN), "选单开着不能进门")
	assert_false(s.leave())
	assert_eq(s.choose(0), "")
	assert_eq(s.mode, PortSession.Mode.GAME_MENU)


func test_menu_detail_for_status_shows_port_name_day_and_balance() -> void:
	var s := PortSession.new()
	s.port_id = 1
	s.world.day = 9
	var lines := s.menu_detail(0, 3).split("\n")
	assert_eq(lines[0], GameMenu.items(0)[3]["desc"])
	assert_string_contains(lines[-1], "塞維利亞")
	assert_string_contains(lines[-1], "第 9 日")
	assert_string_contains(lines[-1], s.balance_line())


func test_menu_detail_marks_unopened_items() -> void:
	var s := PortSession.new()
	assert_eq(s.menu_detail(1, 0), "%s\n%s" % [GameMenu.items(1)[0]["desc"], PortSession.NOT_OPEN_YET])
	assert_eq(s.menu_detail(3, 3), GameMenu.items(3)[3]["desc"], "已开放的项只有说明")
	assert_eq(s.menu_detail(0, 99), "")


const MARKET := 0
const BUY := 0
const SELL := 1
const PRICES := 3


func _at_market(gold := World.STARTING_GOLD) -> PortSession:
	var s := PortSession.new()
	s.player_state = PlayerState.new(gold, 0)
	s.enter_door(MARKET)
	return s


func test_buying_goes_pick_then_amount_then_back_to_menu() -> void:
	var s := _at_market()
	var good: Dictionary = Market.goods(0)[0]
	assert_eq(s.choose(BUY), "", "进入选货，无即时反馈")
	assert_eq(s.mode, PortSession.Mode.PICK)
	assert_string_contains(s.pick_options[0]["label"], good["label"])
	assert_string_contains(s.pick_options[0]["label"], str(good["buy"]), "选货行标出单价")
	assert_true(s.pick(0))
	assert_eq(s.mode, PortSession.Mode.AMOUNT_ENTRY)
	var line := s.confirm_amount(5)
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)
	assert_eq(s.player_state.gold, World.STARTING_GOLD - 5 * good["buy"])
	assert_eq(s.player_state.cargo, {good["key"]: 5})
	assert_string_contains(line, good["label"], "店主报出成交")


func test_buy_cap_is_what_the_gold_affords() -> void:
	var good: Dictionary = Market.goods(0)[0]
	var s := _at_market(good["buy"] * 3 + 1)
	s.choose(BUY)
	s.pick(0)
	assert_eq(s.amount_cap, 3)
	assert_eq(s.confirm_amount(4), "", "超过上限不成交")
	assert_eq(s.player_state.cargo, {})


func test_buy_cap_is_the_free_hold_when_gold_is_plentiful() -> void:
	var s := _at_market(1000000)
	s.player_state.cargo = {"pepper": 30}
	s.choose(BUY)
	s.pick(0)
	assert_eq(s.amount_cap, s.player_state.hold - 30)


func test_only_affordable_goods_are_offered() -> void:
	var cheapest: Dictionary = Market.goods(0)[0]
	for g: Dictionary in Market.goods(0):
		if g["buy"] < cheapest["buy"]:
			cheapest = g
	var s := _at_market(cheapest["buy"])
	s.choose(BUY)
	assert_eq(s.pick_options.size(), 1)
	assert_string_contains(s.pick_options[0]["label"], cheapest["label"])


func test_buying_with_no_gold_or_no_room_gets_a_line_and_stays_in_menu() -> void:
	var broke := _at_market(0)
	assert_ne(broke.choose(BUY), "")
	assert_eq(broke.mode, PortSession.Mode.FACILITY_MENU)
	var full := _at_market()
	full.player_state.cargo = {"pepper": full.player_state.hold}
	assert_ne(full.choose(BUY), "")
	assert_eq(full.mode, PortSession.Mode.FACILITY_MENU)


func test_selling_offers_only_held_goods_and_caps_at_the_quantity() -> void:
	var s := _at_market(0)
	var good: Dictionary = Market.goods(0)[1]
	s.player_state.cargo = {good["key"]: 7}
	assert_eq(s.choose(SELL), "")
	assert_eq(s.mode, PortSession.Mode.PICK)
	assert_eq(s.pick_options.size(), 1)
	assert_string_contains(s.pick_options[0]["label"], good["label"])
	assert_string_contains(s.pick_options[0]["label"], str(good["sell"]))
	s.pick(0)
	assert_eq(s.amount_cap, 7)
	s.confirm_amount(7)
	assert_eq(s.player_state.gold, 7 * good["sell"])
	assert_eq(s.player_state.cargo, {})
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)


func test_selling_with_nothing_the_port_trades_gets_a_line() -> void:
	var s := _at_market()
	assert_ne(s.choose(SELL), "", "船舱空")
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)
	s.player_state.cargo = {"amber": 3}
	assert_ne(s.choose(SELL), "", "这座港没给琥珀标价，不收")
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)


func test_buying_then_selling_in_the_same_port_loses_the_spread() -> void:
	var s := _at_market()
	var good: Dictionary = Market.goods(0)[0]
	s.choose(BUY)
	s.pick(0)
	s.confirm_amount(10)
	s.choose(SELL)
	s.pick(0)
	s.confirm_amount(10)
	assert_eq(s.player_state.gold, World.STARTING_GOLD - 10 * (good["buy"] - good["sell"]))


func test_cancel_pick_returns_to_menu_without_trading() -> void:
	var s := _at_market()
	s.choose(BUY)
	assert_true(s.cancel_pick())
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)
	assert_eq(s.pick_options, [])
	assert_eq(s.player_state.gold, World.STARTING_GOLD)


func test_cancel_amount_after_pick_trades_nothing() -> void:
	var s := _at_market()
	s.choose(BUY)
	s.pick(0)
	assert_true(s.cancel_amount())
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)
	assert_eq(s.player_state.cargo, {})


func test_pick_is_refused_out_of_range_or_out_of_mode() -> void:
	var s := _at_market()
	assert_false(s.pick(0), "还没选买卖")
	assert_false(s.cancel_pick())
	s.choose(BUY)
	assert_false(s.pick(-1))
	assert_false(s.pick(s.pick_options.size()))
	assert_eq(s.mode, PortSession.Mode.PICK)
	assert_false(s.leave(), "选货时不能直接离开设施")
	assert_eq(s.choose(SELL), "", "选货时菜单不响应")
	assert_eq(s.mode, PortSession.Mode.PICK)


func test_show_prices_lists_every_good_the_port_trades() -> void:
	var s := _at_market()
	var line := s.choose(PRICES)
	for g: Dictionary in Market.goods(0):
		assert_string_contains(line, g["label"])
		assert_string_contains(line, str(g["buy"]))
		assert_string_contains(line, str(g["sell"]))
	assert_gt(line.split("\n").size(), 1, "多行")
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)


func test_menu_detail_for_cargo_lists_what_is_held() -> void:
	var s := PortSession.new()
	var empty := s.menu_detail(0, 5)
	assert_false(empty.contains(PortSession.NOT_OPEN_YET), "貨物一覽已开放")
	var good: Dictionary = Market.goods(0)[0]
	s.player_state.cargo = {good["key"]: 12}
	var detail := s.menu_detail(0, 5)
	assert_string_contains(detail, good["label"])
	assert_string_contains(detail, "12")
	assert_ne(detail, empty)


const SAVE_PATH := "user://test_tmp/port_session.json"
const SYSTEM := 3
const SAVE := 1
const LOAD := 2


func after_all() -> void:
	DirAccess.remove_absolute(SAVE_PATH)


func _in_menu(world: World = null) -> PortSession:
	DirAccess.remove_absolute(SAVE_PATH)
	var s := PortSession.new(world)
	s.save_path = SAVE_PATH
	s.open_menu()
	return s


func test_session_plays_on_the_world_it_is_given() -> void:
	var w := World.new()
	var s := PortSession.new(w)
	s.port_id = 4
	s.enter_door(BANK)
	s.choose(0)
	s.confirm_amount(700)
	assert_eq([w.player.gold, w.player.bank, w.port_id], [World.STARTING_GOLD - 700, 700, 4])
	var next := PortSession.new(w)
	assert_eq(next.balance_line(), s.balance_line(), "换一个会话（换场景）看到的是同一份状态")


func test_save_writes_the_world_and_the_detail_pane_confirms() -> void:
	var s := _in_menu()
	s.world.player.deposit(250)
	assert_false(s.menu_detail(SYSTEM, SAVE).contains("已儲存"))
	assert_true(s.save_game())
	assert_string_contains(s.menu_detail(SYSTEM, SAVE), "進度已儲存")
	assert_false(s.menu_detail(SYSTEM, LOAD).contains("已儲存"), "提示只挂在儲存那一项")
	assert_eq(SaveFile.load(SAVE_PATH).player.bank, 250)
	s.close_menu()
	s.open_menu()
	assert_false(s.menu_detail(SYSTEM, SAVE).contains("已儲存"), "重开选单不留旧提示")


func test_save_and_load_only_work_from_the_game_menu() -> void:
	var s := _in_menu()
	s.save_game()
	s.close_menu()
	DirAccess.remove_absolute(SAVE_PATH)
	assert_false(s.save_game())
	assert_false(SaveFile.exists(SAVE_PATH))


func test_load_returns_the_saved_world() -> void:
	var s := _in_menu()
	s.world.player.deposit(250)
	s.save_game()
	s.world.player.withdraw(250)
	var loaded := s.load_game()
	assert_not_null(loaded)
	assert_ne(loaded, s.world)
	assert_eq(loaded.player.bank, 250)


func test_load_without_a_save_says_so() -> void:
	var s := _in_menu()
	assert_null(s.load_game())
	assert_string_contains(s.menu_detail(SYSTEM, LOAD), "還沒有存檔")


func test_load_of_a_corrupt_save_says_so() -> void:
	var s := _in_menu()
	s.save_game()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string("{")
	f.close()
	assert_null(s.load_game())
	assert_string_contains(s.menu_detail(SYSTEM, LOAD), "損毀")


const HARBOR := 3
const SET_SAIL := 0
const SEVILLE := 1


func test_setting_sail_from_the_harbor_picks_a_destination_and_travels() -> void:
	var s := PortSession.new()
	s.enter_door(HARBOR)
	assert_eq(s.choose(SET_SAIL), "")
	assert_eq(s.mode, PortSession.Mode.PICK)
	assert_eq(s.pick_options.size(), Market.routes(0).size())
	assert_string_contains(s.pick_options[0]["label"], "塞維利亞")
	assert_string_contains(s.pick_options[0]["label"], "4", "列出航程日数")
	assert_true(s.pick(0))
	assert_eq(s.mode, PortSession.Mode.SAILED)
	assert_eq([s.world.port_id, s.world.day], [SEVILLE, 5])
	assert_eq(s.world.player.gold, World.STARTING_GOLD, "航行不花钱")
	assert_eq(s.world.take_notice(), "航行 4 日，抵達塞維利亞。")


func test_cancelling_the_destination_pick_at_the_harbor_returns_to_its_menu() -> void:
	var s := PortSession.new()
	s.enter_door(HARBOR)
	s.choose(SET_SAIL)
	assert_true(s.cancel_pick())
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)
	assert_eq([s.world.port_id, s.world.day], [0, 1])
	assert_true(s.leave())


func test_departure_zone_opens_the_destination_pick_from_walking() -> void:
	var s := PortSession.new()
	assert_true(s.open_departure())
	assert_eq(s.mode, PortSession.Mode.PICK)
	assert_string_contains(s.pick_options[0]["label"], "塞維利亞")
	assert_false(s.open_departure(), "已经在选了")
	assert_true(s.cancel_pick())
	assert_eq(s.mode, PortSession.Mode.WALKING, "从哪儿开的回哪儿")
	s.open_departure()
	assert_true(s.pick(0))
	assert_eq([s.mode, s.world.port_id], [PortSession.Mode.SAILED, SEVILLE])


func test_departure_is_refused_outside_walking() -> void:
	var s := PortSession.new()
	s.enter_door(TAVERN)
	assert_false(s.open_departure())
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)


func test_a_port_without_routes_cannot_be_left() -> void:
	var s := PortSession.new()
	s.port_id = 999
	assert_false(s.open_departure())
	s.enter_door(HARBOR)
	assert_ne(s.choose(SET_SAIL), "", "港务局说明没有航线")
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)


func test_a_session_that_sailed_accepts_nothing_more() -> void:
	var s := PortSession.new()
	s.open_departure()
	s.pick(0)
	assert_false(s.enter_door(TAVERN))
	assert_false(s.open_menu())
	assert_false(s.open_departure())
	assert_false(s.cancel_pick())
	assert_eq(s.mode, PortSession.Mode.SAILED)


func test_goods_bought_in_one_port_sell_for_more_in_the_other() -> void:
	var w := World.new()
	var s := PortSession.new(w)
	s.enter_door(MARKET)
	s.choose(BUY)
	var row: int = s.pick_options.map(func(r: Dictionary) -> String: return r["key"]).find("woolens")
	s.pick(row)
	s.confirm_amount(20)
	s.leave()
	s.open_departure()
	s.pick(0)
	var there := PortSession.new(w)
	there.enter_door(MARKET)
	there.choose(SELL)
	there.pick(0)
	there.confirm_amount(20)
	assert_gt(w.player.gold, World.STARTING_GOLD, "低买高卖赚到钱")


const PALACE := 5


func _lines(s: PortSession) -> Array:
	var out := []
	while true:
		var b := s.interp.next_beat()
		if b["kind"] == "line":
			out.append(b["body"])
		elif b["kind"] == "end":
			break
	s.story_finished()
	return out


func _past_intro() -> World:
	var w := World.new_game()
	World.current = null
	var s := PortSession.new(w)
	s.arrive()
	_lines(s)
	return w


func test_new_game_arrival_plays_the_intro_then_returns_to_walking() -> void:
	var s := PortSession.new(World.new_game())
	World.current = null
	assert_true(s.arrive())
	assert_eq(s.mode, PortSession.Mode.CUTSCENE)
	assert_false(s.enter_door(TAVERN), "开场没演完不能进门")
	assert_between(_lines(s).size(), 8, 12)
	assert_eq(s.mode, PortSession.Mode.WALKING, "开场不通向任何设施")
	assert_eq(s.slot, -1)
	assert_true(s.enter_door(TAVERN))


func test_intro_does_not_replay_on_a_later_port_entry_or_after_loading() -> void:
	var w := _past_intro()
	var again := PortSession.new(w)
	assert_false(again.arrive(), "回到里斯本不重演")
	assert_eq(again.mode, PortSession.Mode.WALKING)
	var loaded := World.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())))
	assert_false(PortSession.new(loaded).arrive(), "读档后不重演")


func test_arrival_without_a_story_does_nothing() -> void:
	var s := PortSession.new()
	assert_false(s.arrive())
	assert_eq(s.mode, PortSession.Mode.WALKING)
	s.open_menu()
	assert_false(s.arrive(), "只能从走路进剧情")


func test_palace_opens_as_usual_before_the_goal_is_met() -> void:
	var s := PortSession.new(_past_intro())
	s.enter_door(PALACE)
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)


func test_palace_congratulates_once_when_the_goal_is_met_then_opens() -> void:
	var w := _past_intro()
	w.player.gold = 9000
	w.player.deposit(4000)
	w.player.gold += 1000
	var s := PortSession.new(w)
	s.enter_door(PALACE)
	assert_eq(s.mode, PortSession.Mode.CUTSCENE)
	assert_gt(_lines(s).size(), 0)
	assert_eq([s.mode, s.slot], [PortSession.Mode.FACILITY_MENU, PALACE], "道贺完照常进王宫")
	s.leave()
	s.enter_door(PALACE)
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU, "只道贺一次")
	assert_true(s.enter_door(TAVERN) or s.leave(), "游戏照常继续")


func test_menu_detail_for_status_shows_the_goal_and_progress() -> void:
	var s := PortSession.new(_past_intro())
	var detail := s.menu_detail(0, 3)
	assert_string_contains(detail, s.world.goal()["text"])
	assert_string_contains(detail, str(World.STARTING_GOLD))
	s.world.player.gold = 10000
	assert_string_contains(s.menu_detail(0, 3), "已達成")
