## 港口场景 lint：从 Spawn 出发，用主角胶囊在 XZ 网格上洪泛能走到的地方，查掉坑、落差与走不到的门。
## 代码 lint（正则扫 .gd）看不见关卡几何，这些规则补的是那一半（见 test_lint.gd）。
extends GutTest

const PORTS_DIR := "res://game/port3d/ports/"
const CELL := 0.5
## 相邻两格可接受的高差；台阶坡每格约 0.3。
const STEP := 0.6
const RADIUS := 0.3
const HEIGHT := 1.6
const RULES := {
	"port-void": "走得到的地方脚下没有地面，主角会无限下坠（里斯本台阶两侧曾是空的）。补地面或加隐形墙。",
	"port-ledge": "走得到的边缘下方落差超过一级台阶，主角会掉下去（里斯本台地前缘曾无遮挡）。边缘加隐形墙（Bounds）。",
	"port-unreachable": "从 Spawn 走不到这扇门/出航区，多半是隐形墙把路堵了。",
	"port-departure-facing": "出航区 -Z 前方 3 米有地面、或身后 3 米没地面：Departure 没朝海，朝海推不会问去哪。把 Departure 绕 Y 转到 -Z 指向水面。",
}


## 射线正好落在 CSG 三角网的对角线上会漏检（实测里斯本台地顶 (5.5,-22.5)），故偏一点再打一次。
static func _floor(space: PhysicsDirectSpaceState3D, c: Vector2i, from_y: float, exclude: Array[RID]) -> Variant:
	for jitter in [Vector2.ZERO, Vector2(0.07, 0.03)]:
		var x: float = c.x * CELL + jitter.x
		var z: float = c.y * CELL + jitter.y
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, -50, z))
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			return hit.position.y
	return null


## 用胶囊扫过 c→n 这一步：只查落点会漏掉 CSG 三角网——胶囊整个在实心体里时与任何面都不接触。
static func _blocked(space: PhysicsDirectSpaceState3D, c: Vector2i, y: float, n: Vector2i, ny: float, exclude: Array[RID]) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.exclude = exclude
	var lift := 0.2 + HEIGHT * 0.5
	var from := Vector3(c.x * CELL, y + lift, c.y * CELL)
	q.transform = Transform3D(Basis(), from)
	q.motion = Vector3(n.x * CELL, ny + lift, n.y * CELL) - from
	return space.cast_motion(q)[0] < 1.0


## 返回 {reached: {Vector2i: 地面高}, problems: [{rule, at: Vector3}]}。
static func walk(space: PhysicsDirectSpaceState3D, spawn: Vector3, exclude: Array[RID] = []) -> Dictionary:
	var start := Vector2i(roundi(spawn.x / CELL), roundi(spawn.z / CELL))
	var reached := {start: _floor(space, start, spawn.y + STEP, exclude)}
	var problems := []
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		var y: float = reached[c]
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if reached.has(n):
				continue
			var fy: Variant = _floor(space, n, y + STEP, exclude)
			if fy == null or fy < y - STEP:
				if not _blocked(space, c, y, n, y, exclude):
					problems.append({
						"rule": "port-void" if fy == null else "port-ledge",
						"at": Vector3(n.x * CELL, y, n.y * CELL),
					})
				continue
			if _blocked(space, c, y, n, fy, exclude):
				continue
			reached[n] = fy
			queue.append(n)
	return {"reached": reached, "problems": problems}


static func reaches(reached: Dictionary, area: Area3D) -> bool:
	var box := (area.get_child(0) as CollisionShape3D).shape as BoxShape3D
	var half := box.size * 0.5
	var to_local := area.global_transform.affine_inverse()
	for c: Vector2i in reached:
		var p: Vector3 = to_local * Vector3(c.x * CELL, area.global_position.y, c.y * CELL)
		if absf(p.x) <= half.x and absf(p.z) <= half.z:
			return true
	return false


