## FacilityTable（设施坐标表 + 触发查询）单元测试，纯逻辑。
extends GutTest


func test_facility_at_returns_slot_index() -> void:
	var ft := FacilityTable.new([Vector2i(5, 5), FacilityTable.ABSENT, Vector2i(3, 7)])
	assert_eq(ft.facility_at(Vector2i(5, 5)), 0)
	assert_eq(ft.facility_at(Vector2i(3, 7)), 2)


func test_facility_at_empty_tile_returns_minus_one() -> void:
	var ft := FacilityTable.new([Vector2i(5, 5)])
	assert_eq(ft.facility_at(Vector2i(9, 9)), -1)


func test_absent_slot_never_triggers() -> void:
	var ft := FacilityTable.new([FacilityTable.ABSENT, Vector2i(2, 2)])
	assert_false(ft.is_present(0))
	assert_true(ft.is_present(1))
	# 即便用 ABSENT 的坐标查询也不该命中缺席槽
	assert_eq(ft.facility_at(FacilityTable.ABSENT), -1)


func test_present_slots_lists_only_existing() -> void:
	var ft := FacilityTable.new([Vector2i(5, 5), FacilityTable.ABSENT, Vector2i(3, 7)])
	assert_eq(ft.present_slots(), [0, 2])


func test_name_of_delegates_to_facility_type() -> void:
	var ft := FacilityTable.new([])
	assert_eq(ft.name_of(0), "交易所")
	assert_eq(ft.name_of(1), "酒馆")
	assert_eq(ft.name_of(99), "?")  # 越界安全


func test_type_at_returns_facility_type() -> void:
	var ft := FacilityTable.new([Vector2i(5, 5), Vector2i(3, 7)])
	var t := ft.type_at(Vector2i(3, 7))
	assert_not_null(t)
	assert_eq(t.slot, 1)
	assert_eq(t.key, &"tavern")
	assert_null(ft.type_at(Vector2i(9, 9)), "空格无类型")
