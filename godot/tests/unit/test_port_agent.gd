## agent 只靠 observe()/act() 玩 HD-2D 港口（headless，不看画面）。
extends GutTest

const MARKET := 0
const TAVERN := 1
const HARBOR := 3
const BANK := 8
const SAVE_PATH := "user://test_tmp/port_agent.json"


func before_each() -> void:
	World.current = World.new()  # 没有剧本的一局：各测试从走路开始，不先演开场
	_entered.clear()
	DirAccess.remove_absolute(SAVE_PATH)


func after_all() -> void:
	DirAccess.remove_absolute(SAVE_PATH)


## 换港（出航/读档）在测试里只记下要去的 world，不真的换 GUT 的当前场景。
var _entered: Array[World] = []


func _agent(port_key := "lisbon") -> PortAgent:
	var port: PortScene3D = load("res://game/port3d/ports/%s.tscn" % port_key).instantiate()
	add_child_autofree(port)
	port.doors.session.save_path = SAVE_PATH
	port.doors.enter_port = func(_tree: SceneTree, w: World) -> void: _entered.append(w)
	return PortAgent.new(port)


func _door(obs: Dictionary, slot: int) -> Dictionary:
	for d in obs["doors"]:
		if d["slot"] == slot:
			return d
	return {}


## 像 agent 那样导航：先横向对准门，再朝门走进去。
func _go_into(agent: PortAgent, slot: int) -> void:
	var door := _door(agent.observe(), slot)
	var dx: float = door["at"][0] - agent.observe()["position"][0]
	await agent.act({"do": "walk", "dir": "left" if dx < 0 else "right", "seconds": absf(dx) / Avatar3D.SPEED})
	for _i in 10:
		if agent.observe()["mode"] != "walking":
			return
		await agent.act({"do": "walk", "dir": "up", "seconds": 0.5})


func test_observation_at_spawn() -> void:
	var agent := _agent()
	await wait_seconds(0.2)
	var obs := agent.observe()
	assert_eq(obs["mode"], "walking")
	assert_eq(obs["position"].size(), 3)
	assert_eq(obs["gold"], World.STARTING_GOLD)
	assert_eq(obs["day"], 1)
	assert_eq(obs["port"], {"id": 0, "name": "里斯本"})
	var tavern := _door(obs, TAVERN)
	assert_eq(tavern.get("name"), "酒馆", "观察里列出各门：槽号、名字、位置")
	assert_gt(obs["doors"].size(), 1)


func test_agent_walks_in_chooses_and_leaves() -> void:
	var agent := _agent()
	await wait_seconds(0.2)
	await _go_into(agent, TAVERN)
	var obs := agent.observe()
	assert_eq(obs["mode"], "facility_menu", "朝门走进设施")
	assert_eq(obs["facility"]["slot"], TAVERN)
	assert_eq(obs["facility"]["menu"][-1], "離開")

	assert_true(obs.has("said"), "店主回话字段可观察")
	assert_false(await agent.act({"do": "choose", "index": obs["facility"]["menu"].size()}), "越界序号被拒")
	assert_true(await agent.act({"do": "choose", "index": obs["facility"]["menu"].size() - 1}), "选末项「離開」")
	assert_eq(agent.observe()["mode"], "walking")


func test_agent_reads_and_advances_a_cutscene() -> void:
	var agent := _agent()
	var events := {"scenario": 1, "chapters": [{"index": 0,
		"entries": [{"trigger_id": "%04x" % TAVERN, "label": "L0"}],
		"script": [{"label": "L0"}, {"op": "say", "text": "snr1/0"}, {"op": "wait"}, {"op": "end"}]}]}
	agent.port.doors.inject_story(EventScript.new(events, PackedStringArray(["〔店主〕\n請進！"])), GameState.new(1, 0))
	await wait_seconds(0.2)
	await _go_into(agent, TAVERN)
	var obs := agent.observe()
	assert_eq(obs["mode"], "cutscene")
	assert_eq(obs["line"]["body"], "請進！")
	assert_true(await agent.act({"do": "next"}))
	assert_eq(agent.observe()["mode"], "facility_menu", "剧情演完进设施")


func test_illegal_action_is_refused() -> void:
	var agent := _agent()
	await wait_seconds(0.2)
	assert_false(await agent.act({"do": "leave"}), "港口里不能离开设施")
	assert_false(await agent.act({"do": "fly"}), "未知动作")


