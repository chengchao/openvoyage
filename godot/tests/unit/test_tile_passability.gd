## TilePassability 单元测试：按 PORTCHIP 的 4 字节图块号分界把图块分区，判定可通行。
##
## 分界 b=[b0,b1,b2,b3] 把图块号 0..239 切成 5 个区间（图块按属性排序存放）：
##   [0,b0)=区0  [b0,b1)=区1 … [b3,240)=区4
## 哪些区可通行尚未从原版完全验证（语义由玩法里程碑校准），故做成可配置的区集合；
## 本测试只验证「分区 + 区集合 → 可否通行」这一机制的正确性。
extends GutTest


func test_region_partitions_by_boundaries() -> void:
	var p := TilePassability.new(PackedByteArray([2, 4, 6, 8]), [])
	assert_eq(p.region(0), 0)
	assert_eq(p.region(1), 0)
	assert_eq(p.region(2), 1)
	assert_eq(p.region(5), 2)
	assert_eq(p.region(8), 4)
	assert_eq(p.region(239), 4)


func test_is_passable_uses_passable_region_set() -> void:
	var p := TilePassability.new(PackedByteArray([2, 4, 6, 8]), [0])
	assert_true(p.is_passable(0), "区0 可通行")
	assert_true(p.is_passable(1))
	assert_false(p.is_passable(2), "区1 不可通行")
	assert_false(p.is_passable(100))


func test_multiple_passable_regions() -> void:
	var p := TilePassability.new(PackedByteArray([2, 4, 6, 8]), [0, 2])
	assert_true(p.is_passable(1))   # 区0
	assert_false(p.is_passable(3))  # 区1
	assert_true(p.is_passable(5))   # 区2
