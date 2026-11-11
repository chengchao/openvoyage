## 冒烟验收（headless 自动化，无 mock）。可玩性的最小定义，随里程碑逐步加严。
##
## M0：按工程配置启动 → 主菜单可达（开始/退出按钮存在且已接线）→ 无错退出(0)。
## M2：从主菜单进入资料查看器，能从占位包成功打开至少 10 项图片。
## 开场：开始按钮进灰盒里斯本，先演随包的开场剧情，逐句推进到底才轮到走路，HUD 显示港名/现金/目标与操作提示；之后换场景、读档都不重演。
## 港口：碰门进设施、退出；交易所买进再卖出；走进银行存款；撞门剧情；ESC 开游戏内选单、移光标、关闭后照常走路。
## 航行：新开一局，里斯本买毛織品 → 港务局啟航 → 塞維利亞卖出，现金高于开局 → 走进塞維利亞的银行存款。
## 存读档（在塞維利亞）：选单存档 → 提款 → 读档回到存档时的局面；回到標題 →「繼續航程」接着存档玩，人还在塞維利亞。
## 运行：godot --headless --path godot -s tests/smoke/smoke_test.gd
extends SceneTree

const SAVE_PATH := "user://test_tmp/smoke_save.json"


func _initialize() -> void:
	var ok := await _smoke()
	if ok:
		print("SMOKE_OK: 主菜单可达，导航信号已接线")
	else:
		push_error("SMOKE_FAIL: 冒烟验收未通过")
	quit(0 if ok else 1)


func _smoke() -> bool:
	var main_scene_path := str(ProjectSettings.get_setting("application/run/main_scene"))
	var packed: PackedScene = load(main_scene_path)
	if packed == null:
		push_error("%s 加载失败" % main_scene_path)
		return false

	var main: Node = packed.instantiate()
	get_root().add_child(main)
	current_scene = main
	await process_frame  # 等一帧，让 Main._ready 跑完（接线在此发生）

	var menu: Node = main.get_node_or_null("MainMenu")
	if menu == null:
		push_error("主菜单未实例化")
		return false
	if menu.get_node_or_null("%StartButton") == null or menu.get_node_or_null("%QuitButton") == null:
		push_error("开始/退出按钮缺失")
		return false

	# Main 路由已把菜单意图接到导航/退出（开始/查看器/退出可响应）
	for sig in ["start_requested", "continue_requested", "view_requested", "quit_requested"]:
		if menu.get_signal_connection_list(sig).is_empty():
			push_error("%s 未接线" % sig)
			return false

	# M2：经真实菜单导航进入资料查看器，并能从占位包打开至少 10 项。
	(menu.get_node("%ViewButton") as Button).pressed.emit()
	await process_frame
	var viewer: Node = main.get_node_or_null("AssetViewer")
	if viewer == null:
		push_error("资料查看器未通过主菜单导航实例化")
		return false
	var opened: int = viewer.load_all_images()
	if opened < 10:
		push_error("资料查看器只打开了 %d 项（需 ≥10）" % opened)
		return false
	print("  查看器成功打开 %d 项" % opened)

	(viewer.get_node("%BackButton") as Button).pressed.emit()
	await process_frame
	menu = main.get_node_or_null("MainMenu")
	if menu == null:
		push_error("从资料查看器返回主菜单失败")
		return false

	(menu.get_node("%StartButton") as Button).pressed.emit()
	for _i in 5:
		await physics_frame
	var port := current_scene as PortScene3D
	if port == null:
		push_error("开始游戏未进入港口场景")
		return false
	if not await _intro(port):
		return false
	if not await _door(port):
		return false
	if not await _market(port):
		return false
	if not await _bank(port):
		return false
	if not await _story_at_door(port):
		return false
	if not await _game_menu(port):
		return false
	var seville := await _voyage()
	var ok := seville != null and await _save_and_load(seville) and await _continue_from_title()
	DirAccess.remove_absolute(SAVE_PATH)
	return ok


