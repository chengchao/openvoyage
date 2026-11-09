## 主菜单单元测试：纯 UI 组件，发信号、无场景树副作用，故可独立实例化测试。
extends GutTest

const MainMenuScene := preload("res://game/main_menu.tscn")


func _make() -> Control:
	var menu: Control = MainMenuScene.instantiate()
	add_child_autofree(menu)
	return menu


func test_has_start_view_and_quit_buttons() -> void:
	var menu := _make()
	assert_not_null(menu.get_node_or_null("%StartButton"), "缺少 StartButton")
	assert_not_null(menu.get_node_or_null("%ViewButton"), "缺少 ViewButton")
	assert_not_null(menu.get_node_or_null("%QuitButton"), "缺少 QuitButton")


func test_view_button_emits_view_requested() -> void:
	var menu := _make()
	watch_signals(menu)
	(menu.get_node("%ViewButton") as Button).pressed.emit()
	assert_signal_emitted(menu, "view_requested")


func test_start_button_emits_start_requested() -> void:
	var menu := _make()
	watch_signals(menu)
	(menu.get_node("%StartButton") as Button).pressed.emit()
	assert_signal_emitted(menu, "start_requested")


func test_quit_button_emits_quit_requested() -> void:
	var menu := _make()
	watch_signals(menu)
	(menu.get_node("%QuitButton") as Button).pressed.emit()
	assert_signal_emitted(menu, "quit_requested")