func test_agent_opens_browses_and_closes_the_game_menu() -> void:
	var agent := _agent()
	await wait_seconds(0.2)
	assert_false(agent.observe().has("game_menu"))
	assert_false(await agent.act({"do": "close"}), "没开着选单")
	assert_false(await agent.act({"do": "menu_select", "category": 0, "item": 0}))
	assert_true(await agent.act({"do": "menu"}))
	var obs := agent.observe()
	assert_eq(obs["mode"], "game_menu")
	assert_eq(obs["game_menu"]["categories"], ["情報", "艦隊", "隨身物", "系統"])
	assert_eq([obs["game_menu"]["category"], obs["game_menu"]["item"]], [0, 0])

	assert_true(await agent.act({"do": "menu_select", "category": 3, "item": 4}))
	var menu: Dictionary = agent.observe()["game_menu"]
	assert_eq([menu["category"], menu["item"]], [3, 4])
	assert_eq(menu["items"][4], "結束遊戲")
	assert_ne(menu["detail"], "")
	assert_false(await agent.act({"do": "menu_select", "category": 3, "item": 5}), "越界项被拒")
	assert_false(await agent.act({"do": "menu_select", "category": 4, "item": 0}), "越界分类被拒")
	assert_false(await agent.act({"do": "menu"}), "已开着")
	assert_false(await agent.act({"do": "walk", "dir": "up", "seconds": 0.1}), "选单开着不能走")

	assert_true(await agent.act({"do": "close"}))
	assert_eq(agent.observe()["mode"], "walking")


func test_agent_trades_at_the_market() -> void:
	var agent := _agent()
	await wait_seconds(0.2)
	assert_eq(agent.observe()["cargo"], {})
	agent.port.doors.open(MARKET)
	assert_false(await agent.act({"do": "pick", "index": 0}), "还没选买卖")
	assert_true(await agent.act({"do": "choose", "index": 0}))
	var obs := agent.observe()
	assert_eq(obs["mode"], "pick")
	var good: Dictionary = Market.goods(0)[0]
	assert_string_contains(obs["pick"]["options"][0], good["label"])
	assert_false(await agent.act({"do": "pick", "index": obs["pick"]["options"].size()}), "越界被拒")
	assert_true(await agent.act({"do": "pick", "index": 0}))
	assert_eq(agent.observe()["mode"], "amount_entry")
	assert_true(await agent.act({"do": "amount", "value": 4}))
	obs = agent.observe()
	assert_eq(obs["mode"], "facility_menu")
	assert_eq(obs["cargo"], {good["key"]: 4})
	assert_eq(obs["gold"], World.STARTING_GOLD - 4 * good["buy"])
	assert_ne(obs["said"], "")


func test_agent_walks_into_the_bank_and_deposits() -> void:
	var agent := _agent()
	await wait_seconds(0.2)
	var door := _door(agent.observe(), BANK)
	var me: Array = agent.observe()["position"]
	await agent.act({"do": "walk", "dir": "down", "seconds": (door["at"][2] - me[2]) / Avatar3D.SPEED})
	for _i in 12:
		if agent.observe()["mode"] != "walking":
			break
		await agent.act({"do": "walk", "dir": "right", "seconds": 0.5})
	var obs := agent.observe()
	assert_eq(obs["mode"], "facility_menu", "银行门朝西，从广场往东走进去")
	assert_eq(obs["facility"]["slot"], BANK)
	assert_true(await agent.act({"do": "choose", "index": 0}))
	assert_true(await agent.act({"do": "amount", "value": 500}))
	obs = agent.observe()
	assert_eq([obs["gold"], obs["bank"]], [World.STARTING_GOLD - 500, 500])


func test_agent_cancels_a_pick() -> void:
	var agent := _agent()
	await wait_seconds(0.2)
	agent.port.doors.open(MARKET)
	await agent.act({"do": "choose", "index": 1})
	assert_eq(agent.observe()["mode"], "facility_menu", "没货可卖，留在菜单")
	await agent.act({"do": "choose", "index": 0})
	assert_true(await agent.act({"do": "cancel"}))
	var obs := agent.observe()
	assert_eq(obs["mode"], "facility_menu")
	assert_false(obs.has("pick"))


func test_port_scene_plays_on_the_current_world() -> void:
	var w := World.new_game()
	w.port_id = 9
	w.day = 5
	w.player.deposit(150)
	var obs := _agent().observe()
	assert_eq([obs["gold"], obs["bank"], obs["day"]], [World.STARTING_GOLD - 150, 150, 5])
	assert_eq(w.port_id, 0, "进了里斯本，世界里的所在港跟着变")


