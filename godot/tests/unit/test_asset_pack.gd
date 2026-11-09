## AssetPack 单元测试：薄加载层，读占位包 manifest 并按需解码图片（headless 可跑）。
extends GutTest


func test_loads_placeholder_pack() -> void:
	var pack := AssetPack.load_pack()
	assert_eq(pack.pack_name(), "placeholder-v0")
	assert_true(pack.items().size() >= 10, "占位包应至少含 10 项供查看器")


func test_load_image_returns_image_with_declared_size() -> void:
	var pack := AssetPack.load_pack()
	var entry: Dictionary = pack.items()[0]
	var img := pack.load_image(entry)
	assert_not_null(img, "首项图片应能解码")
	assert_eq(img.get_width(), int(entry["w"]))
	assert_eq(img.get_height(), int(entry["h"]))


func test_missing_pack_has_no_items() -> void:
	var pack := AssetPack.load_pack("res://data/does_not_exist.json")
	assert_eq(pack.items().size(), 0)
