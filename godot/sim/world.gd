## 一局游戏的全部可存档状态（纯逻辑，RefCounted）：玩家经济、剧情进度、所在港、日期。
## current 跨场景存活：每个港口场景各建自己的 PortSession，但读写的都是这一份。
class_name World
extends RefCounted

const STARTING_GOLD := 2000  # 开局现金；开场剧情里提到这个数，改它要一起改 data/story/main.json
const MAX_WHOLE := 1 << 53  # JSON 数字是 double，超过这个就不再是精确整数

static var current: World

var player := PlayerState.new(STARTING_GOLD, 0)
var story := GameState.new()
var story_script: EventScript  # 随包剧本：是内容不是进度，不进存档。裸 World.new() 没有 = 无剧情、无目标
var port_id := 0
var day := 1
var notice := ""  # 给下一个港口场景显示一次的话（抵港通知）；不进存档


static func new_game() -> World:
	current = World.new()
	var shipped := EventScript.load_shipped()
	if shipped != null:
		current.story_script = shipped
		current.story = GameState.new(shipped.scenario, 0)
		for key: String in shipped.names:
			current.story.set_name(key, shipped.names[key])
	return current


## 本局目标 {text, progress, target, met}，progress = 现金加存款；没有剧本返回 {}。
## 达成的那一刻记进旗标（剧本据此道贺），之后把钱花掉也仍算达成。
func goal() -> Dictionary:
	if story_script == null or story_script.goal.is_empty():
		return {}
	var target := int(story_script.goal["target"])
	var met_flag := int(story_script.goal["met_flag"])
	var progress := player.gold + player.bank
	if progress >= target:
		story.set_flag(met_flag, true)
	return {"text": str(story_script.goal["text"]), "progress": progress, "target": target, "met": story.flag(met_flag)}


## 目标与进度的一行字；没有目标返回 ""。
func goal_line() -> String:
	var g := goal()
	if g.is_empty():
		return ""
	return "目標%s：%s（目前 %d）" % ["已達成" if g["met"] else "", g["text"], g["progress"]]


func take_notice() -> String:
	var text := notice
	notice = ""
	return text


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
	w.story_script = EventScript.load_shipped()
	w.port_id = int(d["port_id"])
	w.day = int(d["day"])
	return w


## v 是不小于 lo 的整数值（JSON 读回来的整数是 float，所以两种类型都收）。
static func is_whole(v: Variant, lo: float = -MAX_WHOLE) -> bool:
	return typeof(v) in [TYPE_INT, TYPE_FLOAT] and v == floorf(v) and v >= lo and v <= MAX_WHOLE
