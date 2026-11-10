## agent 只靠 observe()/act() 玩 HD-2D 港口（headless，不看画面）。
extends GutTest

const MARKET := 0
const TAVERN := 1
const BANK := 8


func _agent() -> PortAgent:
	var port: PortScene3D = load("res://game/port3d/ports/lisbon.tscn").instantiate()
	add_child_autofree(port)
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
	assert_eq(obs["gold"], PortSession.STARTING_GOLD)
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
	assert_eq(obs["mode"], "goods_pick")
	var good: Dictionary = Market.goods(0)[0]
	assert_string_contains(obs["pick"]["options"][0], good["label"])
	assert_false(await agent.act({"do": "pick", "index": obs["pick"]["options"].size()}), "越界被拒")
	assert_true(await agent.act({"do": "pick", "index": 0}))
	assert_eq(agent.observe()["mode"], "amount_entry")
	assert_true(await agent.act({"do": "amount", "value": 4}))
	obs = agent.observe()
	assert_eq(obs["mode"], "facility_menu")
	assert_eq(obs["cargo"], {good["key"]: 4})
	assert_eq(obs["gold"], PortSession.STARTING_GOLD - 4 * good["buy"])
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
	assert_eq([obs["gold"], obs["bank"]], [PortSession.STARTING_GOLD - 500, 500])


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