## 新开一局进港先演开场：逐句推进到底，回到走路，目标可观察。
func _intro(port: PortScene3D) -> bool:
	var agent := PortAgent.new(port)
	var first := agent.observe()
	if first["mode"] != "cutscene" or first["line"]["body"] == "":
		push_error("新开一局没有演开场：%s" % first)
		return false
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	get_root().push_input(click)
	get_root().push_input(click)
	if agent.observe().get("line", {}) == first["line"]:
		push_error("鼠标左键点两下（全显 → 下一句）没有推进开场对话")
		return false
	var lines := 1
	while agent.observe()["mode"] == "cutscene" and lines < 30:
		await agent.act({"do": "next"})
		lines += 1
	var obs := agent.observe()
	if obs["mode"] != "walking" or obs["goal"].get("target", 0) <= 0 or obs["goal"]["met"]:
		push_error("开场演完没有回到走路，或没有目标：%s" % obs)
		return false
	if not await agent.act({"do": "walk", "dir": "down", "seconds": 0.2}):
		push_error("开场演完走不动")
		return false
	var hud := port.doors.hud
	if not (hud.hint_visible() and hud.status_text().contains(obs["port"]["name"]) and hud.status_text().contains(str(obs["gold"]))):
		push_error("走路时 HUD 没有显示港名/现金或操作提示：%s" % hud.status_text())
		return false
	print("  HUD：%s｜%s" % [hud.status_text(), PortHud.HINT])
	print("  开场：『%s』… 共 %d 句 → 走路；目標：%s" % [first["line"]["body"].replace("\n", " "), lines, obs["goal"]["text"]])
	return true


## HD-2D 港口：主角朝一扇门走进去 → 进该门的设施 → 退出回到港口。
func _door(port: PortScene3D) -> bool:
	_stand_before(port, port.find_children("*", "PortDoor", true, false)[0])
	if not await _push_into_door(port):
		push_error("HD-2D 港口碰门未进设施")
		return false
	var labels := port.doors.facility_scene.menu_labels()
	if labels.size() < 2:
		push_error("设施菜单只有「離開」：自制内容未随包")
		return false
	print("  HD-2D 港口：朝门走入 → 进入设施『%s』，菜单 %s" % [port.doors.facility_scene.facility_name(), labels])
	for _i in 10:
		await physics_frame  # 像真人一样在店里停留，港口才会冻结主角
	port.doors.facility_scene._request_exit()
	for _i in 10:
		await physics_frame
	if port.doors.is_busy():
		push_error("HD-2D 港口未能退出设施")
		return false
	print("  HD-2D 港口：退出设施，回到港口")
	return true


func _stand_before(port: PortScene3D, door: PortDoor) -> void:
	var front := door.global_position + door.global_basis.z * 1.5
	port.player.global_position = Vector3(front.x, door.global_position.y - 0.9, front.z)


## 站到某种设施的门前，朝门里推进去。
func _walk_into(port: PortScene3D, key: StringName) -> bool:
	for door: PortDoor in port.find_children("*", "PortDoor", true, false):
		if FacilityType.of(door.slot).key == key:
			_stand_before(port, door)
			for _i in 3:
				await physics_frame  # 瞬移后门的重叠名单要过一个物理步才更新，否则会被刚离开的那扇门再拉进去
			var inward := -door.global_basis.z
			var action := "ui_up" if inward.z < -0.5 else ("ui_left" if inward.x < 0.0 else "ui_right")
			return await _push_into_door(port, action) and port.doors.session.slot == door.slot
	return false


func _leave(port: PortScene3D, agent: PortAgent) -> bool:
	if not await agent.act({"do": "leave"}):
		return false
	for _i in 10:
		await physics_frame
	return not port.doors.is_busy()


