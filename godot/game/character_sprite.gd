## 可复用的走路精灵组件（表现层）。给它朝向/走路状态，它自己选帧显示。
## 港口、设施、世界地图等场景共用，避免每个场景重复精灵逻辑。
##
## 程序员美术：全体角色共用一张自制占位精灵，按套号上色区分（不用原版 CHAR.LZW）。
## 帧序约定 0,1=背(UP) 2,3=右 4,5=正(DOWN) 6,7=左，留给日后的正式精灵表。
class_name CharacterSprite
extends Sprite2D

const DIR_FRAMES := {
	Vector2i.DOWN: [4, 5],
	Vector2i.UP: [0, 1],
	Vector2i.LEFT: [6, 7],
	Vector2i.RIGHT: [2, 3],
}
const PLACEHOLDER := preload("res://data/placeholder/images/char_placeholder.png")
const TINTS := [Color.WHITE, Color(1.0, 0.75, 0.75), Color(0.75, 0.85, 1.0), Color(0.8, 1.0, 0.75)]

var _facing := Vector2i.DOWN
var _walk := 0


## 装上占位精灵；variant = 角色套号（主角 0、NPC 1..），决定色调。
func load_set(variant := 0) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture = PLACEHOLDER
	modulate = TINTS[variant % TINTS.size()]


func set_facing(f: Vector2i) -> void:
	_facing = f


func step_walk() -> void:
	_walk = 1 - _walk


func facing() -> Vector2i:
	return _facing


func walk_step() -> int:
	return _walk


## 当前应显示的帧号（按朝向 + 走路步）。
func current_frame() -> int:
	var pair: Array = DIR_FRAMES.get(_facing, DIR_FRAMES[Vector2i.DOWN])
	return pair[_walk % pair.size()]
