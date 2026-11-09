## 一个港口的可玩数据：图块矩阵 + 可通行规则 + 出生点 + 设施门 + 港号。
class_name PortData
extends RefCounted

var map: PortMap
var passability: TilePassability
var spawn: Vector2i
var facilities: Array = []  # 12 个设施门口坐标（Vector2i，缺席为 FacilityTable.ABSENT）
var port_id: int = 0  # 港号（=SNR 触发键高字节；里斯本=0）。撞门派发剧情时作 find_entry 的 port。


func _init(port_map: PortMap, tile_passability: TilePassability, start: Vector2i) -> void:
	map = port_map
	passability = tile_passability
	spawn = start
