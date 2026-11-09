## 进门流程的表现层：玩法状态全在 PortSession（sim）。玩家/agent 的动作转给 session，
## 再由 _sync() 让界面（剧情对话 / 设施面板 / 金额输入）与 session.mode 一致。
class_name DoorFlow
extends Node

const STARTING_GOLD := PortSession.STARTING_GOLD

var session := PortSession.new()
var facility_scene: FacilityScene
var director: DialogueDirector
var amount_entry: AmountEntry
var last_said := ""  # 店主最近一句回话（供 agent 观察）

var port_id: int:
	get: return session.port_id
	set(v): session.port_id = v
var player_state: PlayerState:
	get: return session.player_state
	set(v): session.player_state = v


func inject_story(event_script: EventScript, state: GameState) -> void:
	session.event_script = event_script
	session.game_state = state


func is_in_facility() -> bool:
	return session.mode in [PortSession.Mode.FACILITY_MENU, PortSession.Mode.AMOUNT_ENTRY]


func is_in_cutscene() -> bool:
	return session.mode == PortSession.Mode.CUTSCENE


func is_busy() -> bool:
	return session.mode != PortSession.Mode.WALKING


func open(slot: int) -> void:
	if session.enter_door(slot):
		last_said = ""
		_sync()


func choose(index: int) -> void:
	_say(session.choose(index))


func leave() -> void:
	if session.leave():
		_sync()


func confirm_amount(amount: int) -> void:
	_say(session.confirm_amount(amount))


func cancel_amount() -> void:
	if session.cancel_amount():
		_sync()


func _say(line: String) -> void:
	_sync()
	if line != "":
		last_said = line
		facility_scene.say(line)


func _sync() -> void:
	var m := session.mode
	if m == PortSession.Mode.CUTSCENE and director == null:
		director = DialogueDirector.new()
		add_child(director)
		director.finished.connect(_on_story_finished)
		if not director.play(session.interp, PortLoader.converted_dir()):
			_on_story_finished()  # 入口无可演内容 → 直接进设施
			return
	elif m != PortSession.Mode.CUTSCENE and director != null:
		director.queue_free()
		director = null

	var in_facility := is_in_facility()
	if in_facility and facility_scene == null:
		facility_scene = FacilityScene.new()
		facility_scene.layer = 5  # 盖在港口 HUD(layer 1) 之上
		facility_scene.setup(FacilityType.of(session.slot), PortLoader.converted_dir())
		facility_scene.exit_requested.connect(leave)
		facility_scene.menu_selected.connect(func(index: int, _label: String) -> void: choose(index))
		add_child(facility_scene)
	elif not in_facility and facility_scene != null:
		facility_scene.queue_free()
		facility_scene = null

	var entering := m == PortSession.Mode.AMOUNT_ENTRY
	if entering and amount_entry == null:
		amount_entry = AmountEntry.new()
		amount_entry.setup(session.amount_prompt, session.amount_cap, 0)
		amount_entry.confirmed.connect(confirm_amount)
		amount_entry.cancelled.connect(cancel_amount)
		add_child(amount_entry)
	elif not entering and amount_entry != null:
		amount_entry.queue_free()
		amount_entry = null
	if facility_scene != null:
		facility_scene.set_process_unhandled_input(not entering)  # 金额输入时输入归模态


func _on_story_finished() -> void:
	if session.story_finished():
		_sync()