## 低买高卖：新开一局，里斯本买 20 件毛織品 → 港务局啟航 → 塞維利亞卖掉，现金高于开局 → 存 500 进塞維利亞的银行。
## 返回塞維利亞的港口场景；走不通返回 null。
func _voyage() -> PortScene3D:
	PortScene3D.enter(self, World.new_game())
	for _i in 5:
		await physics_frame
	var agent := PortAgent.current(self)
	if agent == null or agent.observe()["port"]["id"] != 0 or not await _intro(agent.port):
		push_error("新开一局没有进里斯本")
		return null
	if not (await _walk_into(agent.port, &"market") and await agent.act({"do": "choose", "index": 0})):
		push_error("里斯本交易所走不进或不能採購：%s" % agent.observe())
		return null
	var options: Array = agent.observe()["pick"]["options"]
	var row := -1
	for i in options.size():
		if options[i].contains(Market.label("woolens")):
			row = i
	if not (await agent.act({"do": "pick", "index": row}) and await agent.act({"do": "amount", "value": 20})
			and await _leave(agent.port, agent)):
		push_error("里斯本买毛織品走不通：%s" % agent.observe())
		return null

	if not (await _walk_into(agent.port, &"harbor") and await agent.act({"do": "choose", "index": 0})
			and agent.observe()["mode"] == "pick"):
		push_error("港務局啟航没有问去哪：%s" % agent.observe())
		return null
	var route: String = agent.observe()["pick"]["options"][0]
	var lisbon := agent.port
	if not await agent.act({"do": "pick", "index": 0}):
		push_error("选不了目的地")
		return null
	for _i in 5:
		await physics_frame
	agent = PortAgent.current(self)
	if agent == null or agent.port == lisbon:
		push_error("启航后没有换进目的港的场景")
		return null
	var obs := agent.observe()
	if obs["port"]["id"] != 1 or obs["day"] != 5 or obs["mode"] != "walking" or obs["cargo"] != {"woolens": 20}:
		push_error("抵港后的局面有误：%s" % obs)
		return null
	print("  航行：『%s』→ %s（%s，第 %d 日）" % [route, obs["said"], obs["port"]["name"], obs["day"]])

	if not (await _walk_into(agent.port, &"market") and await agent.act({"do": "choose", "index": 1})
			and await agent.act({"do": "pick", "index": 0}) and await agent.act({"do": "amount", "value": 20})
			and await _leave(agent.port, agent)):
		push_error("塞維利亞卖货走不通：%s" % agent.observe())
		return null
	var gold: int = agent.observe()["gold"]
	if gold <= World.STARTING_GOLD:
		push_error("跑了一趟没赚到钱：現金 %d" % gold)
		return null
	print("  航行：塞維利亞卖出 20 件毛織品，現金 %d → %d" % [World.STARTING_GOLD, gold])

	if not (await _walk_into(agent.port, &"bank") and await agent.act({"do": "choose", "index": 0})
			and await agent.act({"do": "amount", "value": 500}) and await _leave(agent.port, agent)):
		push_error("塞維利亞的銀行走不进或存不了款：%s" % agent.observe())
		return null
	return agent.port


## 交易所：走进门 → 採購 → 选货 → 件数 → 出售同一批 → 亏掉买卖价差 → 离开。
func _market(port: PortScene3D) -> bool:
	var agent := PortAgent.new(port)
	for door: PortDoor in port.find_children("*", "PortDoor", true, false):
		if FacilityType.of(door.slot).key == &"market":
			_stand_before(port, door)
	if not await _push_into_door(port) or agent.observe()["facility"]["name"] != FacilityType.of(0).name:
		push_error("没能走进交易所")
		return false
	var good: Dictionary = Market.goods(port.port_id)[0]
	var gold: int = agent.observe()["gold"]
	if not (await agent.act({"do": "choose", "index": 0}) and await agent.act({"do": "pick", "index": 0})
			and await agent.act({"do": "amount", "value": 3})):
		push_error("交易所买进流程走不通：%s" % agent.observe())
		return false
	var obs := agent.observe()
	if obs["cargo"] != {good["key"]: 3} or obs["gold"] != gold - 3 * good["buy"]:
		push_error("买进后货物/现金有误：%s" % obs)
		return false
	print("  交易所：买进 3 件%s → %s" % [good["label"], obs["said"].replace("\n", " ")])
	if not (await agent.act({"do": "choose", "index": 1}) and await agent.act({"do": "pick", "index": 0})
			and await agent.act({"do": "amount", "value": 3})):
		push_error("交易所卖出流程走不通：%s" % agent.observe())
		return false
	obs = agent.observe()
	if obs["cargo"] != {} or obs["gold"] != gold - 3 * (good["buy"] - good["sell"]):
		push_error("卖出后货物/现金有误：%s" % obs)
		return false
	print("  交易所：卖出 3 件%s → %s" % [good["label"], obs["said"].replace("\n", " ")])
	if not await agent.act({"do": "leave"}):
		return false
	for _i in 10:
		await physics_frame
	return not port.doors.is_busy()


