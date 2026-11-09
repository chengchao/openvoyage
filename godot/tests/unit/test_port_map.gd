## PortMap 单元测试：96×96 图块索引矩阵的纯逻辑模型（headless 可跑）。
extends GutTest


func _grid() -> PortMap:
	# 4×3：行优先
	#  0 1 2 3
	#  4 5 6 7
	#  8 9 10 11
	return PortMap.new(4, 3, PackedByteArray([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]))


func test_dimensions() -> void:
	var m := _grid()
	assert_eq(m.width, 4)
	assert_eq(m.height, 3)


func test_tile_at_is_row_major() -> void:
	var m := _grid()
	assert_eq(m.tile_at(0, 0), 0)
	assert_eq(m.tile_at(3, 0), 3)
	assert_eq(m.tile_at(1, 2), 9)


func test_in_bounds() -> void:
	var m := _grid()
	assert_true(m.in_bounds(0, 0))
	assert_true(m.in_bounds(3, 2))
	assert_false(m.in_bounds(4, 0))
	assert_false(m.in_bounds(0, 3))
	assert_false(m.in_bounds(-1, 0))


func test_rejects_size_mismatch() -> void:
	# 数据长度与 w*h 不符应失败
	assert_null(PortMap.try_create(2, 2, PackedByteArray([1, 2, 3])))
