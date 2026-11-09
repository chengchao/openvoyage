## 港口场景集成测试：注入确定数据（测试小房间），断言碰撞与边界。
extends GutTest

const PortScene := preload("res://game/port_scene.tscn")
const ROOM := preload("res://tests/unit/test_port_loader.gd").ROOM  # 13×13 房间，出生 (6,6)，酒馆门 (6,7)


func _scene(data: PortData = null) -> PortScene:
	var s: PortScene = PortScene.instantiate()
	s.inject_data(data if data != null else PortLoader.parse_layout(ROOM, 0))  # 加树前注入，确定可复现
	add_child_autofree(s)
	return s


func test_camera_uses_native_zoom() -> void:
	# 取景靠工程像素基准分辨率 + 整数拉伸，相机本身不缩放（原生 16px 图块）。
	var s := _scene()
	assert_not_null(s._camera, "应已创建 Camera2D")
	assert_almost_eq(s._camera.zoom.x, s.CAMERA_ZOOM, 0.001)
	assert_almost_eq(s._camera.zoom.x, 1.0, 0.001)


func test_map_viewport_centers_character_in_rect() -> void:
	# 港图取景=居中 384×384(24×24 图块)矩形，两侧 HUD。主角居于矩形中心而非整屏中心。
	var s := _scene()
	var expect := s.get_viewport_rect().size * 0.5 \
		- (Vector2(s.MAP_VIEW.position) + Vector2(s.MAP_VIEW.size) * 0.5)
	assert_eq(s._camera.offset, expect, "相机偏移=屏中心−取景矩形中心")
	assert_eq(s.MAP_VIEW.size, Vector2i(384, 384), "取景 24×24 图块（实测自原版 640×400 截图）")


func test_spawns_wandering_npcs() -> void:
	var s := _scene()
	assert_not_null(s._npcs, "应有 NPC 群")
	assert_gt(s._npcs.count(), 0, "至少生成 1 个 NPC")
	assert_eq(s._npc_sprites.size(), s._npcs.count(), "每个 NPC 一个精灵")
	for i in s._npcs.count():
		assert_true(s.walker.can_enter(s._npcs.pos_of(i)), "NPC 出生格应可站立")


func test_camera_limits_keep_viewport_inside_map() -> void:
	var tiles := PackedByteArray()
	tiles.resize(40 * 30)
	var m := PortMap.new(40, 30, tiles)
	var pass_rule := TilePassability.new(PackedByteArray([1, 1, 1, 1]), [0])
	var s := _scene(PortData.new(m, pass_rule, Vector2i(20, 15)))
	assert_eq(s._camera.limit_left, 0)
	assert_eq(s._camera.limit_top, 0)
	assert_eq(s._camera.limit_right, 40 * s.TILE)
	assert_eq(s._camera.limit_bottom, 30 * s.TILE)


func test_camera_limits_center_maps_smaller_than_viewport() -> void:
	var s := _scene()
	assert_lt(s._camera.limit_left, 0)
	assert_lt(s._camera.limit_top, 0)
	assert_gt(s._camera.limit_right, s.map.width * s.TILE)
	assert_gt(s._camera.limit_bottom, s.map.height * s.TILE)


func test_character_sprite_is_two_by_two_tiles() -> void:
	# 精灵 32×32：角色图形横跨左右两半块(~20px)，取全宽不裁两侧肩/臂；逻辑碰撞仍 1 格（足迹另测）。
	var s := _scene()
	assert_not_null(s._char, "应有主角 Sprite2D")
	var tex: Texture2D = s._char.texture
	assert_not_null(tex, "主角应有纹理")
	assert_eq(tex.get_width(), s.TILE * 2)   # 32
	assert_eq(tex.get_height(), s.TILE * 2)  # 32


func test_character_is_half_tile_shifted_between_tiles() -> void:
	# 原版主角网格相对图块网格右移半格(8px)，居于两格之间 → 能正对 2 格宽门居中。
	var s := _scene()
	s.facilities = FacilityTable.new([])  # 避免触发设施
	var p := s.walker_pos()
	assert_almost_eq(s._char.position.x, float((p.x + 1) * s.TILE), 0.01, "主角渲染中心应落在格边界(两格之间)")


