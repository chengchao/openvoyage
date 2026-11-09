## 港口图块索引矩阵的纯逻辑模型（不依赖场景树，headless 可测）。
## 数据来自自制文本港图（PortLoader.parse_layout），每格一个图块种类号。
class_name PortMap
extends RefCounted

var width: int
var height: int
var _tiles: PackedByteArray


func _init(w: int, h: int, tiles: PackedByteArray) -> void:
	width = w
	height = h
	_tiles = tiles


## 安全构造：数据长度与 w*h 不符时返回 null（供加载层校验）。
static func try_create(w: int, h: int, tiles: PackedByteArray) -> PortMap:
	if tiles.size() != w * h:
		return null
	return PortMap.new(w, h, tiles)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func tile_at(x: int, y: int) -> int:
	return _tiles[y * width + x]
