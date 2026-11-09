## 主路由（主场景根）。在「主菜单 ↔ 资料查看器」间切换屏幕，把各屏的意图信号接到导航/退出。
## 屏幕动态实例化、用完即弃，故各屏保持纯组件、零副作用、可独立单测。
extends Node

const MENU_SCENE := preload("res://game/main_menu.tscn")
const VIEWER_SCENE := preload("res://game/asset_viewer.tscn")
const NEW_GAME_SCENE := "res://game/port_scene.tscn"
## 启动参数 `-- --hd2d` 时开始游戏进 HD-2D 灰盒港口（feature flag，3D 港口接通设施后转正）。
const HD2D_SCENE := "res://game/port3d/ports/lisbon.tscn"

var _current: Node = null


func _ready() -> void:
	_goto_menu()
	if DisplayServer.get_name() != "headless":
		get_window().grab_focus.call_deferred()
		DisplayServer.window_move_to_foreground.call_deferred()


func _goto_menu() -> void:
	var menu := MENU_SCENE.instantiate()
	_swap(menu)
	menu.start_requested.connect(_on_start_requested)
	menu.view_requested.connect(_goto_viewer)
	menu.quit_requested.connect(_on_quit_requested)


func _goto_viewer() -> void:
	var viewer := VIEWER_SCENE.instantiate()
	_swap(viewer)
	viewer.back_requested.connect(_goto_menu)


func _swap(node: Node) -> void:
	if _current != null:
		_current.queue_free()
	_current = node
	add_child(node)


func _on_start_requested() -> void:
	var hd2d := OS.get_cmdline_user_args().has("--hd2d")
	get_tree().change_scene_to_file(HD2D_SCENE if hd2d else NEW_GAME_SCENE)


func _on_quit_requested() -> void:
	get_tree().quit()