## 银行：门朝西，往东走进去 → 存款 500 → 离开。
func _bank(port: PortScene3D) -> bool:
	var agent := PortAgent.new(port)
	var found := false
	for door: PortDoor in port.find_children("*", "PortDoor", true, false):
		if FacilityType.of(door.slot).key == &"bank":
			_stand_before(port, door)
			found = true
	if not found or not await _push_into_door(port, "ui_right") or agent.observe()["facility"]["slot"] != 8:
		push_error("没能走进銀行")
		return false
	var before := agent.observe()
	if not (await agent.act({"do": "choose", "index": 0}) and await agent.act({"do": "amount", "value": 500})):
		push_error("銀行存款流程走不通：%s" % agent.observe())
		return false
	var obs := agent.observe()
	if obs["gold"] != before["gold"] - 500 or obs["bank"] != before["bank"] + 500:
		push_error("存款后现金/存款有误：%s" % obs)
		return false
	print("  銀行：存入 500 → %s" % obs["said"])
	if not await agent.act({"do": "leave"}):
		return false
	for _i in 10:
		await physics_frame
	return not port.doors.is_busy()


func _push_into_door(port: PortScene3D, action := "ui_up") -> bool:
	Input.action_press(action)
	for _i in 60:
		await physics_frame
		if port.doors.is_busy():
			break
	Input.action_release(action)
	return port.doors.is_busy()