func test_character_sprite_follows_walker() -> void:
	var s := _scene()
	s._npcs = null  # 只验精灵跟随，移除 NPC 身位干扰
	var before: Vector2 = s._char.position
	s.move(Vector2i.RIGHT)  # 右侧无设施，纯移动
	assert_ne(s._char.position, before, "主角精灵应跟随移动")


func test_player_cannot_walk_into_npc_body() -> void:
	# 角色身位 2 格宽×2 格高：玩家目标格与 NPC 锚格切比雪夫距离 <2 即身体相叠 →
	# 如撞墙，原地只转向；反方向远离则照常可走。
	var s := _scene()
	s.facilities = FacilityTable.new([])  # 屏蔽设施触发
	var spawn := s.walker_pos()
	s._npcs = NpcCrowd.new(s.map, s.passability, [spawn + Vector2i(2, 0)], [0], [Vector2i.RIGHT])
	assert_false(s.move(Vector2i.RIGHT), "撞 NPC 身位不应移动")
	assert_eq(s.walker_pos(), spawn, "原地不动")
	assert_eq(s.walker.facing, Vector2i.RIGHT, "撞 NPC 仍应转向")
	assert_true(s.move(Vector2i.LEFT), "反向远离 NPC 应可走")


func test_spawns_on_a_passable_tile() -> void:
	var s := _scene()
	var p := s.walker_pos()
	assert_true(s.passability.is_passable(s.map.tile_at(p.x, p.y)), "出生点应可通行")


func test_cannot_walk_through_right_wall() -> void:
	var s := _scene()  # 占位房间 13×13，出生 (6,6)，墙在 x=12
	s.facilities = FacilityTable.new([])  # 屏蔽设施触发
	s._npcs = null  # 只验墙体碰撞，移除 NPC 身位干扰
	for _i in 10:
		s.move(Vector2i.RIGHT)
	# 足迹含右格：主角身体探入右邻格，故停在 (10) —— (11) 的右邻 (12) 是墙，会嵌墙。
	assert_eq(s.walker_pos(), Vector2i(10, 6), "停在右墙前一格(10)，身体不嵌入右墙")


func test_walk_10_each_direction_never_passes_a_wall() -> void:
	var s := _scene()
	s.facilities = FacilityTable.new([])  # 本测试只验碰撞，屏蔽设施触发
	s._npcs = null  # 只验墙体碰撞，移除 NPC 身位干扰
	var spawn := s.walker_pos()
	for dir in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		s.walker.pos = spawn
		for _i in 10:
			s.move(dir)
			var p := s.walker_pos()
			assert_true(s.map.in_bounds(p.x, p.y))
			assert_true(s.passability.is_passable(s.map.tile_at(p.x, p.y)))


func test_facing_facility_door_enters_without_stepping_on_it() -> void:
	var s := _scene()  # 测试房间：酒馆门 (6,7)，出生 (6,6)
	assert_false(s.doors.is_in_facility())
	s.move(Vector2i.DOWN)  # 面向门(6,7)撞入
	assert_eq(s.walker_pos(), Vector2i(6, 6), "门口不踏入，停在原格")
	assert_true(s.doors.is_in_facility(), "面门撞入应进入设施")


func test_movement_ignored_while_in_facility() -> void:
	var s := _scene()
	s.move(Vector2i.DOWN)  # 进入酒馆
	var p := s.walker_pos()
	s.move(Vector2i.RIGHT)  # 设施中：应被忽略
	assert_eq(s.walker_pos(), p, "设施模态层中港口移动被忽略")


func test_exit_closes_facility() -> void:
	var s := _scene()
	s.move(Vector2i.DOWN)
	assert_true(s.doors.is_in_facility())
	s.doors.facility_scene._request_exit()
	assert_false(s.doors.is_in_facility(), "退出后回到港口")
