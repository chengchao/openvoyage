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
		"said": flow.last_said,
	}
	if flow.facility_scene != null:
		obs["facility"] = {"slot": s.slot, "name": flow.facility_scene.facility_name(),
			"menu": Array(flow.facility_scene.menu_labels())}
	if flow.director != null:
		obs["line"] = flow.director.current_line()
	if s.mode == PortSession.Mode.AMOUNT_ENTRY:
		obs["amount"] = {"prompt": s.amount_prompt, "cap": s.amount_cap}
	return obs


## 执行一个动作，合法且已执行返回 true。动作：
## {"do":"walk","dir":"up|down|left|right","seconds":s} {"do":"choose","index":i}（末项 = 離開）
## {"do":"leave"} {"do":"amount","value":n} {"do":"cancel"} {"do":"next"}（剧情下一句）
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
		"amount":
			if mode != PortSession.Mode.AMOUNT_ENTRY:
				return false
			flow.confirm_amount(int(a.get("value", -1)))
			return flow.session.mode == PortSession.Mode.FACILITY_MENU
		"cancel":
			if mode != PortSession.Mode.AMOUNT_ENTRY:
				return false
			flow.cancel_amount()
			return true
		"next":
			if mode != PortSession.Mode.CUTSCENE:
				return false
			flow.director.advance()
			return true
	return false
