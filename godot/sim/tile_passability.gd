## 图块可通行判定（纯逻辑）：按升序分界把图块号切成若干区间，落在可通行区间集合内即可走。
## 自制港图把可走图块排在最前（PortLoader：街道/码头 < 海），一条分界即可。
class_name TilePassability
extends RefCounted

var _boundaries: PackedByteArray
var _passable_regions: Dictionary = {}


func _init(boundaries: PackedByteArray, passable_regions: Array) -> void:
	_boundaries = boundaries
	for r in passable_regions:
		_passable_regions[int(r)] = true


## 图块号所属区间编号（0..len(boundaries)）。boundaries 须升序。
func region(tile: int) -> int:
	var r := 0
	for b in _boundaries:
		if tile >= b:
			r += 1
		else:
			break
	return r


func is_passable(tile: int) -> bool:
	return _passable_regions.has(region(tile))
