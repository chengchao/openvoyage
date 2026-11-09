## 设施行为表解释器（纯逻辑，RefCounted）：把 (设施 key, 菜单项 0-based 序号) 解析为行为原语名。
## 表驱动——映射来自 res://data/facility_actions.json（与 converter 测试、wiki 同一真相源：
## 只记原版事实「菜单项→原语」，不含实现进度）。消费方（port_scene）按 action 名 match 分发：
## 有分支=已实装，落入 default=尚未開放。本类只做解析，不重复登记「哪些已实装」（那是代码的事）。
class_name FacilityActions
extends RefCounted

const CATALOG_PATH := "res://data/facility_actions.json"

static var _doc: Dictionary = {}


static func _load() -> Dictionary:
	if _doc.is_empty() and FileAccess.file_exists(CATALOG_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			_doc = parsed
	return _doc


## (设施 key, 菜单项序号) → 行为原语名（StringName）；未找到返回 &""。
static func action_of(facility_key: StringName, item_index: int) -> StringName:
	return resolve(facility_key, item_index).get("action", &"")


## 解析为 { action:StringName, needs:Array, kind:StringName, params:Dictionary }；未找到返回 {}。
## needs/kind 取自 actions 受控词表（原语契约），params 取自该菜单项行。
static func resolve(facility_key: StringName, item_index: int) -> Dictionary:
	var doc := _load()
	var rows: Array = doc.get("facilities", {}).get(String(facility_key), [])
	for row in rows:
		if int(row.get("item", -1)) == item_index:
			var action := StringName(row.get("action", ""))
			var cat: Dictionary = doc.get("actions", {}).get(String(action), {})
			return {
				"action": action,
				"needs": cat.get("needs", []),
				"kind": StringName(cat.get("kind", "")),
				"params": row.get("params", {}),
			}
	return {}


## 仅供测试：清空静态缓存。
static func _reset() -> void:
	_doc = {}
