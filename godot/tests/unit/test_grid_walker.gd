## GridWalker 单元测试：格子行走 + 碰撞（纯逻辑，集成 PortMap + TilePassability）。
extends GutTest


func _walker() -> GridWalker:
	# 3×3，图块 0=可通行，>=1=墙：
	#  0 0 1
	#  0 1 0
	#  0 0 0
	var m := PortMap.new(3, 3, PackedByteArray([0, 0, 1, 0, 1, 0, 0, 0, 0]))
	var passable := TilePassability.new(PackedByteArray([1, 1, 1, 1]), [0])  # 仅区0(=图块0)可走
	return GridWalker.new(m, passable, Vector2i(0, 0))


func test_default_facing_is_down() -> void:
	assert_eq(_walker().facing, Vector2i.DOWN)


func test_facing_updates_on_move() -> void:
	var w := _walker()
	w.try_move(Vector2i.RIGHT)
	assert_eq(w.facing, Vector2i.RIGHT)


func test_facing_turns_even_when_blocked() -> void:
	var w := _walker()
	w.try_move(Vector2i.RIGHT)            # (1,0)
	assert_false(w.try_move(Vector2i.RIGHT))  # (2,0)=墙，挡住
	assert_eq(w.facing, Vector2i.RIGHT, "撞墙也转向面对")
	assert_eq(w.pos, Vector2i(1, 0))


func test_moves_into_passable_cell() -> void:
	var w := _walker()
	assert_true(w.try_move(Vector2i.RIGHT))
	assert_eq(w.pos, Vector2i(1, 0))


func test_blocked_by_wall_tile() -> void:
	var w := _walker()
	w.try_move(Vector2i.RIGHT)            # → (1,0)
	assert_false(w.try_move(Vector2i.RIGHT), "(2,0)=墙，不能进")
	assert_eq(w.pos, Vector2i(1, 0), "撞墙后原地不动")


func test_blocked_by_out_of_bounds() -> void:
	var w := _walker()
	assert_false(w.try_move(Vector2i.UP))   # (0,-1) 越界
	assert_false(w.try_move(Vector2i.LEFT))  # (-1,0) 越界
	assert_eq(w.pos, Vector2i(0, 0))


func test_can_walk_a_path_around_walls() -> void:
	var w := _walker()
	# 下、下、右、右 走到 (2,2)
	assert_true(w.try_move(Vector2i.DOWN))
	assert_true(w.try_move(Vector2i.DOWN))
	assert_true(w.try_move(Vector2i.RIGHT))
	assert_true(w.try_move(Vector2i.RIGHT))
	assert_eq(w.pos, Vector2i(2, 2))


func test_footprint_blocks_standing_when_right_neighbor_is_wall() -> void:
	# 足迹含右格：(0,1) 可通行，但其右邻 (1,1) 是墙 → 不能站在 (0,1)。
	var m := PortMap.new(3, 3, PackedByteArray([0, 0, 1, 0, 1, 0, 0, 0, 0]))
	var passable := TilePassability.new(PackedByteArray([1, 1, 1, 1]), [0])
	var w := GridWalker.new(m, passable, Vector2i(0, 0), [Vector2i.RIGHT])
	assert_false(w.try_move(Vector2i.DOWN), "(0,1) 右邻 (1,1)=墙，身体会嵌墙 → 不可站")
	assert_eq(w.pos, Vector2i(0, 0))
	# 无足迹时同一格可站（对照）
	var w2 := GridWalker.new(m, passable, Vector2i(0, 0))
	assert_true(w2.try_move(Vector2i.DOWN))
