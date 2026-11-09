## 资料查看器单元测试：列表填充、返回信号、批量打开图片不出错。
extends GutTest

const ViewerScene := preload("res://game/asset_viewer.tscn")


func _make() -> Control:
	var viewer: Control = ViewerScene.instantiate()
	add_child_autofree(viewer)
	return viewer


func test_lists_all_pack_items() -> void:
	var viewer := _make()
	var expected := AssetPack.load_pack().items().size()
	assert_eq((viewer.get_node("%ItemList") as ItemList).item_count, expected)


func test_back_button_emits_back_requested() -> void:
	var viewer := _make()
	watch_signals(viewer)
	(viewer.get_node("%BackButton") as Button).pressed.emit()
	assert_signal_emitted(viewer, "back_requested")


func test_load_all_images_opens_at_least_10() -> void:
	var viewer := _make()
	assert_true(viewer.load_all_images() >= 10, "查看器应能成功打开至少 10 项")
