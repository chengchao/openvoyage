## 一个港口的设施坐标表（来自 ZA_DAT，见 docs/08 §8.3）：每港 12 槽，每槽是门口坐标或缺席。
## 纯逻辑：给定玩家格子查命中哪个槽 / 哪种设施（FacilityType）。
## 槽位↔设施类型的全港通用映射在 FacilityType 目录里；本类只管本港的「哪个槽在哪格」。
class_name FacilityTable
extends RefCounted

const ABSENT := Vector2i(-1, -1)
const SLOT_COUNT := 12

var slots: Array = []  # 每槽 Vector2i（缺席为 ABSENT）


func _init(slot_coords: Array) -> void:
	slots = slot_coords


func is_present(slot: int) -> bool:
	return slot >= 0 and slot < slots.size() and slots[slot] != ABSENT


## 玩家所在/面向格 pos 命中的设施槽号；无则 -1。缺席槽永不命中。
func facility_at(pos: Vector2i) -> int:
	for i in slots.size():
		if slots[i] != ABSENT and slots[i] == pos:
			return i
	return -1


## pos 命中的设施类型（FacilityType），无则 null。
func type_at(pos: Vector2i) -> FacilityType:
	return type_of(facility_at(pos))


## 槽号 → 设施类型（全港通用目录）。
func type_of(slot: int) -> FacilityType:
	return FacilityType.of(slot)


## 存在的设施槽号列表。
func present_slots() -> Array:
	var out: Array = []
	for i in slots.size():
		if is_present(i):
			out.append(i)
	return out


## 槽号 → 显示名（便捷封装，缺省 "?"）。
func name_of(slot: int) -> String:
	var t := FacilityType.of(slot)
	return t.name if t != null else "?"
