## 游戏内选单表（纯逻辑，RefCounted）：分类 → 项 → 行为原语名，真相源 res://data/game_menu.json。
## 分类与项仿原版指令分组，标题与说明均为自撰。action 为空 = 尚未開放；消费方按 action 名分发。
class_name GameMenu
extends RefCounted

const CATALOG_PATH := "res://data/game_menu.json"

static var _doc: Dictionary = {}


static func _load() -> Dictionary:
	if _doc.is_empty() and FileAccess.file_exists(CATALOG_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			_doc = parsed
	return _doc


static func categories() -> Array:
	return _load().get("categories", [])


## 越界返回 []。
static func items(cat_index: int) -> Array:
	var cats := categories()
	if cat_index < 0 or cat_index >= cats.size():
		return []
	return cats[cat_index].get("items", [])


## 越界或尚未開放返回 &""。
static func action_of(cat_index: int, item_index: int) -> StringName:
	var rows := items(cat_index)
	if item_index < 0 or item_index >= rows.size():
		return &""
	return StringName(rows[item_index].get("action", ""))


## 仅供测试：清空静态缓存。
static func _reset() -> void:
	_doc = {}
