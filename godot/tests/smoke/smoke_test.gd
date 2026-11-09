## 冒烟验收（headless 自动化，无 mock）。可玩性的最小定义，随里程碑逐步加严。
##
## M0：按工程配置启动 → 主菜单可达（开始/退出按钮存在且已接线）→ 无错退出(0)。
## M2：从主菜单进入资料查看器，能从占位包成功打开至少 10 项图片。
## 港口：开始按钮进灰盒里斯本，碰门进设施、退出；撞门剧情；ESC 开游戏内选单、移光标、关闭后照常走路。
## 运行：godot --headless --path godot -s tests/smoke/smoke_test.gd
extends SceneTree


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
	for sig in ["start_requested", "view_requested", "quit_requested"]:
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
	if not await _door(port):
		return false
	if not await _story_at_door(port):
		return false
	return await _game_menu(port)


## HD-2D 港口：主角朝一扇门走进去 → 进该门的设施 → 退出回到港口。
func _door(port: PortScene3D) -> bool:
	var door: PortDoor = port.find_children("*", "PortDoor", true, false)[0]
	var front := door.global_position + door.global_basis.z * 1.5
	port.player.global_position = Vector3(front.x, door.global_position.y - 0.9, front.z)
	if not await _push_into_door(port):
		push_error("HD-2D 港口碰门未进设施")
		return false
	print("  HD-2D 港口：朝门走入 → 进入设施『%s』" % port.doors.facility_scene.facility_name())
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


func _push_into_door(port: PortScene3D) -> bool:
	Input.action_press("ui_up")
	for _i in 60:
		await physics_frame
		if port.doors.is_busy():
			break
	Input.action_release("ui_up")
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
	if not await _push_into_door(port) or not port.doors.is_in_cutscene():
		push_error("撞有剧情的门未触发剧情对话")
		return false
	var body: String = port.doors.director.current_line()["body"]
	if body != "阿明，請進！":
		push_error("剧情台词/变量代入有误：%s" % body)
		return false
	port.doors.director.advance()
	await process_frame
	if not port.doors.is_in_facility():
		push_error("剧情演完未落入常规设施")
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
