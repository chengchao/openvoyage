## GameConfig 单元测试（纯逻辑，headless 可跑）。
extends GutTest


func test_version_is_m0() -> void:
	assert_eq(GameConfig.VERSION, "0.0.1-m0")


func test_loads_placeholder_manifest() -> void:
	var manifest := GameConfig.load_manifest()
	assert_eq(manifest.get("pack"), "placeholder-v0")
	assert_true(manifest.has("version"), "manifest 应含 version 字段")


func test_missing_manifest_returns_empty_dict() -> void:
	var manifest := GameConfig.load_manifest("res://data/does_not_exist.json")
	assert_eq(manifest, {})