## 门登记了剧情事件：撞门先演对话（find_entry → EventInterpreter → DialogueDirector），演完照常进设施。
## 合成脚本，CI 无原版 SNR 也能跑通全链路。
func _story_at_door(port: PortScene3D) -> bool:
	var door: PortDoor = port.find_children("*", "PortDoor", true, false)[0]
	var events := {
		"scenario": 1,
		"chapters": [{"index": 0, "entries": [
			{"trigger_id": "%02x%02x" % [port.port_id, door.slot], "label": "L0"},
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
	port.doors.inject_story(EventScript.new(events, PackedStringArray(["〔店主〕\n$n，請進！"])), st)
	_stand_before(port, door)
	if not await _push_into_door(port) or not port.doors.is_in_cutscene():
		push_error("撞有剧情的门未触发剧情对话")
		return false
	var body: String = port.doors.director.current_line()["body"]
	if body != "阿明，請進！":
		push_error("剧情台词/变量代入有误：%s" % body)
		return false
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(380, 153)
	get_root().push_input(click)
	get_root().push_input(click)
	await process_frame
	if not port.doors.is_in_facility():
		push_error("点击演完剧情后没有留在设施里（收尾的点击穿透到了刚出现的菜单？）")
		return false
	var fs: FacilityScene = port.doors.facility_scene
	if not fs._menu_items[0].get_global_rect().has_point(click.position):
		push_error("冒烟的点击位置 %s 已不在设施菜单第一项上，这一步测不到穿透" % click.position)
		return false
	if not fs.has_dialogue():
		push_error("收尾的点击顺带关掉了店主寒暄")
		return false
	var greeting := fs.spoken_line()
	click.position = fs._menu_items[3].get_global_rect().get_center()
	get_root().push_input(click)
	if fs.spoken_line() == greeting:
		push_error("寒暄开着时点菜单项『%s』没有选中它" % fs._menu_items[3].text)
		return false
	print("  HD-2D 港口：撞门 → 剧情『%s』 → 演完进设施" % body)
	port.doors.facility_scene._request_exit()
	for _i in 10:
		await physics_frame
	return not port.doors.is_busy()


## HD-2D 港口：ESC 开选单 → 移光标 → 选单开着走不动 → ESC 关 → 照常走路。
func _game_menu(port: PortScene3D) -> bool:
	var agent := PortAgent.new(port)
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	get_root().push_input(esc)
	var obs := agent.observe()
	if obs["mode"] != "game_menu":
		push_error("ESC 未打开游戏内选单")
		return false
	if not await agent.act({"do": "menu_select", "category": 3, "item": 1}):
		push_error("选单光标移不动")
		return false
	var menu: Dictionary = agent.observe()["game_menu"]
	if menu["category"] != 3 or menu["item"] != 1 or menu["detail"] == "":
		push_error("选单光标/详情有误：%s" % menu)
		return false
	if await agent.act({"do": "walk", "dir": "down", "seconds": 0.1}):
		push_error("选单开着时仍能走路")
		return false
	get_root().push_input(esc)
	var before: Array = agent.observe()["position"]
	if not await agent.act({"do": "walk", "dir": "down", "seconds": 0.3}):
		push_error("关闭选单后未回到走路")
		return false
	if agent.observe()["position"] == before:
		push_error("关闭选单后主角走不动")
		return false
	print("  HD-2D 港口：ESC 开选单 → 『%s』 → ESC 关 → 继续走路" % menu["items"][menu["item"]])
	return true


## 存读档：选单存档 → 把存款提光 → 选单读档 → 换进新的港口场景，现金/存款回到存档时。
func _save_and_load(port: PortScene3D) -> bool:
	var agent := PortAgent.new(port)
	port.doors.session.save_path = SAVE_PATH
	var saved := agent.observe()
	if not (await agent.act({"do": "menu"}) and await agent.act({"do": "menu_select", "category": 3, "item": 1})
			and await agent.act({"do": "menu_activate"}) and SaveFile.exists(SAVE_PATH)):
		push_error("选单存档没写出存档文件：%s" % agent.observe())
		return false
	var note: String = agent.observe()["game_menu"]["detail"]
	await agent.act({"do": "close"})

	port.doors.open(8)
	if not (await agent.act({"do": "choose", "index": 1}) and await agent.act({"do": "amount", "value": saved["bank"]})
			and await agent.act({"do": "leave"})) or agent.observe()["bank"] != 0:
		push_error("存档后提款走不通：%s" % agent.observe())
		return false

	if not (await agent.act({"do": "menu"}) and await agent.act({"do": "menu_select", "category": 3, "item": 2})
			and await agent.act({"do": "menu_activate"}) and await agent.act({"do": "menu_activate"})):
		push_error("选单读档走不通：%s" % agent.observe())
		return false
	for _i in 5:
		await physics_frame
	var reloaded := current_scene as PortScene3D
	if reloaded == null or reloaded == port:
		push_error("读档后没有换进存档所在的港口场景")
		return false
	var obs := PortAgent.new(reloaded).observe()
	if (obs["mode"] != "walking" or obs["gold"] != saved["gold"] or obs["bank"] != saved["bank"] or saved["bank"] == 0
			or obs["port"] != saved["port"]):
		push_error("读档后局面不是存档时的：%s（存档时现金 %d 存款 %d）" % [obs, saved["gold"], saved["bank"]])
		return false
	print("  存读档：『%s』→ 提光存款 → 读档 → 現金 %d　存款 %d" % [note.replace("\n", " "), obs["gold"], obs["bank"]])
	return true


## 选单「回到標題」→ 主菜单「繼續航程」→ 从存档文件进港（不靠内存里那一局）。
func _continue_from_title() -> bool:
	var agent := PortAgent.new(current_scene as PortScene3D)
	var before := agent.observe()
	if not (await agent.act({"do": "menu"}) and await agent.act({"do": "menu_select", "category": 3, "item": 3})
			and await agent.act({"do": "menu_activate"}) and await agent.act({"do": "menu_activate"})):
		push_error("选单回到標題走不通")
		return false
	for _i in 3:
		await process_frame
	var menu := current_scene.get_node_or_null("MainMenu") as MainMenu
	if menu == null:
		push_error("回到標題后没有主菜单")
		return false
	World.current = null
	menu.save_path = SAVE_PATH
	(menu.get_node("%ContinueButton") as Button).pressed.emit()
	for _i in 5:
		await physics_frame
	var port := current_scene as PortScene3D
	if port == null:
		push_error("繼續航程未进入港口场景")
		return false
	var obs := PortAgent.new(port).observe()
	if (obs["mode"] != "walking" or obs["gold"] != before["gold"] or obs["bank"] != before["bank"]
			or obs["port"] != before["port"] or obs["port"]["id"] != 1):
		push_error("繼續航程后的局面不是存档里的：%s" % obs)
		return false
	print("  標題 →「繼續航程」→ %s，現金 %d　存款 %d" % [obs["port"]["name"], obs["gold"], obs["bank"]])
	return true
