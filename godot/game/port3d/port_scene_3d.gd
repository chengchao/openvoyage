## HD-2D 港口场景根。港口本身在编辑器里手工摆（ports/*.tscn），本脚本只做契约：
## Spawn 放主角、朝 PortDoor 走进去时走进门流程（DoorFlow）、走进 Departure 问去哪座港、镜头以固定斜角跟随。
class_name PortScene3D
extends Node3D

signal door_entered(slot: int)

## 港号（SNR 事件键高字节；里斯本 = 0）。
@export var port_id := 0
## 镜头相对主角的偏移；固定朝北俯视，只平移不旋转。
@export var camera_offset := Vector3(0, 12, 24)
@export var camera_x_limits := Vector2(-14, 14)

## 站在门的触发区里、且方向键朝门里（门节点 -Z）推到这个程度才进门；横着擦过不算。
const DOOR_PUSH := 0.7

var player: Avatar3D
var _doors: Array[PortDoor] = []
var doors := DoorFlow.new()

@onready var _camera: Camera3D = $Camera3D


## 让 world 成为当前世界，并切到它所在港的场景。
static func enter(tree: SceneTree, world: World) -> void:
	World.current = world
	tree.change_scene_to_file(Market.port_scene(world.port_id))


func _ready() -> void:
	player = Avatar3D.new()
	player.name = "Player"
	add_child(player)
	player.global_position = ($Spawn as Marker3D).global_position
	if World.current == null:
		World.new_game()  # 直接运行港口场景（编辑器 F6、测试）时没有主菜单替它开局
	doors.session.world = World.current
	doors.port_id = port_id
	add_child(doors)
	_doors.assign(find_children("*", "PortDoor", true, false))
	($Departure as Area3D).body_entered.connect(func(body: Node3D) -> void:
		if body == player:
			doors.open_departure())
	var notice := World.current.take_notice()
	if notice != "":
		doors.announce(notice)
	_camera.global_position = _camera_target()
	_camera.look_at(player.global_position + Vector3.UP)


## 父节点先于主角跑物理帧：进门当帧即冻结主角（只停物理步，见 test_lint.gd process-mode-disabled）。
func _physics_process(_delta: float) -> void:
	player.set_physics_process(not doors.is_busy())
	if doors.is_busy():
		return
	var push := Avatar3D.input_dir()
	for door in _doors:
		if door.overlaps_body(player) and push.dot(-door.global_basis.z) >= DOOR_PUSH:
			door_entered.emit(door.slot)
			doors.open(door.slot)
			return


func _process(delta: float) -> void:
	_camera.global_position = _camera.global_position.lerp(_camera_target(), 1.0 - exp(-6.0 * delta))


func _camera_target() -> Vector3:
	var p := player.global_position + camera_offset
	p.x = clampf(p.x, camera_x_limits.x, camera_x_limits.y)
	return p
