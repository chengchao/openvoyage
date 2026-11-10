## 给 agent 用的港口接口：observe() 返回可序列化的局面，act() 执行一个动作（走路会等物理帧，需 await）。
## 走路经真实输入动作与物理引擎，菜单/剧情经 DoorFlow → PortSession，与玩家操作同一路径；headless 可玩。
class_name PortAgent
extends RefCounted

const WALK_ACTIONS := {"up": "ui_up", "down": "ui_down", "left": "ui_left", "right": "ui_right"}
const MODE_NAMES := {
	PortSession.Mode.WALKING: "walking",
	PortSession.Mode.CUTSCENE: "cutscene",
	PortSession.Mode.FACILITY_MENU: "facility_menu",
	PortSession.Mode.AMOUNT_ENTRY: "amount_entry",
	PortSession.Mode.GAME_MENU: "game_menu",
	PortSession.Mode.GOODS_PICK: "goods_pick",
}

var port: PortScene3D


func _init(p_port: PortScene3D) -> void:
	port = p_port


func observe() -> Dictionary:
	var flow := port.doors
	var s := flow.session
	var me := port.player.global_position
	var doors := []
	for d: PortDoor in port.find_children("*", "PortDoor", true, false):
		var at := d.global_position
		doors.append({"slot": d.slot, "name": FacilityType.of(d.slot).name,
			"at": [at.x, at.y, at.z], "distance": me.distance_to(at)})
	doors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
	var obs := {
		"mode": MODE_NAMES[s.mode],
		"position": [me.x, me.y, me.z],
		"doors": doors,
		"gold": s.player_state.gold,
		"bank": s.player_state.bank,
		"cargo": s.player_state.cargo.duplicate(),
		"said": flow.last_said,
	}
	if flow.facility_scene != null:
		obs["facility"] = {"slot": s.slot, "name": flow.facility_scene.facility_name(),
			"menu": Array(flow.facility_scene.menu_labels())}
	if flow.director != null:
		obs["line"] = flow.director.current_line()
	if s.mode == PortSession.Mode.GOODS_PICK:
		obs["pick"] = {"prompt": s.pick_prompt,
			"options": s.pick_options.map(func(row: Dictionary) -> String: return row["label"])}
	if s.mode == PortSession.Mode.AMOUNT_ENTRY:
		obs["amount"] = {"prompt": s.amount_prompt, "cap": s.amount_cap}
	var gm := flow.game_menu
	if gm != null:
		obs["game_menu"] = {"categories": Array(gm.category_labels()), "items": Array(gm.item_labels()),
			"category": gm.category_index(), "item": gm.item_index(), "detail": gm.detail_text()}
	return obs


## 执行一个动作，合法且已执行返回 true。动作：
## {"do":"walk","dir":"up|down|left|right","seconds":s} {"do":"choose","index":i}（末项 = 離開）
## {"do":"leave"} {"do":"pick","index":i}（选货） {"do":"amount","value":n}
## {"do":"cancel"}（取消选货或金额输入） {"do":"next"}（剧情下一句）
## {"do":"menu"}（开游戏内选单） {"do":"menu_select","category":i,"item":j}（移光标） {"do":"close"}（关选单）
func act(a: Dictionary) -> bool:
	var flow := port.doors
	var mode := flow.session.mode
	match a.get("do"):
		"walk":
			var action: String = WALK_ACTIONS.get(a.get("dir"), "")
			if mode != PortSession.Mode.WALKING or action == "":
				return false
			Input.action_press(action)
			for _i in maxi(1, ceili(float(a.get("seconds", 0.1)) * Engine.physics_ticks_per_second)):
				await port.get_tree().physics_frame
			Input.action_release(action)
			return true
		"choose":
			var menu := flow.facility_scene.menu_labels() if flow.facility_scene != null else PackedStringArray()
			var i: int = a.get("index", -1)
			if mode != PortSession.Mode.FACILITY_MENU or i < 0 or i >= menu.size():
				return false
			if i == menu.size() - 1:
				flow.leave()
			else:
				flow.choose(i)
			return true
		"leave":
			if mode != PortSession.Mode.FACILITY_MENU:
				return false
			flow.leave()
			return true
		"pick":
			var i: int = a.get("index", -1)
			if mode != PortSession.Mode.GOODS_PICK or i < 0 or i >= flow.session.pick_options.size():
				return false
			flow.pick(i)
			return true
		"amount":
			if mode != PortSession.Mode.AMOUNT_ENTRY:
				return false
			flow.confirm_amount(int(a.get("value", -1)))
			return flow.session.mode == PortSession.Mode.FACILITY_MENU
		"cancel":
			match mode:
				PortSession.Mode.GOODS_PICK:
					flow.cancel_pick()
				PortSession.Mode.AMOUNT_ENTRY:
					flow.cancel_amount()
				_:
					return false
			return true
		"menu":
			if mode != PortSession.Mode.WALKING:
				return false
			flow.open_menu()
			return true
		"menu_select":
			var c: int = a.get("category", -1)
			var j: int = a.get("item", -1)
			if mode != PortSession.Mode.GAME_MENU or j < 0 or j >= GameMenu.items(c).size():
				return false
			flow.game_menu.move_category(c - flow.game_menu.category_index())
			flow.game_menu.move_item(j - flow.game_menu.item_index())
			return true
		"close":
			if mode != PortSession.Mode.GAME_MENU:
				return false
			flow.close_menu()
			return true
		"next":
			if mode != PortSession.Mode.CUTSCENE:
				return false
			flow.director.advance()
			return true
	return false
