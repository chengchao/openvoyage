## 进门流程的表现层：玩法状态全在 PortSession（sim）。玩家/agent 的动作转给 session，
## 再由 _sync() 让界面（剧情对话 / 设施面板 / 金额输入 / 游戏内选单）与 session.mode 一致。
class_name DoorFlow
extends Node

const STARTING_GOLD := PortSession.STARTING_GOLD
const TITLE_SCENE := "res://game/main.tscn"

var session := PortSession.new()
var facility_scene: FacilityScene
var director: DialogueDirector
var amount_entry: AmountEntry
var game_menu: GameMenuPanel
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


func open_menu() -> void:
	if session.open_menu():
		_sync()


func close_menu() -> void:
	if session.close_menu():
		_sync()


## 港里按 ESC 开选单。设施/金额输入/选单各自的 ESC 都先被它们吃掉（已标记 handled），到不了这里，
## 所以关设施的那一下不会顺手开选单，开选单的那一下也不会被新建的面板再收到。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and session.mode == PortSession.Mode.WALKING:
		get_viewport().set_input_as_handled()
		open_menu()


func _on_menu_action(action: StringName) -> void:
	match action:
		&"title":
			get_tree().change_scene_to_file(TITLE_SCENE)
		&"quit":
			get_tree().quit()


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
		if not director.play(session.interp):
			_on_story_finished()  # 入口无可演内容 → 直接进设施
			return
	elif m != PortSession.Mode.CUTSCENE and director != null:
		director.queue_free()
		director = null

	var in_facility := is_in_facility()
	if in_facility and facility_scene == null:
		facility_scene = FacilityScene.new()
		facility_scene.layer = 5  # 盖在港口 HUD(layer 1) 之上
		facility_scene.setup(FacilityType.of(session.slot))
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

	var in_menu := m == PortSession.Mode.GAME_MENU
	if in_menu and game_menu == null:
		game_menu = GameMenuPanel.new()
		game_menu.layer = 5
		game_menu.setup(session)
		game_menu.close_requested.connect(close_menu)
		game_menu.action_requested.connect(_on_menu_action)
		add_child(game_menu)
	elif not in_menu and game_menu != null:
		game_menu.queue_free()
		game_menu = null


func _on_story_finished() -> void:
	if session.story_finished():
		_sync()
