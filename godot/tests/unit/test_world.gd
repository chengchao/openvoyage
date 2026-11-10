## World：一局游戏的可存档状态；from_dict 是存档的信任边界。
extends GutTest


func before_each() -> void:
	World.current = null


func _played() -> World:
	var w := World.new()
	w.player.buy("wine", 7, 40)
	w.player.deposit(300)
	w.day = 12
	w.story = GameState.new(1, 2)
	w.story.set_flag(5, true)
	w.story.set_flag(9, false)
	w.story.set_var(50, 6)
	w.story.set_var(3, -4)
	w.story.set_name("n", "阿明")
	return w


func _through_json(d: Dictionary) -> Variant:
	return JSON.parse_string(JSON.stringify(d))


func test_new_game_replaces_current_with_a_fresh_world() -> void:
	var old := World.new_game()
	old.player.deposit(500)
	var w := World.new_game()
	assert_eq(World.current, w)
	assert_ne(w, old)
	assert_eq([w.player.gold, w.player.bank, w.player.cargo, w.port_id, w.day], [World.STARTING_GOLD, 0, {}, 0, 1])


func test_round_trip_through_json_keeps_everything() -> void:
	var w := _played()
	var back := World.from_dict(_through_json(w.to_dict()))
	assert_not_null(back)
	assert_eq(back.to_dict(), w.to_dict())
	assert_eq([back.player.gold, back.player.bank, back.player.cargo], [World.STARTING_GOLD - 580, 300, {"wine": 7}])
	assert_eq([back.port_id, back.day, back.story.scenario, back.story.chapter], [0, 12, 1, 2])
	assert_true(back.story.flag(5))
	assert_false(back.story.flag(9))
	assert_eq([back.story.get_var(50), back.story.get_var(3)], [6, -4])
	assert_eq(back.story.substitute("$n"), "阿明")


func test_restored_world_does_not_share_state_with_the_dict() -> void:
	var d := _played().to_dict()
	var back := World.from_dict(d)
	back.player.sell("wine", 7, 1)
	assert_eq(d["player"]["cargo"], {"wine": 7})


func _broken(path: Array, value: Variant) -> Variant:
	var d: Variant = _through_json(_played().to_dict())
	var at: Variant = d
	for k: String in path.slice(0, -1):
		at = at[k]
	if value == null:
		at.erase(path[-1])
	else:
		at[path[-1]] = value
	return d


func test_malformed_saves_are_rejected_whole() -> void:
	var cases := [
		[["player"], null], [["story"], null], [["port_id"], null], [["day"], null],
		[["player"], "rich"], [["story"], []],
		[["player", "gold"], -1], [["player", "gold"], 10.5], [["player", "gold"], "2000"], [["player", "gold"], 1e300],
		[["player", "bank"], null], [["player", "hold"], -5],
		[["player", "cargo"], [1, 2]], [["player", "cargo", "wine"], 0], [["player", "cargo", "wine"], "many"],
		[["player", "cargo", "wine"], 101],
		[["port_id"], 999], [["port_id"], -1], [["day"], 0], [["day"], "soon"],
		[["story", "scenario"], -2], [["story", "chapter"], 0.5],
		[["story", "flags"], null], [["story", "flags", "5"], 1], [["story", "flags", "five"], true],
		[["story", "vars", "50"], "six"], [["story", "vars", "x"], 1], [["story", "names", "n"], 7],
	]
	for c: Array in cases:
		assert_null(World.from_dict(_broken(c[0], c[1])), "%s = %s 应整档拒收" % [c[0], c[1]])
	for junk: Variant in [null, 3, "save", [], {}]:
		assert_null(World.from_dict(junk), "%s 不是存档" % [junk])


func test_being_in_the_second_port_round_trips() -> void:
	var w := _played()
	w.port_id = 1
	var back := World.from_dict(_through_json(w.to_dict()))
	assert_not_null(back)
	assert_eq(back.port_id, 1)


func test_notice_is_read_once_and_not_saved() -> void:
	var w := World.new()
	w.notice = "航行 4 日，抵達塞維利亞。"
	assert_false(w.to_dict().has("notice"))
	assert_eq(w.take_notice(), "航行 4 日，抵達塞維利亞。")
	assert_eq(w.take_notice(), "")


func test_new_game_ships_with_a_protagonist_and_a_goal() -> void:
	var w := World.new_game()
	assert_ne(w.story.substitute("$n"), "$n", "主角有名字")
	var goal := w.goal()
	assert_ne(goal["text"], "")
	assert_eq([goal["progress"], goal["target"], goal["met"]], [World.STARTING_GOLD, 10000, false])


func test_goal_progress_is_cash_plus_bank() -> void:
	var w := World.new_game()
	w.player.deposit(500)
	assert_eq(w.goal()["progress"], World.STARTING_GOLD)
	w.player.gold += 7999
	assert_false(w.goal()["met"])
	w.player.gold += 1
	assert_eq([w.goal()["progress"], w.goal()["met"]], [10000, true])


func test_goal_once_met_stays_met_after_spending_and_after_loading() -> void:
	var w := World.new_game()
	w.player.gold = 10000
	assert_true(w.goal()["met"])
	w.player.gold = 10
	assert_eq([w.goal()["progress"], w.goal()["met"]], [10, true])
	assert_true(World.from_dict(_through_json(w.to_dict())).goal()["met"])


func test_loaded_save_has_the_story_and_goal() -> void:
	var w := World.new_game()
	var back := World.from_dict(_through_json(w.to_dict()))
	assert_eq(back.goal(), w.goal())
	assert_eq(back.story.substitute("$n"), w.story.substitute("$n"))


func test_world_without_a_story_has_no_goal() -> void:
	assert_eq(World.new().goal(), {})
	assert_eq(World.new().goal_line(), "")
