## 单选列表模态（表现层）：列出几行让玩家挑一行（交易所选货、出航选目的地）。
## 操作：↑/↓ 移光标（回绕），确定(ui_accept)或点击一行发 picked(index)，取消(ui_cancel)发 cancelled。
class_name PickList
extends CanvasLayer

signal picked(index: int)
signal cancelled

const ROW_H := 22
const WIDTH := 240
const CURSOR_COLOR := Color(1, 0.9, 0.55)
const NORMAL_COLOR := Color(0.92, 0.92, 0.88)

var _prompt := ""
var _labels := PackedStringArray()
var _selected := 0
var _rows: Array[Label] = []


## 注入提示语与各行文字（加入场景树前调用）。
func setup(prompt: String, labels: PackedStringArray) -> void:
	_prompt = prompt
	_labels = labels


func _ready() -> void:
	layer = 20  # 盖在设施面板/对话框之上

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # 模态：挡住下层设施菜单的点击
	add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(WIDTH, 44 + ROW_H * _labels.size())
	panel.position = ((get_viewport().get_visible_rect().size - panel.size) * 0.5).floor()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.1, 0.2, 0.95)  # 不透明底：否则下层设施菜单的字会透上来
	style.border_color = Color(0.78, 0.64, 0.32)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var prompt := Label.new()
	prompt.text = _prompt
	prompt.position = Vector2(10, 8)
	panel.add_child(prompt)

	for i in _labels.size():
		var row := Label.new()
		row.text = _labels[i]
		row.position = Vector2(10, 36 + ROW_H * i)
		row.size = Vector2(WIDTH - 20, ROW_H)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.gui_input.connect(_on_row_input.bind(i))
		panel.add_child(row)
		_rows.append(row)

	_refresh()


func selected_index() -> int:
	return _selected


## 移动光标（回绕）。
func move(delta: int) -> void:
	_selected = posmod(_selected + delta, maxi(1, _labels.size()))
	_refresh()


func confirm() -> void:
	picked.emit(_selected)


func cancel() -> void:
	cancelled.emit()


func _refresh() -> void:
	for i in _rows.size():
		_rows[i].modulate = CURSOR_COLOR if i == _selected else NORMAL_COLOR


func _on_row_input(event: InputEvent, index: int) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_selected = index
		confirm()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		move(-1)
	elif event.is_action_pressed("ui_down"):
		move(1)
	elif event.is_action_pressed("ui_accept"):
		confirm()
	elif event.is_action_pressed("ui_cancel"):
		cancel()
	else:
		return
	get_viewport().set_input_as_handled()
