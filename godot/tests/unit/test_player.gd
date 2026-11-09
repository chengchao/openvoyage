## Player（主角 avatar）单元测试：身份 + 移动/朝向（委托 GridWalker），纯逻辑。
extends GutTest


func _player(char_id := 0) -> Player:
	# 3×3：图块 0 可走，>=1 墙
	var m := PortMap.new(3, 3, PackedByteArray([0, 0, 1, 0, 1, 0, 0, 0, 0]))
	var pass_rule := TilePassability.new(PackedByteArray([1, 1, 1, 1]), [0])
	return Player.new(GridWalker.new(m, pass_rule, Vector2i(0, 0)), char_id)


func test_identity() -> void:
	assert_eq(_player(3).character_id, 3)


func test_position_and_facing_delegate() -> void:
	var p := _player()
	assert_eq(p.pos, Vector2i(0, 0))
	assert_eq(p.facing, Vector2i.DOWN)


func test_move_updates_pos_and_facing() -> void:
	var p := _player()
	assert_true(p.try_move(Vector2i.RIGHT))
	assert_eq(p.pos, Vector2i(1, 0))
	assert_eq(p.facing, Vector2i.RIGHT)


func test_move_blocked_keeps_pos_but_turns() -> void:
	var p := _player()
	p.try_move(Vector2i.RIGHT)               # (1,0)
	assert_false(p.try_move(Vector2i.RIGHT))  # (2,0)=墙
	assert_eq(p.pos, Vector2i(1, 0))
	assert_eq(p.facing, Vector2i.RIGHT)
