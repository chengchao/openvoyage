## 事件命令表运行器（纯逻辑 RefCounted，headless 可测）—— 原版主程序事件解释器的复刻。
## 从某入口标签走 events/ 命令表，逐拍产出对话「节拍」供 DialogueDirector 演出。
##
## 节拍词表（DialogueDirector 按此鸭子类型驱动）：
##   {kind:"open"}                          —— window(C0)：开/清窗
##   {kind:"portrait", face:int}            —— portrait(CC/CD)：换说话人头像
##   {kind:"line", index, speaker, body}    —— say(C8)：取台词；已拆说话人、已代入 $ 变量
##   {kind:"wait"}                          —— wait(C7)：等待按键推进
##   {kind:"end"}                           —— end(F2)/越界/无法跟随的跳转：对话块结束
##
## 控制流（引擎验证，见 docs/09、OPCODES.md）在内部处理、不产节拍：
##   branch  AC=if-set / AD=if-clear（按 GameState 旗标决定是否跳转）
##   jump    无条件跳转；label  跳转目标标记
##   end     终止
##   set_flag  自撰剧本用：立/清一个旗标（{flag, value 缺省 true}），让一段剧情只演一次
## set/arith/query/cond/sound/music/raw —— **语义未解**，一律记日志的安全 no-op（不评估、不跳转），
##   以便经验映射旗标/变量含义（do NOT invent）。cond 虽带跳转目标，但条件未解→不跳、取直落分支。
class_name EventInterpreter
extends RefCounted

# 单次 next_beat 内的控制步上限：守卫无 wait 的死循环跳转，避免 headless 挂起。
const _GUARD_STEPS := 100000

var _script: EventScript
var _state: GameState
var _chapter: int
var _steps: Array = []
var _pc: int = -1
var _running := false
var _log: Array = []


func _init(script: EventScript, state: GameState, chapter: int) -> void:
	_script = script
	_state = state
	_chapter = chapter


## 定位入口标签的指令下标。找不到→ false（调用方据此回退到常规菜单）。
func start(label: String) -> bool:
	var idx := _script.label_index(_chapter, label)
	if idx < 0:
		return false
	_steps = _script.chapter_script(_chapter)
	_pc = idx
	_running = true
	return true


func is_running() -> bool:
	return _running


## no-op 操作码日志（含被读到的旗标/变量），供经验映射语义。
func get_log() -> Array:
	return _log


## 取下一个对话节拍；内部消化 branch/jump/label 与 no-op 操作码，直到产出一拍或抵达 end。
func next_beat() -> Dictionary:
	if not has_content():
		return {"kind": "end"}
	var s: Dictionary = _steps[_pc]
	_pc += 1
	match str(s["op"]):
		"window":
			return {"kind": "open"}
		"portrait":
			var face := _state.get_var(int(s["from_var"])) if s.has("from_var") else int(s.get("kao", 0))
			return {"kind": "portrait", "face": face}
		"say":
			return _line_beat(str(s.get("text", "")))
	return {"kind": "wait"}


## 还有节拍可演吗？走完挡在前面的控制流（旗标分支、set_flag…）停在下一拍上，不消耗它；
## 已到 end 返回 false。调用方据此不为一段「旗标让它一句都不演」的剧情开对话。
func has_content() -> bool:
	var guard := 0
	while _running and _pc >= 0 and _pc < _steps.size():
		guard += 1
		if guard > _GUARD_STEPS:
			_log.append("guard: aborted possible infinite loop")
			break
		var s: Dictionary = _steps[_pc]
		if s.has("label"):
			_pc += 1
			continue
		var op := str(s.get("op", ""))
		match op:
			"window", "portrait", "say", "wait":
				return true
			"end":
				break
			"branch", "jump":
				var followed := _follow_branch(s) if op == "branch" else _goto(s)
				if not followed:
					break
			"set_flag":
				_state.set_flag(int(s.get("flag", 0)), bool(s.get("value", true)))
				_pc += 1
			"cond":
				# 条件语义未解：不评估、不跳转，取直落分支（记日志）
				_log.append("cond %s args=%s (no-op, fall through)" % [s.get("code", "?"), s.get("args", [])])
				_pc += 1
			_:
				# set/arith/query/sound/music/raw 等：记日志的安全 no-op
				_log.append("%s %s (no-op)" % [op, _brief(s)])
				_pc += 1
	_running = false
	return false


# branch：按旗标决定是否跳转。返回 false=应终止（无法跟随的跨节跳转）。
func _follow_branch(s: Dictionary) -> bool:
	var want_set := str(s.get("if", "set")) == "set"
	var take := _state.flag(int(s.get("flag", 0))) == want_set
	if not take:
		_pc += 1
		return true
	return _goto(s)


# 跳到 to 标签；unresolved（跨节）或标签缺失→无法跟随，返回 false（终止）。
func _goto(s: Dictionary) -> bool:
	if bool(s.get("unresolved", false)):
		_log.append("jump/branch to %s unresolved (cross-section) → end" % s.get("to", "?"))
		return false
	var idx := _script.label_index(_chapter, str(s.get("to", "")))
	if idx < 0:
		_log.append("jump/branch to missing label %s → end" % s.get("to", "?"))
		return false
	_pc = idx
	return true


func _line_beat(text_id: String) -> Dictionary:
	var raw := _script.text(text_id)
	var parts := EventScript.split_speaker(raw)
	var slash := text_id.rfind("/")
	var index := text_id.substr(slash + 1).to_int() if slash >= 0 else -1
	return {
		"kind": "line",
		"index": index,
		"speaker": _state.substitute(parts["speaker"]),
		"body": _state.substitute(parts["body"]),
	}


func _brief(s: Dictionary) -> String:
	if s.has("code"):
		return str(s["code"])
	if s.has("fn"):
		return str(s["fn"])
	if s.has("id"):
		return "id=" + str(s["id"])
	return ""
