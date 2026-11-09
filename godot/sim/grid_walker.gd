## 格子行走 + 碰撞（纯逻辑）。持有港图与可通行规则，按格移动；撞墙/越界则原地不动。
## 场景层只把输入翻译成方向、把 pos 映射成像素坐标，移动判定全在此处，可 headless 测。
class_name GridWalker
extends RefCounted

var map: PortMap
var passability: TilePassability
var pos: Vector2i
var facing := Vector2i.DOWN  # 朝向（供镜头/进设施判定「面前那格」用）
# 占位足迹：除所在格外，这些相对偏移的格也须可通行才能站立。
# 主角精灵右移半格(8px)、宽 16px，身体探入右邻格 → footprint=[RIGHT]，防止贴墙时身体嵌入右墙。
var footprint: Array = []


func _init(port_map: PortMap, tile_passability: TilePassability, start: Vector2i,
		tile_footprint: Array = []) -> void:
	map = port_map
	passability = tile_passability
	pos = start
	footprint = tile_footprint


func _passable(cell: Vector2i) -> bool:
	return map.in_bounds(cell.x, cell.y) and passability.is_passable(map.tile_at(cell.x, cell.y))


## 某格是否可站立：该格可通行，且足迹覆盖的相邻格也都可通行。
func can_enter(cell: Vector2i) -> bool:
	if not _passable(cell):
		return false
	for off in footprint:
		if not _passable(cell + off):
			return false
	return true


## 尝试朝 delta 方向移动一格；先转向面对该方向（撞墙也转向），可进则移动。
func try_move(delta: Vector2i) -> bool:
	if delta != Vector2i.ZERO:
		facing = delta
	var target := pos + delta
	if can_enter(target):
		pos = target
		return true
	return false
