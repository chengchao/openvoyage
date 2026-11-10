## 主菜单单元测试：纯 UI 组件，发信号、无场景树副作用，故可独立实例化测试。
extends GutTest

const MainMenuScene := preload("res://game/main_menu.tscn")


const SAVE_PATH := "user://test_tmp/main_menu.json"


func before_each() -> void:
	DirAccess.remove_absolute(SAVE_PATH)


func after_all() -> void:
	DirAccess.remove_absolute(SAVE_PATH)


func _make() -> MainMenu:
	var menu: MainMenu = MainMenuScene.instantiate()
	menu.save_path = SAVE_PATH
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


func test_continue_is_disabled_without_a_save() -> void:
	assert_true((_make().get_node("%ContinueButton") as Button).disabled)


func test_continue_is_disabled_when_the_save_is_unreadable() -> void:
	SaveFile.save(World.new(), SAVE_PATH)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string("{")
	f.close()
	assert_true((_make().get_node("%ContinueButton") as Button).disabled, "读不出来的存档不给点")


func test_continue_is_enabled_with_a_save_and_emits_continue_requested() -> void:
	SaveFile.save(World.new(), SAVE_PATH)
	var menu := _make()
	watch_signals(menu)
	var button := menu.get_node("%ContinueButton") as Button
	assert_false(button.disabled)
	button.pressed.emit()
	assert_signal_emitted(menu, "continue_requested")
