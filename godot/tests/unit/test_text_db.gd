## TextDb 测试：载入解码文本，缺失时回退空串。
extends GutTest


func before_each() -> void:
	TextDb._reset()


func test_loads_messages_from_converted_dir() -> void:
	var dir := "user://test_text"
	DirAccess.make_dir_recursive_absolute(dir + "/text")
	var f := FileAccess.open(dir + "/text/message.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(["請進！", "要點什麼？"]))
	f.close()
	assert_eq(TextDb.message(dir, 0), "請進！")
	assert_eq(TextDb.message(dir, 1), "要點什麼？")
	assert_eq(TextDb.message_count(dir), 2)
	OS.move_to_trash(ProjectSettings.globalize_path(dir))


func test_menu_returns_group_labels() -> void:
	var dir := "user://test_menu"
	DirAccess.make_dir_recursive_absolute(dir + "/text")
	var f := FileAccess.open(dir + "/text/menu.json", FileAccess.WRITE)
	# 组 0 = 银行；解码后组内 0x00 分隔已成换行
	f.store_string(JSON.stringify(["甲項\n乙項\n丙項\n丁項", "子項\n丑項"]))
	f.close()
	var bank := TextDb.menu(dir, 0)
	assert_eq(bank.size(), 4)
	assert_eq(bank[0], "甲項")
	assert_eq(bank[3], "丁項")
	assert_eq(TextDb.menu(dir, 1)[0], "子項")
	OS.move_to_trash(ProjectSettings.globalize_path(dir))


func test_menu_out_of_range_or_missing_is_empty() -> void:
	assert_eq(TextDb.menu("", 0).size(), 0, "无原档/CI → 空数组")
	assert_eq(TextDb.menu("res://nonexistent", 9).size(), 0)


func test_missing_text_returns_empty() -> void:
	assert_eq(TextDb.message("", TextDb.GREETING), "", "无原档/CI → 空串，调用方回退占位")
	assert_eq(TextDb.message("res://nonexistent", 5), "")


func test_out_of_range_returns_empty() -> void:
	var dir := "user://test_text2"
	DirAccess.make_dir_recursive_absolute(dir + "/text")
	var f := FileAccess.open(dir + "/text/message.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(["a"]))
	f.close()
	assert_eq(TextDb.message(dir, 9), "")
	OS.move_to_trash(ProjectSettings.globalize_path(dir))
