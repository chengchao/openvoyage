## agent 只靠 observe()/act() 玩 HD-2D 港口（headless，不看画面）。
extends GutTest

const TAVERN := 1


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
