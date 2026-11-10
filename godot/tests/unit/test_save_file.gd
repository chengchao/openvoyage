## SaveFile：World ⇄ JSON 存档文件。只碰 user://test_tmp/ 下的临时文件。
extends GutTest

const PATH := "user://test_tmp/save_file.json"


func before_each() -> void:
	World.current = null
	DirAccess.remove_absolute(PATH)


func after_all() -> void:
	DirAccess.remove_absolute(PATH)


func _write(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(PATH.get_base_dir())
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_missing_file_does_not_exist_and_loads_null() -> void:
	assert_false(SaveFile.exists(PATH))
	assert_null(SaveFile.load(PATH))


func test_save_then_new_game_then_load_restores_progress() -> void:
	var w := World.new_game()
	w.player.buy("wine", 4, 40)
	w.player.deposit(600)
	w.day = 3
	assert_true(SaveFile.save(w, PATH))
	assert_true(SaveFile.exists(PATH))

	World.new_game()
	var back := SaveFile.load(PATH)
	assert_not_null(back)
	assert_eq([back.player.gold, back.player.bank, back.player.cargo, back.port_id, back.day],
		[World.STARTING_GOLD - 760, 600, {"wine": 4}, 0, 3])


func test_saving_again_overwrites_the_previous_save() -> void:
	var w := World.new()
	assert_true(SaveFile.save(w, PATH))
	w.player.deposit(100)
	assert_true(SaveFile.save(w, PATH))
	assert_eq(SaveFile.load(PATH).player.bank, 100)
	assert_false(FileAccess.file_exists(PATH + ".tmp"), "不留临时文件")


func test_save_file_carries_a_version() -> void:
	SaveFile.save(World.new(), PATH)
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert_eq(int(doc["version"]), SaveFile.VERSION)


func test_corrupt_or_foreign_files_load_null() -> void:
	var good := {"version": SaveFile.VERSION, "world": World.new().to_dict()}
	var half := JSON.stringify(good)
	var newer := good.duplicate()
	newer["version"] = SaveFile.VERSION + 1
	var no_version := {"world": good["world"]}
	var bad_world := {"version": SaveFile.VERSION, "world": {"player": {}}}
	for text: String in ["", "not json", half.left(half.length() / 2), "[1, 2]", "42",
			JSON.stringify(newer), JSON.stringify(no_version), JSON.stringify(bad_world),
			JSON.stringify({"version": "1", "world": good["world"]})]:
		_write(text)
		assert_true(SaveFile.exists(PATH))
		assert_null(SaveFile.load(PATH), "应拒收：%s" % text.left(40))
	_write(JSON.stringify(good))
	assert_not_null(SaveFile.load(PATH), "前提：完整的存档读得出来")


func test_save_to_an_unwritable_path_reports_failure() -> void:
	_write("a file where the save's folder should be")
	assert_false(SaveFile.save(World.new(), PATH + "/save.json"))
