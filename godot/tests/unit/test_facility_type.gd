## FacilityType 目录测试：12 设施类型、稳定 key、显示名、证据等级。
extends GutTest


func test_catalog_has_twelve_types() -> void:
	assert_eq(FacilityType.count(), 12)


func test_of_returns_type_by_slot() -> void:
	assert_eq(FacilityType.of(0).key, &"market")
	assert_eq(FacilityType.of(0).name, "交易所")
	assert_eq(FacilityType.of(1).key, &"tavern")
	assert_eq(FacilityType.of(10).key, &"church")
	assert_eq(FacilityType.of(11).name, "占卜师")


func test_slot_identities() -> void:
	assert_eq(FacilityType.of(7).key, &"armory", "槽 7 = 武器屋")
	# 实机校正（2026-06-10，逐门进门实证）：{银行,道具屋,行会} 在槽 6/8/9 上是 3-循环错位。
	# 真相：槽 6 门(纹章盾)=行会、槽 8 门(金器)=银行、槽 9 门(柱卷)=道具屋。
	assert_eq(FacilityType.of(6).key, &"guild", "槽 6 = 行会（实机校正）")
	assert_eq(FacilityType.of(8).key, &"bank", "槽 8 = 银行（实机校正）")
	assert_eq(FacilityType.of(9).key, &"item_shop", "槽 9 = 道具屋（实机校正）")


func test_of_out_of_range_is_null() -> void:
	assert_null(FacilityType.of(-1))
	assert_null(FacilityType.of(12))


func test_slot_matches_index() -> void:
	for i in FacilityType.count():
		assert_eq(FacilityType.of(i).slot, i)


func test_menu_index_maps_to_menudat_group() -> void:
	assert_eq(FacilityType.of(8).menu_index, 0, "银行 → MENU.DAT 组 0 实机校正")
	assert_eq(FacilityType.of(0).menu_index, 6, "交易所 → 组 6")
	assert_eq(FacilityType.of(9).menu_index, 5, "道具屋 → 组 5 实机校正")
	assert_eq(FacilityType.of(6).menu_index, 1, "行会 → 组 1 实机校正")
	assert_eq(FacilityType.of(2).menu_index, 22, "造船所 → 组 22")


func test_every_facility_has_unique_in_range_menu_index() -> void:
	var seen := {}
	for t in FacilityType.catalog():
		assert_true(t.menu_index >= 0 and t.menu_index < 61, "%s menu_index 越界" % t.key)
		assert_false(seen.has(t.menu_index), "menu_index 应唯一：%d" % t.menu_index)
		seen[t.menu_index] = true


func test_keys_are_unique() -> void:
	var seen := {}
	for t in FacilityType.catalog():
		assert_false(seen.has(t.key), "key 应唯一：%s" % t.key)
		seen[t.key] = true


func test_confidence_is_valid() -> void:
	var valid := [FacilityType.CONFIRMED, FacilityType.HIGH, FacilityType.TENTATIVE]
	for t in FacilityType.catalog():
		assert_true(t.confidence in valid, "%s 证据等级非法" % t.key)
