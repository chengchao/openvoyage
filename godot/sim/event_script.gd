## 事件脚本程序（纯逻辑数据 + 查找，headless 可测）。
## 数据 = 带标签的命令表脚本 + 触发入口表（events 字典）与台词列表（say 的 id 'snrN/k' 即行下标）。
## 控制流/语义在 EventInterpreter；此处只做章节脚本取用、标签→下标、入口查找、台词解析。
class_name EventScript
extends RefCounted

const NAME_OPEN := "〔"
const NAME_CLOSE := "〕"

var scenario: int = 0
var chapters: Array = []
var words: PackedStringArray = PackedStringArray()
var _label_maps: Array = []   # 每章 {label:String -> index:int}，懒构建


func _init(events: Dictionary = {}, words_: PackedStringArray = PackedStringArray()) -> void:
	scenario = int(events.get("scenario", 0))
	chapters = events.get("chapters", [])
	words = words_
	_label_maps.resize(chapters.size())


func chapter_count() -> int:
	return chapters.size()


func chapter_script(ch: int) -> Array:
	if ch < 0 or ch >= chapters.size():
		return []
	return chapters[ch].get("script", [])


## 章节内某标签的指令下标；无此标签/越界→ -1。
func label_index(ch: int, lbl: String) -> int:
	if ch < 0 or ch >= chapters.size():
		return -1
	if _label_maps[ch] == null:
		var m: Dictionary = {}
		var script: Array = chapters[ch].get("script", [])
		for i in range(script.size()):
			if script[i].has("label"):
				m[str(script[i]["label"])] = i
		_label_maps[ch] = m
	return int(_label_maps[ch].get(lbl, -1))


# 0xA3 位置无关通配的港号阈值：公共轨(SNR0)=0x82，主角轨(SNRn,n≥1)=0x64（docs/09 §9.A.3/§9.A.4）。
func _wildcard_threshold() -> int:
	return 0x82 if scenario == 0 else 0x64


## 撞门派发：按 (章, 港, 设施码) 在事件入口表里找入口标签——**逐字节复刻引擎搜索**
## （docs/09 §9.A.3/§9.A.5，已对 SNR1 章0 实证）：按表B 出现顺序线性扫描，
##   高字节 hi 命中 = (hi==港) 或 (港<阈值 且 hi==0xA3 位置无关通配)；
##   低字节 lo 命中 = (lo==设施码) 或 (lo==0xFF 该港兜底)；
##   首个命中即返回（专属项排在 xxFF 兜底之前）。设施码即 ZA_DAT 槽位号 0..0x0B。
## 未命中→空串（调用方据此回退常规设施菜单）。
func find_entry(ch: int, port: int, facility_code: int) -> String:
	if ch < 0 or ch >= chapters.size():
		return ""
	var threshold := _wildcard_threshold()
	for e in chapters[ch].get("entries", []):
		var eid := str(e.get("trigger_id", "")).hex_to_int()
		var hi := (eid >> 8) & 0xff
		var lo := eid & 0xff
		var hi_ok := hi == port or (port < threshold and hi == 0xA3)
		var lo_ok := lo == facility_code or lo == 0xFF
		if hi_ok and lo_ok:
			return str(e.get("label", ""))
	return ""


## 台词 id（'snrN/k'）→ 原文（含 〔说话人〕\n 前缀与 $ 变量）；越界/非法→空串。
func text(id: String) -> String:
	var slash := id.rfind("/")
	if slash < 0:
		return ""
	var k := id.substr(slash + 1).to_int()
	return words[k] if k >= 0 and k < words.size() else ""


## 拆出首行 〔说话人〕；无括号则 speaker 为空、body 即原文。
static func split_speaker(s: String) -> Dictionary:
	if s.begins_with(NAME_OPEN):
		var close := s.find(NAME_CLOSE)
		if close >= 0:
			var rest := s.substr(close + NAME_CLOSE.length())
			if rest.begins_with("\n"):
				rest = rest.substr(1)
			return {"speaker": s.substr(NAME_OPEN.length(), close - NAME_OPEN.length()), "body": rest}
	return {"speaker": "", "body": s}

