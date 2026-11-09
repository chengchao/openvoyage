## NpcCrowd 自主游走单元测试（纯逻辑、注入 RNG）。行为仿原版（docs/08 §8.4）：
## 节流（移动间歇 2–5 拍）、75% 沿原方向直走、角色身位 2 格宽×2 格高
## （任两角色锚格切比雪夫距离 ≥2 才不相叠）。
extends GutTest

const W := 12


func _open_map(w := W) -> PortMap:
	var tiles := PackedByteArray()
	tiles.resize(w * w)  # 全 0 = 可通行
	return PortMap.new(w, w, tiles)


func _crowd(spawns: Array, w := W) -> NpcCrowd:
	var pass_rule := TilePassability.new(PackedByteArray([1, 1, 1, 1]), [0])
	return NpcCrowd.new(_open_map(w), pass_rule, spawns, [0, 8], [Vector2i.RIGHT])


func _rng(seed_v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r


func test_spawns_agents_with_char_sets() -> void:
	var c := _crowd([Vector2i(3, 3), Vector2i(5, 5), Vector2i(7, 7)])
	assert_eq(c.count(), 3)
	assert_eq(c.char_set_of(0), 0)
	assert_eq(c.char_set_of(1), 8)
	assert_eq(c.char_set_of(2), 0)  # 循环复用


func test_agents_stay_on_passable_tiles() -> void:
	var c := _crowd([Vector2i(2, 2), Vector2i(8, 8)])
	var rng := _rng(99)
	for _t in 200:
		c.step(rng)
		for i in c.count():
			var p: Vector2i = c.pos_of(i)
			assert_true(p.x >= 0 and p.x < W - 1 and p.y >= 0 and p.y < W,
				"NPC %d 越界/出可站立区于 %s" % [i, p])


func test_agents_keep_body_separation() -> void:
	# 角色画 2 格宽×2 格高：任两 NPC 锚格切比雪夫距离 <2 即身体相叠，永不允许。
	var c := _crowd([Vector2i(2, 2), Vector2i(4, 2), Vector2i(8, 8)])
	var rng := _rng(7)
	for _t in 200:
		c.step(rng)
		for i in c.count():
			for j in range(i + 1, c.count()):
				var a: Vector2i = c.pos_of(i)
				var b: Vector2i = c.pos_of(j)
				assert_true(absi(a.x - b.x) >= 2 or absi(a.y - b.y) >= 2,
					"NPC %d 与 %d 身体相叠：%s vs %s" % [i, j, a, b])


func test_keeps_body_distance_from_blocked_anchor() -> void:
	# blocked 传角色锚格（如玩家）：NPC 不会走到与其切比雪夫距离 <2 的格子。
	var c := _crowd([Vector2i(4, 5)])
	var rng := _rng(3)
	var player := Vector2i(7, 5)
	for _t in 300:
		c.step(rng, [player])
		var p: Vector2i = c.pos_of(0)
		assert_true(absi(p.x - player.x) >= 2 or absi(p.y - player.y) >= 2,
			"NPC 与玩家身体相叠于 %s" % p)


func test_mostly_keeps_walking_direction() -> void:
	# 原版 NPC 走直线：上一步顺利则 75% 沿原方向继续，而非每步均匀随机（同向仅 ~25%）。
	var c := _crowd([Vector2i(20, 20)], 40)
	var rng := _rng(11)
	var prev := Vector2i.ZERO
	var same := 0
	var moves := 0
	for _t in 2000:
		c.step(rng)
		if c.moved_last(0):
			var d: Vector2i = c.facing_of(0)
			if prev != Vector2i.ZERO:
				moves += 1
				if d == prev:
					same += 1
			prev = d
	assert_gt(moves, 50, "样本应足够")
	assert_gt(float(same) / moves, 0.5, "应多数时间沿原方向直走（均匀随机仅 ~25% 同向）")


func test_moves_are_throttled() -> void:
	# 原版节流：每次移动尝试后歇 2–5 拍 → 两次移动至少隔 3 拍；但不会永远不动。
	var c := _crowd([Vector2i(5, 5)])
	var rng := _rng(42)
	var last_move := -10
	var moves := 0
	for t in 200:
		c.step(rng)
		if c.moved_last(0):
			assert_gt(t - last_move, 2, "两次移动应至少隔 3 拍（节流 2–5）")
			last_move = t
			moves += 1
	assert_gt(moves, 10, "NPC 应持续游走")


func test_deterministic_with_same_seed() -> void:
	var a := _crowd([Vector2i(3, 3), Vector2i(8, 6)])
	var b := _crowd([Vector2i(3, 3), Vector2i(8, 6)])
	var ra := _rng(123)
	var rb := _rng(123)
	for _t in 60:
		a.step(ra)
		b.step(rb)
	for i in a.count():
		assert_eq(a.pos_of(i), b.pos_of(i), "同种子下 NPC %d 轨迹应一致" % i)


func test_respects_blocked_cells() -> void:
	# 单 NPC 被四面 blocked 围住 → 永不移动。
	var c := _crowd([Vector2i(5, 5)])
	var rng := _rng(1)
	var walls := [Vector2i(4, 5), Vector2i(6, 5), Vector2i(5, 4), Vector2i(5, 6)]
	for _t in 50:
		c.step(rng, walls)
	assert_eq(c.pos_of(0), Vector2i(5, 5), "四面被占应原地不动")
