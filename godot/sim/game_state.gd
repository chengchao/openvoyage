## 剧情运行时状态（纯逻辑 RefCounted，headless 可测）：
##   - 旗标 flags：branch(AC/AD) 测试的故事进度位（语义未解，仅作为开关被读写）
##   - 变量 vars：portrait from_var(CD)、query(DC/D0) 写入的脚本变量（50/51=说话人头像）
##   - 名字 names：$n 主角名 / $s 动态名 等占位符代入源
##   - 当前剧本号 scenario / 章节 chapter
##
## 旗标与变量的**具体含义仍在逆向**（见 docs/09、HANDOFF），故本类不内置任何旗标语义——
## 只提供存取；含义由运行时经验映射（no-op 操作码会被 EventInterpreter 记日志以辅助映射）。
class_name GameState
extends RefCounted

var scenario: int = -1
var chapter: int = 0
var _flags: Dictionary = {}   # idx:int -> bool
var _vars: Dictionary = {}    # idx:int -> int
var _names: Dictionary = {}   # key:String("n"/"s"/…) -> String


func _init(scenario_: int = -1, chapter_: int = 0) -> void:
	scenario = scenario_
	chapter = chapter_


func flag(idx: int) -> bool:
	return bool(_flags.get(idx, false))


func set_flag(idx: int, value: bool) -> void:
	_flags[idx] = value


func get_var(idx: int) -> int:
	return int(_vars.get(idx, 0))


func set_var(idx: int, value: int) -> void:
	_vars[idx] = value


func set_name(key: String, value: String) -> void:
	_names[key] = value


## 代入 $n/$s 等名字占位符；未提供的（$r/$d 等查询型，语义未解）原样保留。
func substitute(text: String) -> String:
	var out := text
	for k in _names:
		out = out.replace("$" + str(k), str(_names[k]))
	return out
