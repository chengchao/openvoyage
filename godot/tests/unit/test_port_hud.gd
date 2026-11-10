## 港口 HUD：顶上一条显示港名/日期/现金/船舱/目标，底下一行操作提示只在走路时显示。
extends GutTest

const MARKET := 0
const BANK := 8


func _flow(world: World = null) -> DoorFlow:
	var f := DoorFlow.new()
	if world != null:
		f.session.world = world
	add_child_autofree(f)
	return f


func _new_game() -> World:
	var w := World.new_game()
	World.current = null
	return w


func test_status_shows_port_day_cash_hold_and_goal() -> void:
	var w := _new_game()
	w.day = 7
	var text := _flow(w).hud.status_text()
	for part: String in ["里斯本", "第 7 日", "現金 %d" % World.STARTING_GOLD, "船艙 0/100", "%d/10000" % World.STARTING_GOLD]:
		assert_string_contains(text, part)


func test_status_follows_a_purchase() -> void:
	var f := _flow(_new_game())
	var good: Dictionary = Market.goods(0)[0]
	f.open(MARKET)
	f.choose(0)
	f.pick(0)
	f.confirm_amount(5)
	var text := f.hud.status_text()
	assert_string_contains(text, "現金 %d" % (World.STARTING_GOLD - 5 * good["buy"]))
	assert_string_contains(text, "船艙 5/100")
	assert_string_contains(text, "%d/10000" % (World.STARTING_GOLD - 5 * good["buy"]), "目标进度跟着现金变")


func test_status_follows_a_deposit() -> void:
	var f := _flow(_new_game())
	f.open(BANK)
	f.choose(0)
	f.confirm_amount(500)
	assert_string_contains(f.hud.status_text(), "現金 %d" % (World.STARTING_GOLD - 500))
	assert_string_contains(f.hud.status_text(), "%d/10000" % World.STARTING_GOLD, "存款也算进目标")


func test_status_names_the_port_the_world_is_in() -> void:
	var w := _new_game()
	w.port_id = 1
	assert_string_contains(_flow(w).hud.status_text(), "塞維利亞")


func test_status_says_when_the_goal_is_met() -> void:
	var w := _new_game()
	w.player.gold = 12000
	assert_string_contains(_flow(w).hud.status_text(), "目標已達成")


func test_status_without_a_story_has_no_goal() -> void:
	assert_false(_flow().hud.status_text().contains("目標"))


func test_controls_hint_is_visible_only_while_walking() -> void:
	var f := _flow()
	assert_true(f.hud.hint_visible())
	for key: String in ["方向鍵", "Enter", "Esc"]:
		assert_string_contains(PortHud.HINT, key)
	f.open(MARKET)
	assert_false(f.hud.hint_visible(), "设施里不显示")
	f.leave()
	assert_true(f.hud.hint_visible())
	f.open_menu()
	assert_false(f.hud.hint_visible(), "选单开着不显示")


func test_controls_hint_is_hidden_during_the_intro() -> void:
	var f := _flow(_new_game())
	f.arrive()
	assert_false(f.hud.hint_visible())
	for _i in 20:
		if f.is_in_cutscene():
			f.director.advance()
	assert_true(f.hud.hint_visible())


func test_hud_sits_below_the_facility_and_menu_layers() -> void:
	var f := _flow()
	f.open(MARKET)
	assert_lt(f.hud.layer, f.facility_scene.layer)


func test_status_strip_steps_aside_for_the_game_menu() -> void:
	var f := _flow()
	assert_true(f.hud.status_visible())
	f.open(MARKET)
	assert_true(f.hud.status_visible(), "买卖时仍看得到现金与船舱")
	f.leave()
	f.open_menu()
	assert_false(f.hud.status_visible(), "选单占满全屏、自带资金栏，两条叠在一起会互相遮挡")
	f.close_menu()
	assert_true(f.hud.status_visible())
