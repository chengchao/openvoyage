## 进门流程的表现层：玩法状态全在 PortSession（sim）。玩家/agent 的动作转给 session，
## 再由 _sync() 让界面（剧情对话 / 设施面板 / 单选列表 / 金额输入 / 游戏内选单）与 session.mode 一致。
class_name DoorFlow
extends Node

const TITLE_SCENE := "res://game/main.tscn"
const NOTICE_SECONDS := 4.0

var session := PortSession.new()
var facility_scene: FacilityScene
var director: DialogueDirector
var pick_list: PickList
var amount_entry: AmountEntry
var game_menu: GameMenuPanel
var last_said := ""  # 店主最近一句回话或抵港通知（供 agent 观察）
var enter_port := PortScene3D.enter  # 出航/读档后换进 world 所在港；测试换成不动场景树的假函数

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
	return session.slot >= 0 and session.mode in [
		PortSession.Mode.FACILITY_MENU, PortSession.Mode.PICK, PortSession.Mode.AMOUNT_ENTRY]


func is_in_cutscene() -> bool:
	return session.mode == PortSession.Mode.CUTSCENE


func is_busy() -> bool:
	return session.mode != PortSession.Mode.WALKING


func open(slot: int) -> void:
	if session.enter_door(slot):
		last_said = ""
		_sync()


func arrive() -> void:
	if session.arrive():
		_sync()


func choose(index: int) -> void:
	_say(session.choose(index))


func leave() -> void:
	if session.leave():
		_sync()


func open_departure() -> void:
	if session.open_departure():
		_sync()


func pick(index: int) -> void:
	if session.pick(index):
		_sync()
		if session.mode == PortSession.Mode.SAILED:
			enter_port.call(get_tree(), session.world)


## 屏幕上方显示几秒的一行字（抵港通知）。
func announce(text: String) -> void:
	last_said = text
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.position.y = 16
	layer.add_child(label)
	add_child(layer)
	get_tree().create_timer(NOTICE_SECONDS).timeout.connect(layer.queue_free)


func cancel_pick() -> void:
	if session.cancel_pick():
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
		&"save":
			session.save_game()
		&"load":
			var loaded := session.load_game()
			if loaded != null:
				enter_port.call(get_tree(), loaded)


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
			_on_story_finished()  # 只有开窗/换头像、没有一句台词
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

	var picking := m == PortSession.Mode.PICK
	if picking and pick_list == null:
		pick_list = PickList.new()
		pick_list.setup(session.pick_prompt, PackedStringArray(
			session.pick_options.map(func(row: Dictionary) -> String: return row["label"])))
		pick_list.picked.connect(pick)
		pick_list.cancelled.connect(cancel_pick)
		add_child(pick_list)
	elif not picking and pick_list != null:
		pick_list.queue_free()
		pick_list = null

	var entering := m == PortSession.Mode.AMOUNT_ENTRY
	if entering and amount_entry == null:
		amount_entry = AmountEntry.new()
		amount_entry.setup(session.amount_prompt, session.amount_cap, 0, session.amount_step)
		amount_entry.confirmed.connect(confirm_amount)
		amount_entry.cancelled.connect(cancel_amount)
		add_child(amount_entry)
	elif not entering and amount_entry != null:
		amount_entry.queue_free()
		amount_entry = null
	if facility_scene != null:
		facility_scene.set_process_unhandled_input(not (picking or entering))  # 单选列表/金额输入时输入归模态

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
