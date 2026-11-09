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
	var s := PortSession.new(port_id)
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
	assert_eq(s.amount_cap, PortSession.STARTING_GOLD, "存款上限 = 现金")
	assert_eq(s.confirm_amount(1000), "現金 %d　存款 1000" % (PortSession.STARTING_GOLD - 1000))
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
	assert_eq(s.choose(1), "現金 %d　存款 0" % PortSession.STARTING_GOLD, "没有存款可提")
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)


func test_cancel_amount_moves_no_money() -> void:
	var s := PortSession.new()
	s.enter_door(BANK)
	s.choose(0)
	assert_true(s.cancel_amount())
	assert_eq(s.mode, PortSession.Mode.FACILITY_MENU)
	assert_eq(s.player_state.gold, PortSession.STARTING_GOLD)


func test_amount_over_cap_is_rejected() -> void:
	var s := PortSession.new()
	s.enter_door(BANK)
	s.choose(0)
	assert_eq(s.confirm_amount(PortSession.STARTING_GOLD + 1), "", "超过上限不搬钱")
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
