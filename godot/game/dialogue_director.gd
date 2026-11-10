## 对话协调器（表现层）：单一入口，把 EventInterpreter 的节拍泵进可复用的 DialogueBox，
## 逐句演出、按键推进、结束发 finished。任何场景（设施/港口/世界图）实例化它即可放剧情，
## 调用方无需知道 UI 细节——逻辑(解释器)/表现(对话窗)经节拍词表解耦（参 docs/08 §8.5）。
##
## 复用现成 DialogueBox：每个 wait 分隔的「一句」用一个 DialogueBox 显示，其 closed 信号
## （逐字全显后再按键）= 推进到下一句。头像由 portrait 节拍按头像号选自制占位头像。
class_name DialogueDirector
extends Node

signal finished

const PORTRAIT_FMT := "res://data/placeholder/images/portrait_%02d.png"
const PORTRAIT_COUNT := 6

# 任何暴露 next_beat()->{kind,…} 的运行器（当前为 EventInterpreter 命令表运行器；鸭子类型）。
# 节拍词表统一（open/portrait/line/wait/end），故协调器与具体运行器解耦。
var _interp
var _box: DialogueBox
var _pending: Dictionary = {}
var _face: int = -1
var _active := false


## 直接驱动一个已 start 的运行器（EventInterpreter，调用方先定位入口）。
## 返回 true=已开始演出（至少一句）；false=立即结束（无可演内容）。
func play(interp) -> bool:
	_interp = interp
	_face = -1
	_active = true
	return _pump()


func is_active() -> bool:
	return _active


## 当前正在显示的一句 {face, speaker, body}（测试/外部查询用）。
func current_line() -> Dictionary:
	return _pending


## 推进到下一句（等价于玩家按键越过当前句）；供测试/程序化驱动。
func advance() -> void:
	if _active:
		_on_box_closed()


# 读节拍直到攒够一句（遇 wait 显示并返回 true），或抵达 end（收尾返回 false）。
func _pump() -> bool:
	var speaker := ""
	var body := ""
	var have_line := false
	while true:
		var b: Dictionary = _interp.next_beat()
		match b.get("kind", "end"):
			"portrait":
				_face = int(b["face"])
			"line":
				speaker = b["speaker"]
				body = b["body"]
				have_line = true
			"wait":
				if have_line:
					_pending = {"face": _face, "speaker": speaker, "body": body}
					_show()
					return true
			"open":
				pass  # 清窗：下一句的开始，无需特别处理
			_:  # end
				_finish()
				return false
	return false  # 不可达（while true 内总会 return）；满足静态分析


func _show() -> void:
	if _box != null and is_instance_valid(_box):
		_box.queue_free()
	_box = DialogueBox.new()
	_box.layer = 20  # 盖在设施面板/HUD 之上
	_box.setup(
		DialogueBox.text_tokens(_pending["speaker"]),
		DialogueBox.text_tokens(_pending["body"]),
		_portrait(_pending["face"]),
	)
	_box.closed.connect(_on_box_closed)
	add_child(_box)


func _on_box_closed() -> void:
	_pump()


func _finish() -> void:
	_active = false
	if _box != null and is_instance_valid(_box):
		_box.queue_free()
		_box = null
	finished.emit()


## 头像号 → 占位头像（ponytail: 6 张占位轮换，正式头像集到位后按号映射）；无头像 → null。
func _portrait(face: int) -> Texture2D:
	return load(PORTRAIT_FMT % (face % PORTRAIT_COUNT)) if face >= 0 else null
