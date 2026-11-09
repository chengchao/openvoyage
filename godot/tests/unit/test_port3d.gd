## HD-2D 港口：每个港口场景满足「港口契约」，主角能走、能撞门、不会掉进海里。
extends GutTest

const PORTS_DIR := "res://game/port3d/ports/"


func _port_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(PORTS_DIR):
		if f.ends_with(".tscn"):
			out.append(PORTS_DIR + f)
	return out


func _doors(root: Node) -> Array:
	return root.find_children("*", "PortDoor", true, false)


func _lisbon() -> PortScene3D:
	var s: PortScene3D = load(PORTS_DIR + "lisbon.tscn").instantiate()
	add_child_autofree(s)
	return s


func test_every_port_meets_the_contract() -> void:
	var paths := _port_paths()
	assert_gt(paths.size(), 0, "至少有一个 HD-2D 港口场景")
	for path in paths:
		var root: Node = load(path).instantiate()
		assert_true(root is PortScene3D, "%s 根节点是 PortScene3D" % path)
		assert_true(root.get_node_or_null("Spawn") is Marker3D, "%s 有 Spawn" % path)
		assert_true(root.get_node_or_null("Departure") is Area3D, "%s 有出航区 Departure" % path)
		var slots := {}
		for d in _doors(root):
			assert_between(d.slot, 0, 11, "%s 门槽号在 0..11" % path)
			assert_false(slots.has(d.slot), "%s 门槽号 %d 唯一" % [path, d.slot])
			slots[d.slot] = true
		assert_gt(slots.size(), 0, "%s 至少一扇门" % path)
		root.free()


func test_player_spawns_at_spawn_marker() -> void:
	var s := _lisbon()
	var spawn: Vector3 = s.get_node("Spawn").global_position
	assert_almost_eq(s.player.global_position.x, spawn.x, 0.01)
	assert_almost_eq(s.player.global_position.z, spawn.z, 0.01)


func test_walking_right_moves_player_east_on_the_ground() -> void:
	var s := _lisbon()
	await wait_seconds(0.3)
	var x0 := s.player.global_position.x
	Input.action_press("ui_right")
	await wait_seconds(0.6)
	Input.action_release("ui_right")
	assert_gt(s.player.global_position.x, x0 + 1.0, "按右走向东")
	assert_gt(s.player.global_position.y, -0.2, "仍站在地面上")


func test_quay_edge_keeps_player_out_of_the_sea() -> void:
	var s := _lisbon()
	await wait_seconds(0.3)
	Input.action_press("ui_down")
	await wait_seconds(2.5)
	Input.action_release("ui_down")
	assert_gt(s.player.global_position.y, -0.2, "朝海一直走也不会掉下码头")


func test_player_cannot_walk_while_inside_a_facility() -> void:
	var s := _lisbon()
	await wait_seconds(0.2)
	s.doors.open(1)
	var x0 := s.player.global_position.x
	Input.action_press("ui_right")
	await wait_seconds(0.4)
	Input.action_release("ui_right")
	assert_almost_eq(s.player.global_position.x, x0, 0.01, "设施中港口不响应方向键")


## 站到门前 1.5 单位处，按上（朝门）走进去。
func _walk_into(s: PortScene3D, door: PortDoor) -> void:
	await wait_seconds(0.2)
	s.player.global_position = Vector3(door.global_position.x, 0.1 + door.global_position.y - 1.0, door.global_position.z + 1.5)
	await wait_seconds(0.1)
	Input.action_press("ui_up")
	await wait_seconds(0.8)
	Input.action_release("ui_up")


func test_walking_into_a_door_enters_that_facility() -> void:
	var s := _lisbon()
	watch_signals(s)
	var door: PortDoor = _doors(s)[0]
	await _walk_into(s, door)
	assert_signal_emitted_with_parameters(s, "door_entered", [door.slot])
	assert_true(s.doors.is_in_facility(), "朝门走进设施")
	assert_eq(s.doors.facility_scene.facility_type().slot, door.slot, "进的是这扇门的设施")


func test_walking_past_a_door_sideways_does_not_enter() -> void:
	var s := _lisbon()
	var door: PortDoor = _doors(s)[0]
	await wait_seconds(0.2)
	s.player.global_position = Vector3(door.global_position.x - 2.0, 0.1, door.global_position.z)
	await wait_seconds(0.1)
	Input.action_press("ui_right")
	await wait_seconds(1.0)
	Input.action_release("ui_right")
	assert_gt(s.player.global_position.x, door.global_position.x + 1.0, "前提：确实横穿过门前")
	assert_false(s.doors.is_in_facility(), "横向擦过门不进设施")


func test_leaving_a_facility_stays_in_the_port() -> void:
	var s := _lisbon()
	await _walk_into(s, _doors(s)[0])
	s.doors.facility_scene._request_exit()
	await wait_seconds(0.3)
	assert_false(s.doors.is_in_facility(), "离开设施后留在港口，不会被门立刻再拉回去")