static func violations(port: PortScene3D, path: String) -> PackedStringArray:
	var space := port.get_world_3d().direct_space_state
	var spawn := (port.get_node("Spawn") as Marker3D).global_position
	var result := walk(space, spawn, [port.player.get_rid()])
	var by_rule := {}
	for p in result.problems:
		by_rule.get_or_add(p.rule, []).append(p.at)
	var targets: Array = port.find_children("*", "PortDoor", true, false)
	targets.append(port.get_node("Departure"))
	for t: Area3D in targets:
		if not reaches(result.reached, t):
			by_rule.get_or_add("port-unreachable", []).append(t.global_position)
	var departure := port.get_node("Departure") as Area3D
	var ground := func(along: float) -> bool:
		var p := departure.global_position - departure.global_basis.z * along
		return _floor(space, Vector2i(roundi(p.x / CELL), roundi(p.z / CELL)), 10.0, [port.player.get_rid()]) != null
	if ground.call(3.0) or not ground.call(-3.0):
		by_rule.get_or_add("port-departure-facing", []).append(departure.global_position)
	var out := PackedStringArray()
	for rule: String in by_rule:
		var at: Array = by_rule[rule]
		out.append("%s [%s] ×%d 例 %s：%s" % [path, rule, at.size(), at.slice(0, 3), RULES[rule]])
	return out


func _box(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.position = center
	body.add_child(shape)
	parent.add_child(body)


## 4×4 地台（顶面 y=floor_top），fenced 时四周围 3 高的墙。
func _yard(floor_top := 0.0, fenced := true) -> Node3D:
	var root := Node3D.new()
	add_child_autofree(root)
	_box(root, Vector3(0, floor_top - 0.5, 0), Vector3(4, 1, 4))
	if fenced:
		for s in [-1, 1]:
			_box(root, Vector3(s * 2.25, floor_top + 1.5, 0), Vector3(0.5, 3, 5))
			_box(root, Vector3(0, floor_top + 1.5, s * 2.25), Vector3(5, 3, 0.5))
	return root


func _rules(root: Node3D) -> Array:
	await wait_physics_frames(3)
	return walk(root.get_world_3d().direct_space_state, Vector3.ZERO).problems.map(func(p): return p.rule)


func test_fenced_yard_is_clean() -> void:
	assert_eq(await _rules(_yard()), [])


func test_unfenced_floor_edge_is_a_void() -> void:
	assert_has(await _rules(_yard(0.0, false)), "port-void", "地台边外没地面也没墙 → 掉坑")


func test_drop_onto_lower_floor_is_a_ledge() -> void:
	var root := _yard(0.0, false)
	_box(root, Vector3(0, -3.5, 0), Vector3(20, 1, 20))
	var rules: Array = await _rules(root)
	assert_has(rules, "port-ledge", "地台下 3 单位还有地面 → 无遮挡落差")
	assert_does_not_have(rules, "port-void")


func test_walking_into_a_solid_csg_wall_is_blocked_not_a_void() -> void:
	var root := _yard(0.0, false)
	var wall := CSGBox3D.new()
	wall.use_collision = true
	wall.size = Vector3(2, 3, 8)
	wall.position = Vector3(3, 1.5, 0)
	root.add_child(wall)
	await wait_physics_frames(3)
	var problems: Array = walk(root.get_world_3d().direct_space_state, Vector3.ZERO).problems
	assert_gt(problems.size(), 0, "另外三条边没墙，照报")
	assert_eq(problems.filter(func(p): return p.at.x > 1.9), [], "贴着实心 CSG 墙的那一边不该报坑")


func test_target_outside_the_fence_is_unreachable() -> void:
	var root := _yard()
	await wait_physics_frames(3)
	var reached: Dictionary = walk(root.get_world_3d().direct_space_state, Vector3.ZERO).reached
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	area.add_child(shape)
	root.add_child(area)
	area.global_position = Vector3(0, 1, 0)
	assert_true(reaches(reached, area), "围栏内的门走得到")
	area.global_position = Vector3(6, 1, 0)
	assert_false(reaches(reached, area), "围栏外的门走不到")


func test_every_port_scene_is_lint_clean() -> void:
	var found := PackedStringArray()
	for f in DirAccess.get_files_at(PORTS_DIR):
		if not f.ends_with(".tscn"):
			continue
		var port: PortScene3D = load(PORTS_DIR + f).instantiate()
		add_child(port)
		await wait_physics_frames(3)
		found.append_array(violations(port, PORTS_DIR + f))
		port.free()  # 各港共用一个物理空间：留着上一座，下一座会踩到它的地面上
	assert_eq(found.size(), 0, "\n".join(found))