func test_progress_survives_a_scene_change() -> void:
	var first := _agent()
	first.port.doors.open(BANK)
	await first.act({"do": "choose", "index": 0})
	await first.act({"do": "amount", "value": 800})
	first.port.free()
	var obs := _agent().observe()
	assert_eq([obs["gold"], obs["bank"]], [World.STARTING_GOLD - 800, 800], "新场景接着同一局")


func test_agent_saves_from_the_game_menu() -> void:
	var agent := _agent()
	await wait_seconds(0.2)
	assert_false(await agent.act({"do": "menu_activate"}), "没开着选单")
	await agent.act({"do": "menu"})
	assert_false(await agent.act({"do": "menu_activate"}), "光标在尚未開放的项上")
	await agent.act({"do": "menu_select", "category": 3, "item": 1})
	assert_true(await agent.act({"do": "menu_activate"}))
	assert_string_contains(agent.observe()["game_menu"]["detail"], "進度已儲存")
	assert_true(SaveFile.exists(SAVE_PATH))


func test_agent_sails_from_the_harbor_to_the_next_port_and_sells_at_a_profit() -> void:
	var agent := _agent()
	await wait_seconds(0.2)
	agent.port.doors.open(MARKET)
	await agent.act({"do": "choose", "index": 0})
	var options: Array = agent.observe()["pick"]["options"]
	for i in options.size():
		if options[i].contains(Market.label("woolens")):
			await agent.act({"do": "pick", "index": i})
	await agent.act({"do": "amount", "value": 20})
	await agent.act({"do": "leave"})

	agent.port.doors.open(HARBOR)
	assert_true(await agent.act({"do": "choose", "index": 0}), "啟航出海")
	var obs := agent.observe()
	assert_eq(obs["mode"], "pick")
	assert_string_contains(obs["pick"]["options"][0], "塞維利亞")
	assert_true(await agent.act({"do": "pick", "index": 0}))
	assert_eq(agent.observe()["mode"], "sailed")
	assert_eq(_entered, [World.current], "表现层被要求换进目的港")
	assert_false(await agent.act({"do": "walk", "dir": "up", "seconds": 0.1}), "这座港已经离开了")

	agent.port.free()
	var there := _agent(Market.port_scene(World.current.port_id).get_file().get_basename())
	await wait_seconds(0.2)
	obs = there.observe()
	assert_eq([obs["mode"], obs["port"], obs["day"]], ["walking", {"id": 1, "name": "塞維利亞"}, 5])
	assert_eq(obs["said"], "航行 4 日，抵達塞維利亞。", "抵港通知可观察")
	there.port.doors.open(MARKET)
	await there.act({"do": "choose", "index": 1})
	await there.act({"do": "pick", "index": 0})
	await there.act({"do": "amount", "value": 20})
	assert_gt(there.observe()["gold"], World.STARTING_GOLD)


func test_agent_cancels_a_destination_pick_opened_at_the_departure_zone() -> void:
	var agent := _agent()
	await wait_seconds(0.2)
	agent.port.player.global_position = agent.port.get_node("Departure").global_position
	await wait_seconds(0.2)
	var obs := agent.observe()
	assert_eq(obs["mode"], "pick", "走进出航区就问去哪")
	assert_false(obs.has("facility"))
	assert_true(await agent.act({"do": "cancel"}))
	assert_eq(agent.observe()["mode"], "walking")
	assert_eq(_entered, [])
	assert_true(await agent.act({"do": "walk", "dir": "up", "seconds": 0.2}), "取消后照常走路")


func test_current_finds_the_port_the_tree_is_showing() -> void:
	assert_null(PortAgent.current(get_tree()), "GUT 的当前场景不是港口")


func test_new_game_opens_on_the_intro_and_reports_the_goal() -> void:
	World.new_game()
	var agent := _agent()
	var obs := agent.observe()
	assert_eq(obs["mode"], "cutscene", "新开一局先演开场")
	assert_ne(obs["line"]["body"], "")
	assert_eq(obs["goal"], {"text": World.current.goal()["text"], "progress": World.STARTING_GOLD, "target": 10000, "met": false})
	assert_false(await agent.act({"do": "walk", "dir": "up", "seconds": 0.1}), "开场中不能走")
	for _i in 20:
		if agent.observe()["mode"] == "cutscene":
			await agent.act({"do": "next"})
	assert_eq(agent.observe()["mode"], "walking")
	assert_true(await agent.act({"do": "walk", "dir": "down", "seconds": 0.2}))

	agent.port.free()
	assert_eq(_agent().observe()["mode"], "walking", "再进里斯本不重演")
