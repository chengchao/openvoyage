## 港口数据加载层：读自制港图 res://data/ports/port_NNN.txt（文本版图，入库；不用原版 PORTMAP/ZA_DAT）。
##
## 版图字符：
##   .  街道（可走）      =  码头（可走）     @  出生点（街道）
##   ~  海               #  建筑墙
##   0-9 a b  设施门（槽号 0..11，见 facilities.json）；门格本身不可踏，面门撞入。
class_name PortLoader
extends RefCounted

const PORTS_DIR := "res://data/ports"

# 图块号 = 渲染/碰撞用的种类号。可走图块排在前面，TilePassability 一条分界即可。
const ROAD := 0
const PIER := 1
const SEA := 2
const WALL := 3
const DOOR := 4
const TILE_OF := {".": ROAD, "@": ROAD, "=": PIER, "~": SEA, "#": WALL}
const DOOR_CHARS := "0123456789ab"


## 转换产物目录（文本/剧本 JSON，仍来自 converter）：默认 res://assets-converted，
## 可用环境变量 KOUKAI2_CONVERTED 覆盖。
static func converted_dir() -> String:
	var env := OS.get_environment("KOUKAI2_CONVERTED")
	return env if env != "" else "res://assets-converted"


## 默认港：里斯本（港号 0）。
static func load_default(port_id := 0) -> PortData:
	var path := PORTS_DIR.path_join("port_%03d.txt" % port_id)
	return parse_layout(FileAccess.get_file_as_string(path), port_id)


## 文本版图 → PortData；行宽不齐 / 无出生点 / 未知字符 → null。
static func parse_layout(text: String, port_id: int) -> PortData:
	var rows := text.strip_edges().split("\n")
	var w := rows[0].length()
	var tiles := PackedByteArray()
	var spawn := Vector2i(-1, -1)
	var fac: Array = []
	for i in FacilityTable.SLOT_COUNT:
		fac.append(FacilityTable.ABSENT)
	for y in rows.size():
		var row := rows[y]
		if row.length() != w:
			push_error("港图 %d 第 %d 行宽 %d ≠ %d" % [port_id, y, row.length(), w])
			return null
		for x in w:
			var c := row[x]
			var slot := DOOR_CHARS.find(c)
			if slot >= 0:
				fac[slot] = Vector2i(x, y)
				tiles.append(DOOR)
			elif TILE_OF.has(c):
				tiles.append(TILE_OF[c])
				if c == "@":
					spawn = Vector2i(x, y)
			else:
				push_error("港图 %d (%d,%d) 未知字符 %s" % [port_id, x, y, c])
				return null
	if spawn == Vector2i(-1, -1):
		push_error("港图 %d 缺出生点 @" % port_id)
		return null
	var passability := TilePassability.new(PackedByteArray([SEA]), [0])  # 图块 < SEA 可走
	var pd := PortData.new(PortMap.new(w, rows.size(), tiles), passability, spawn)
	pd.facilities = fac
	pd.port_id = port_id
	return pd
