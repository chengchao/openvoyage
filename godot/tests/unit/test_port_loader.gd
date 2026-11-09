## PortLoader 单元测试：自制港图（文本版图，非原版 PORTMAP）解析 + 默认里斯本港。
extends GutTest

## 小房间：四周墙，出生 @ (6,6)，正下方 (6,7) 是酒馆门(槽1)。
const ROOM := """
#############
#...........#
#...........#
#...........#
#...........#
#...........#
#.....@.....#
#.....1.....#
#...........#
#...........#
#...........#
#...........#
#############
"""


func test_parse_layout_size_spawn_and_door() -> void:
	var d := PortLoader.parse_layout(ROOM, 7)
	assert_eq(d.map.width, 13)
	assert_eq(d.map.height, 13)
	assert_eq(d.spawn, Vector2i(6, 6))
	assert_eq(d.port_id, 7)
	var ft := FacilityTable.new(d.facilities)
	assert_eq(d.facilities.size(), FacilityTable.SLOT_COUNT)
	assert_eq(ft.facility_at(Vector2i(6, 7)), 1, "门字符 1 → 槽 1")
	assert_eq(ft.present_slots(), [1])


func test_parse_layout_passability() -> void:
	var d := PortLoader.parse_layout("~=.#0@", 0)
	var p := d.passability
	var t := func(x: int) -> int: return d.map.tile_at(x, 0)
	assert_false(p.is_passable(t.call(0)), "海不可走")
	assert_true(p.is_passable(t.call(1)), "码头可走")
	assert_true(p.is_passable(t.call(2)), "街道可走")
	assert_false(p.is_passable(t.call(3)), "墙不可走")
	assert_false(p.is_passable(t.call(4)), "门格本身不可踏（面门撞入）")
	assert_true(p.is_passable(t.call(5)), "出生点是街道")
	assert_eq(FacilityTable.new(d.facilities).facility_at(Vector2i(4, 0)), 0)


func test_parse_layout_slots_a_and_b_are_10_and_11() -> void:
	var d := PortLoader.parse_layout(".ab@", 0)
	var ft := FacilityTable.new(d.facilities)
	assert_eq(ft.facility_at(Vector2i(1, 0)), 10)
	assert_eq(ft.facility_at(Vector2i(2, 0)), 11)


func test_parse_layout_rejects_ragged_rows() -> void:
	assert_null(PortLoader.parse_layout("..@\n.", 0), "行宽不齐 → null")


func test_parse_layout_rejects_missing_spawn() -> void:
	assert_null(PortLoader.parse_layout("...", 0), "无出生点 → null")


func test_default_port_is_lisbon_with_all_facilities_reachable() -> void:
	var d := PortLoader.load_default()
	assert_not_null(d, "res://data/ports/port_000.txt 应可解析")
	assert_eq(d.port_id, 0, "里斯本 = 港号 0（SNR 触发键高字节）")
	var w := GridWalker.new(d.map, d.passability, d.spawn, [Vector2i.RIGHT])
	assert_true(w.can_enter(d.spawn), "出生点连同右邻足迹可站立")
	var ft := FacilityTable.new(d.facilities)
	for slot in FacilityTable.SLOT_COUNT:
		assert_true(ft.is_present(slot), "里斯本应有槽 %d 的门" % slot)
		var door: Vector2i = ft.slots[slot]
		var reachable := false
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if w.can_enter(door - dir):
				reachable = true
		assert_true(reachable, "槽 %d 的门 %s 旁应有可站立格" % [slot, door])
