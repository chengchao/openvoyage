## 金额输入模态（表现层）：覆盖在设施面板之上，让玩家选定一个 0..max 的金额。
## 操作：↑/↓ ±小步(100)，→/← ±大步(1000)，确定(ui_accept)发 confirmed(amount)，取消(ui_cancel)发 cancelled。
## 银行存/取、捐献、补给采购等需要选额的设施功能共用此组件。
class_name AmountEntry
extends CanvasLayer

signal confirmed(amount: int)
signal cancelled

const STEP_SMALL := 100
const STEP_BIG := 1000

var _amount: int = 0
var _max: int = 0
var _prompt: String = ""
var _value_label: Label


## 注入提示语与上限（加入场景树前调用）。initial 会被夹到 [0, max]。
func setup(prompt: String, max_amount: int, initial := 0) -> void:
	_prompt = prompt
	_max = maxi(0, max_amount)
	_amount = clampi(initial, 0, _max)


func _ready() -> void:
	layer = 20  # 盖在设施面板/对话框之上

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # 模态：输入金额时挡住下层设施菜单的点击
	add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(180, 92)
	panel.position = ((get_viewport().get_visible_rect().size - panel.size) * 0.5).floor()
	add_child(panel)

	var prompt := Label.new()
	prompt.text = _prompt
	prompt.position = Vector2(10, 8)
	panel.add_child(prompt)

	_value_label = Label.new()
	_value_label.position = Vector2(10, 34)
	panel.add_child(_value_label)

	var hint := Label.new()
	hint.text = "↑↓±100 ←→±1000 确定/取消"
	hint.position = Vector2(10, 66)
	panel.add_child(hint)

	_refresh()


func amount() -> int:
	return _amount


## 增减金额并夹到 [0, max]。
func adjust(delta: int) -> void:
	_amount = clampi(_amount + delta, 0, _max)
	_refresh()


func confirm() -> void:
	confirmed.emit(_amount)


func cancel() -> void:
	cancelled.emit()


func _refresh() -> void:
	if _value_label != null:
		_value_label.text = "%d / %d" % [_amount, _max]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		adjust(STEP_SMALL)
	elif event.is_action_pressed("ui_down"):
		adjust(-STEP_SMALL)
	elif event.is_action_pressed("ui_right"):
		adjust(STEP_BIG)
	elif event.is_action_pressed("ui_left"):
		adjust(-STEP_BIG)
	elif event.is_action_pressed("ui_accept"):
		confirm()
	elif event.is_action_pressed("ui_cancel"):
		cancel()
	else:
		return
	get_viewport().set_input_as_handled()
