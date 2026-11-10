## 游戏内选单（表现层）：港里按 ESC 弹出的模态层。左分类页签 / 中项目列表 / 右详情，顶栏资金，底栏操作提示。
## 内容全部来自 GameMenu 表与 PortSession.menu_detail；本层只管光标与渲染，选定有 action 的项发 action_requested。
class_name GameMenuPanel
extends CanvasLayer

signal close_requested
signal action_requested(action: StringName)

const BG := Color(0.07, 0.1, 0.2, 0.92)
const BORDER := Color(0.78, 0.64, 0.32)
const HIGHLIGHT := Color(0.78, 0.64, 0.32, 0.3)
const TEXT := Color(0.92, 0.92, 0.88)
const TEXT_SELECTED := Color(1, 0.9, 0.55)
const TEXT_CLOSED := Color(0.5, 0.54, 0.62)  # 尚未開放的项
const ROW_H := 26
const HINT := "←→ 分類　↑↓ 選擇　確定　ESC 返回"

var _session: PortSession
var _cat := 0
var _item := 0
var _tabs: Array[Label] = []
var _rows: Array[Label] = []
var _item_list: VBoxContainer
var _heading: Label
var _detail: Label


## 注入会话（加入场景树前调用）。
func setup(session: PortSession) -> void:
	_session = session


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # 模态：挡住下层港口的点击
	add_child(dim)

	var top := _box(Rect2(16, 12, 608, 32))
	top.add_child(_text("選單", Vector2(12, 4), TEXT_SELECTED))
	var funds := _text(_session.balance_line(), Vector2(0, 4), TEXT)
	funds.size = Vector2(596, 24)
	funds.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(funds)

	var tab_list := _list(_box(Rect2(16, 52, 112, 300)))
	for i in GameMenu.categories().size():
		var tab := _row(GameMenu.categories()[i].get("label", ""), _on_tab_input.bind(i))
		tab_list.add_child(tab)
		_tabs.append(tab)

	_item_list = _list(_box(Rect2(136, 52, 216, 300)))

	var pane := _box(Rect2(360, 52, 264, 300))
	_heading = _text("", Vector2(12, 8), TEXT_SELECTED)
	pane.add_child(_heading)
	var rule := ColorRect.new()
	rule.color = BORDER
	rule.position = Vector2(12, 36)
	rule.size = Vector2(240, 1)
	pane.add_child(rule)
	_detail = _text("", Vector2(12, 44), TEXT)
	_detail.size = Vector2(240, 244)
	_detail.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY  # 中文无空格，按字折行
	pane.add_child(_detail)

	_box(Rect2(16, 360, 608, 28)).add_child(_text(HINT, Vector2(12, 2), TEXT_CLOSED))

	_rebuild_items()


func category_index() -> int:
	return _cat


func item_index() -> int:
	return _item


func category_labels() -> PackedStringArray:
	return _labels_of(GameMenu.categories())


func item_labels() -> PackedStringArray:
	return _labels_of(GameMenu.items(_cat))


func detail_text() -> String:
	return _session.menu_detail(_cat, _item)


## 换分类（回绕），项光标回到首项。
func move_category(delta: int) -> void:
	_cat = posmod(_cat + delta, maxi(1, GameMenu.categories().size()))
	_item = 0
	_rebuild_items()


## 移动项光标（回绕）。
func move_item(delta: int) -> void:
	_item = posmod(_item + delta, maxi(1, GameMenu.items(_cat).size()))
	_refresh()


## 选定当前项：有 action 才发 action_requested；尚未開放的项详情栏已写明，不另作反馈。
## 发完重画：存/读档的结果是写进详情栏的。
func activate() -> void:
	var action := GameMenu.action_of(_cat, _item)
	if action != &"":
		action_requested.emit(action)
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		move_category(-1)
	elif event.is_action_pressed("ui_right"):
		move_category(1)
	elif event.is_action_pressed("ui_up"):
		move_item(-1)
	elif event.is_action_pressed("ui_down"):
		move_item(1)
	elif event.is_action_pressed("ui_accept"):
		activate()
	elif event.is_action_pressed("ui_cancel"):
		close_requested.emit()
	else:
		return
	get_viewport().set_input_as_handled()


func _on_tab_input(event: InputEvent, index: int) -> void:
	if _is_click(event):
		move_category(index - _cat)


func _on_item_input(event: InputEvent, index: int) -> void:
	if _is_click(event):
		move_item(index - _item)
		activate()


func _is_click(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	return mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT


func _rebuild_items() -> void:
	for row in _rows:
		row.queue_free()
	_rows.clear()
	var labels := item_labels()
	for i in labels.size():
		var row := _row(labels[i], _on_item_input.bind(i))
		_item_list.add_child(row)
		_rows.append(row)
	_refresh()


func _refresh() -> void:
	for i in _tabs.size():
		_paint(_tabs[i], i == _cat, false)
	for i in _rows.size():
		_paint(_rows[i], i == _item, GameMenu.action_of(_cat, i) == &"")
	_heading.text = item_labels()[_item] if _item < _rows.size() else ""
	_detail.text = detail_text()


func _paint(row: Label, selected: bool, closed: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = HIGHLIGHT if selected else Color.TRANSPARENT
	style.set_corner_radius_all(2)
	style.content_margin_left = 8
	row.add_theme_stylebox_override("normal", style)
	row.add_theme_color_override("font_color",
		TEXT_SELECTED if selected else TEXT_CLOSED if closed else TEXT)


func _labels_of(rows: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for r: Dictionary in rows:
		out.append(r.get("label", ""))
	return out


func _box(rect: Rect2) -> Panel:
	var style := StyleBoxFlat.new()
	style.bg_color = BG
	style.border_color = BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	var box := Panel.new()
	box.position = rect.position
	box.size = rect.size
	box.add_theme_stylebox_override("panel", style)
	add_child(box)
	return box


func _list(box: Panel) -> VBoxContainer:
	var list := VBoxContainer.new()
	list.position = Vector2(6, 8)
	list.size = Vector2(box.size.x - 12, 0)
	list.add_theme_constant_override("separation", 2)
	box.add_child(list)
	return list


func _text(text: String, at: Vector2, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_color_override("font_color", color)
	return label


func _row(text: String, on_input: Callable) -> Label:
	var row := Label.new()
	row.text = text
	row.custom_minimum_size = Vector2(0, ROW_H)
	row.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(on_input)
	return row
