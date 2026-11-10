## 一局游戏的全部可存档状态（纯逻辑，RefCounted）：玩家经济、剧情进度、所在港、日期。
## current 跨场景存活：每个港口场景各建自己的 PortSession，但读写的都是这一份。
class_name World
extends RefCounted

const STARTING_GOLD := 2000  # 开局现金（占位，待开场剧情校准）
const MAX_WHOLE := 1 << 53  # JSON 数字是 double，超过这个就不再是精确整数

static var current: World

var player := PlayerState.new(STARTING_GOLD, 0)
var story := GameState.new()
var port_id := 0
var day := 1


static func new_game() -> World:
	current = World.new()
	return current


func to_dict() -> Dictionary:
	return {"port_id": port_id, "day": day, "player": player.to_dict(), "story": story.to_dict()}


## 存档是外部输入：任何字段缺失或不合法都返回 null，绝不产出半成品。
static func from_dict(d: Variant) -> World:
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var p := PlayerState.from_dict(d.get("player"))
	var s := GameState.from_dict(d.get("story"))
	if p == null or s == null or not is_whole(d.get("port_id"), 0) or not is_whole(d.get("day"), 1):
		return null
	if Market.port_scene(int(d["port_id"])) == "":
		return null
	var w := World.new()
	w.player = p
	w.story = s
	w.port_id = int(d["port_id"])
	w.day = int(d["day"])
	return w


## v 是不小于 lo 的整数值（JSON 读回来的整数是 float，所以两种类型都收）。
static func is_whole(v: Variant, lo: float = -MAX_WHOLE) -> bool:
	return typeof(v) in [TYPE_INT, TYPE_FLOAT] and v == floorf(v) and v >= lo and v <= MAX_WHOLE
