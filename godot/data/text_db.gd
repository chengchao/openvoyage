## 解码文本访问（表现层）：载入转换产物 text/*.json —— 自定义双字节码 → Unicode
## （码表 code_table.json，见 docs/HANDOFF-claude-code.md）。变量占位 $n/$s/$r/$d 原样保留。
## 缺文件（CI/无原档）时返回空串 → 调用方回退占位，保证 headless 可玩。
class_name TextDb
extends RefCounted

const GREETING := 0  # MESSAGE.DAT[0] = 店主通用招呼

static var _cache := {}


## 转换产物目录（文本/剧本 JSON，来自 converter）：默认 res://assets-converted，
## 可用环境变量 KOUKAI2_CONVERTED 覆盖。
static func converted_dir() -> String:
	var env := OS.get_environment("KOUKAI2_CONVERTED")
	return env if env != "" else "res://assets-converted"


static func _load(converted_dir: String, name: String) -> Array:
	var key := converted_dir + "/" + name
	if _cache.has(key):
		return _cache[key]
	var arr: Array = []
	var p := converted_dir.path_join("text/%s.json" % name)
	if converted_dir != "" and FileAccess.file_exists(p):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if j is Array:
			arr = j
	_cache[key] = arr
	return arr


## MESSAGE.DAT 第 i 条解码文本；越界/缺失 → 空串。
static func message(converted_dir: String, i: int) -> String:
	var arr := _load(converted_dir, "message")
	return str(arr[i]) if i >= 0 and i < arr.size() else ""


static func message_count(converted_dir: String) -> int:
	return _load(converted_dir, "message").size()


## MENU.DAT 第 group 组的菜单标签列表（解码后，组内 0x00 分隔已成换行）；缺失/越界 → 空。
## 例：bank 的组 0 → 该组 4 个菜单项文本。
static func menu(converted_dir: String, group: int) -> PackedStringArray:
	var arr := _load(converted_dir, "menu")
	if group < 0 or group >= arr.size():
		return PackedStringArray()
	var labels := PackedStringArray()
	for line in str(arr[group]).split("\n", false):
		var s := str(line).strip_edges()
		if s != "":
			labels.append(s)
	return labels


## 仅供测试：清空缓存。
static func _reset() -> void:
	_cache.clear()
