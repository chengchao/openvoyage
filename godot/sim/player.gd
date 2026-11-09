## 主角（avatar）：身份 + 网格位置/朝向；移动与碰撞委托 GridWalker。
##
## 纯逻辑 RefCounted、headless 可测。这是「玩家是谁 + 在哪 + 朝哪」的归处：
## character_id 选走路精灵套/主角；后续在此承载状态（声望/现金/船队…）并跨场景共用。
class_name Player
extends RefCounted

var walker: GridWalker
var character_id: int  # 走路精灵套号 / 主角编号（CHAR.LZW 第几套）


func _init(grid_walker: GridWalker, char_id := 0) -> void:
	walker = grid_walker
	character_id = char_id


var pos: Vector2i:
	get:
		return walker.pos

var facing: Vector2i:
	get:
		return walker.facing


## 朝 delta 走一格；委托 GridWalker（撞墙也转向）。返回是否真的移动。
func try_move(delta: Vector2i) -> bool:
	return walker.try_move(delta)
