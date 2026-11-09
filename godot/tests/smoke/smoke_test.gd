## 冒烟验收（headless 自动化，无 mock）。可玩性的最小定义，随里程碑逐步加严。
##
## M0：按工程配置启动 → 主菜单可达（开始/退出按钮存在且已接线）→ 无错退出(0)。
## M2：从主菜单进入资料查看器，能从占位包成功打开至少 10 项图片。
## HD-2D：灰盒里斯本碰门进设施、退出。
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

	# M3：经真实开始按钮进入港口场景，向四方向各走 10 步，全程不穿墙、不出界。
	(menu.get_node("%StartButton") as Button).pressed.emit()
	await process_frame
	await process_frame
	var port: Node2D = current_scene as Node2D
	if port == null or port.name != "PortScene":
		push_error("开始游戏未进入港口场景")
		return false
	# NPC：港内自主游走人物已生成
	if port._npcs == null or port._npcs.count() == 0:
		push_error("港口未生成 NPC")
		return false
	print("  港内生成 %d 个自主游走 NPC" % port._npcs.count())
	var spawn: Vector2i = port.walker_pos()
	var saved_facilities = port.facilities
	port.facilities = FacilityTable.new([])  # 行走段屏蔽设施触发，纯验碰撞
	for dir in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		port.walker.pos = spawn
		for _i in 10:
			port.move(dir)
			var p: Vector2i = port.walker_pos()
			if not port.map.in_bounds(p.x, p.y) or not port.passability.is_passable(port.map.tile_at(p.x, p.y)):
				push_error("港口行走穿墙/出界于 %s" % p)
				return false
	print("  港口行走四向各 10 步：未穿墙、未出界")
	port.facilities = saved_facilities

	# M4：走到设施门口 → 进入 → 看到店员 → 退出
	if not _enter_a_facility(port):
		push_error("无法走进任何设施门口")
		return false
	if port.doors.facility_scene.shopkeeper_texture() == null:
		push_error("设施场景未显示店员立绘")
		return false
	# M5：进门弹出店主寒暄对话框 → 关闭 → 露出菜单
	if not port.doors.facility_scene.has_dialogue():
		push_error("进设施未弹出对话框")
		return false
	port.doors.facility_scene._dialogue.closed.emit()
	await process_frame
	if port.doors.facility_scene.has_dialogue():
		push_error("对话框未关闭")
		return false
	print("  进入设施『%s』→ 店主寒暄 → 关闭" % port.doors.facility_scene.facility_name())
	port.doors.facility_scene._request_exit()
	await process_frame
	if port.doors.is_in_facility():
		push_error("未能退出设施回到港口")
		return false
	print("  退出设施，回到港口")

	# M5：进门「事件表优先」—— 给某门登记剧情事件，撞门先演 SNR 字节码对话（CC/C8/C7），
	# 演完再进设施。用合成脚本（真实节拍形态）保证 CI（占位资产、无原版 SNR）也能跑通全链路。
	if not await _play_story_at_door(port):
		return false

	port.queue_free()

	if not await _hd2d_door():
		return false
	return true


## HD-2D 港口：主角朝一扇门走进去 → 进该门的设施 → 退出回到港口。
func _hd2d_door() -> bool:
	var port: PortScene3D = load(preload("res://game/main.gd").HD2D_SCENE).instantiate()
	get_root().add_child(port)
	for _i in 5:
		await physics_frame
	var door: PortDoor = port.find_children("*", "PortDoor", true, false)[0]
	var front := door.global_position + door.global_basis.z * 1.5
	port.player.global_position = Vector3(front.x, door.global_position.y - 0.9, front.z)
	Input.action_press("ui_up")  # 朝门走进去
	for _i in 60:
		await physics_frame
		if port.doors.is_in_facility():
			break
	Input.action_release("ui_up")
	if not port.doors.is_in_facility():
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
	port.queue_free()
	return true


## 演示完整对话链路：find_entry → EventInterpreter → DialogueDirector → DialogueBox → 进设施。
func _play_story_at_door(port: Node2D) -> bool:
	var slot: int = port.facilities.present_slots()[0]
	var door: Vector2i = port.facilities.slots[slot]
	# 事件脚本：港0(占位港)、设施码=该门槽位号 → 命令表入口（开窗/头像/台词/等待/结束）。
	# 用合成 events/ 形态保证 CI（占位资产、无原版 SNR）也能跑通全链路。
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
	var script := EventScript.new(events, PackedStringArray(["〔店主〕\n$n，請進！"]))
	var st := GameState.new(1, 0)
	st.set_name("n", "阿明")
	port.inject_story(script, st)

	for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var nb: Vector2i = door - d
		if _passable(port, nb):
			port.walker.pos = nb
			port.move(d)  # 撞门
			break
	if not port.doors.is_in_cutscene():
		push_error("撞有剧情的门未触发剧情对话")
		return false
	var body: String = port.doors.director.current_line()["body"]
	if body != "阿明，請進！":
		push_error("剧情台词/变量代入有误：%s" % body)
		return false
	print("  剧情触发：撞门 → find_entry 命中 → 对话『%s』(say→台词, portrait→头像, $n 代入)" % body)
	port.doors.director.advance()  # 越过末句 → FE → finished
	await process_frame
	if port.doors.is_in_cutscene():
		push_error("剧情未结束")
		return false
	if not port.doors.is_in_facility():
		push_error("剧情演完未落入常规设施")
		return false
	print("  剧情演完 → 照常进设施『%s』" % port.doors.facility_scene.facility_name())
	port.doors.facility_scene._request_exit()
	await process_frame
	return true


## 找一个可通行的设施门口，从相邻可通行格走入；成功进入返回 true。
func _enter_a_facility(port: Node2D) -> bool:
	var ft = port.facilities
	for slot in ft.present_slots():
		var target: Vector2i = ft.slots[slot]  # 门格本身不可踏，从相邻街道面门撞入
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var nb: Vector2i = target - d
			if _passable(port, nb):
				port.walker.pos = nb
				port.move(d)
				if port.doors.is_in_facility():
					return true
	return false


func _passable(port: Node2D, pos: Vector2i) -> bool:
	return port.map.in_bounds(pos.x, pos.y) and port.passability.is_passable(port.map.tile_at(pos.x, pos.y))
