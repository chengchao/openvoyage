## 设施类型描述符（纯逻辑数据）。一个门槽位 = 一种设施类型，全港通用。
## key 是稳定英文标识（代码按它分发逻辑/菜单）；name 为显示名。目录人工维护于 res://data/facilities.json。
class_name FacilityType
extends RefCounted

## 证据等级
const CONFIRMED := "confirmed"   # 招牌图案明确
const HIGH := "high"             # 招牌工具/分布强指向
const TENTATIVE := "tentative"   # 待 DOSBox 进门 / 解码 MENU 终验

var slot: int            # 门槽位号 0..11
var key: StringName      # 稳定标识：market/tavern/...
var name: String         # 显示名
var confidence: String   # CONFIRMED/HIGH/TENTATIVE


func _init(p_slot: int, p_key: StringName, p_name: String, p_confidence: String) -> void:
	slot = p_slot
	key = p_key
	name = p_name
	confidence = p_confidence


# --- 12 设施目录（人工维护的 JSON，懒加载并缓存） ---

const CATALOG_PATH := "res://data/facilities.json"

static var _catalog: Array[FacilityType] = []


static func catalog() -> Array[FacilityType]:
	if _catalog.is_empty():
		_catalog = _load_catalog()
	return _catalog


static func _load_catalog() -> Array[FacilityType]:
	var out: Array[FacilityType] = []
	if not FileAccess.file_exists(CATALOG_PATH):
		push_error("缺少设施目录：%s" % CATALOG_PATH)
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("facilities"):
		push_error("facilities.json 格式错误")
		return out
	for e in parsed["facilities"]:
		out.append(FacilityType.new(
			int(e["slot"]), StringName(e["key"]), str(e["name"]), str(e["confidence"])))
	return out


static func count() -> int:
	return catalog().size()


## 槽位号 → 设施类型；越界返回 null。
static func of(slot: int) -> FacilityType:
	var c := catalog()
	return c[slot] if slot >= 0 and slot < c.size() else null
