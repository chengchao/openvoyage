## 设施合成场景（表现层）：进入设施后覆盖在港口之上的模态层。
## 占位背景 + 真 GRAPH 店主画 + 标题 + 真 MENU 菜单（光标导航/选定）+ 退出（ESC/确定）。
## 各菜单项的实际功能（交易/存款…）由后续里程碑连 menu_selected 信号接入。
class_name FacilityScene
extends CanvasLayer

signal exit_requested
## 选中某非「離開」菜单项时发出（index = MENU 组内序号，label = 项文本）。
## 各设施功能由后续里程碑连接此信号实现；本场景只负责选择交互。
signal menu_selected(index: int, label: String)

const SHOPKEEPER_PLACEHOLDER := preload("res://data/placeholder/images/shopkeeper_placeholder.png")
const CURSOR_COLOR := Color(1, 1, 0.4)  # 选中项高亮（黄）
const NORMAL_COLOR := Color(1, 1, 1)

var _type: FacilityType
var _converted_dir: String = ""
var _title: Label
var _shopkeeper: TextureRect
var _dialogue: DialogueBox  # 进门寒暄对话框（非空=正在对话）
var _labels: PackedStringArray = PackedStringArray()  # 当前菜单项（含末项「離開」）
var _menu_items: Array[Label] = []  # 菜单项 Label，按序，用于光标高亮
var _selected: int = 0  # 当前光标位置（_labels 下标）


## 注入设施类型 + 转换产物目录（在加入场景树前调用）。
## 店主画 = 自制占位画（程序员美术，不用原版 GRAPH.DAT）。M5 据 _type.key 载入菜单。
func setup(facility_type: FacilityType, converted_dir := "") -> void:
	_type = facility_type
	_converted_dir = converted_dir


func _ready() -> void:
	# 半透明压暗的港口 + 居中设施面板（适配视口尺寸）
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # 模态：挡住下层港口的点击
	add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(240, 180)
	panel.position = ((get_viewport().get_visible_rect().size - panel.size) * 0.5).floor()
	add_child(panel)

	_title = Label.new()
	_title.text = "【%s】" % facility_name()
	_title.position = Vector2(8, 6)
	panel.add_child(_title)

	# 画框（店主画外框），左侧
	var frame := Panel.new()
	frame.position = Vector2(6, 22)
	frame.size = Vector2(140, 116)
	panel.add_child(frame)

	# 画框店主画（136×112 框），左侧
	_shopkeeper = TextureRect.new()
	_shopkeeper.texture = SHOPKEEPER_PLACEHOLDER
	_shopkeeper.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shopkeeper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_shopkeeper.position = Vector2(8, 24)
	_shopkeeper.custom_minimum_size = Vector2(136, 112)
	panel.add_child(_shopkeeper)

	# 真菜单（解码自 MENU.DAT 第 menu_index 组）+ 末项「離開」，右侧。
	# 光标可上下导航并选定；非「離開」项发 menu_selected（功能由后续里程碑接入）。缺产物时仅「離開」。
	_labels = menu_labels()
	var menu := VBoxContainer.new()
	menu.position = Vector2(152, 32)
	for i in _labels.size():
		var item := Label.new()
		item.text = _labels[i]
		item.mouse_filter = Control.MOUSE_FILTER_STOP
		item.gui_input.connect(_on_item_input.bind(i))
		menu.add_child(item)
		_menu_items.append(item)
	panel.add_child(menu)
	_update_cursor()

	var hint := Label.new()
	hint.text = "按 ESC 离开"
	hint.position = Vector2(8, 156)
	panel.add_child(hint)

	_show_greeting()  # 进门：店主寒暄一句（M5）


## 进门寒暄：店主说一句（说话人=设施名+头像=店主画）。真台词来自 MES，待码表接入；
## 当前正文为可读占位（系统字体），对话窗框架与流程已通。按键全显→再按关闭，露出菜单。
func _show_greeting() -> void:
	# 真台词：解码后的 MESSAGE.DAT 店主招呼（缺解码文本时回退占位）。
	var line := TextDb.message(_converted_dir, TextDb.GREETING)
	if line == "":
		line = "（對話待接入）"
	say(line)


## 让店主说一句（说话人=设施名，头像在面板已显示故不重复）。设施功能用它反馈结果。
## 对话存在期间菜单输入被门控（_unhandled_input 早退）；关闭后回到菜单。
func say(line: String) -> void:
	_dialogue = DialogueBox.new()
	_dialogue.layer = 10  # 盖在设施面板之上
	_dialogue.setup(DialogueBox.text_tokens(facility_name()),
		DialogueBox.text_tokens(line), null, _converted_dir)
	_dialogue.closed.connect(_on_dialogue_closed)
	add_child(_dialogue)


func _on_dialogue_closed() -> void:
	if _dialogue != null:
		_dialogue.queue_free()
		_dialogue = null


func has_dialogue() -> bool:
	return _dialogue != null


## ESC 先于对话框处理：设施里按一次就离开，不必先关寒暄。金额输入等子模态接管输入时
## （DoorFlow 关掉本层 unhandled 输入）不抢 ESC。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_processing_unhandled_input():
		get_viewport().set_input_as_handled()
		_request_exit()


func _on_item_input(event: InputEvent, index: int) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_on_dialogue_closed()
	_selected = index
	_update_cursor()
	activate_selected()


func _unhandled_input(event: InputEvent) -> void:
	if _dialogue != null:
		return  # 对话框自行处理输入（推进/关闭）
	if event.is_action_pressed("ui_up"):
		move_selection(-1)
	elif event.is_action_pressed("ui_down"):
		move_selection(1)
	elif event.is_action_pressed("ui_accept"):
		activate_selected()
	else:
		return
	get_viewport().set_input_as_handled()


## 移动光标（delta=±1），在菜单项数内回绕。
func move_selection(delta: int) -> void:
	var n := _labels.size()
	if n == 0:
		return
	_selected = (_selected + delta + n) % n
	_update_cursor()


## 激活当前项：末项「離開」→退出；其余→发 menu_selected（功能后续接入）。
func activate_selected() -> void:
	if _selected < 0 or _selected >= _labels.size():
		return
	var label := _labels[_selected]
	if _selected == _labels.size() - 1:  # 末项恒为「離開」
		_request_exit()
	else:
		menu_selected.emit(_selected, label)


func selected_index() -> int:
	return _selected


func selected_label() -> String:
	if _selected >= 0 and _selected < _labels.size():
		return _labels[_selected]
	return ""


func _update_cursor() -> void:
	for i in _menu_items.size():
		_menu_items[i].modulate = CURSOR_COLOR if i == _selected else NORMAL_COLOR


func _request_exit() -> void:
	exit_requested.emit()


# --- 查询（测试/外部用） ---

func facility_type() -> FacilityType:
	return _type


func facility_name() -> String:
	return _type.name if _type != null else ""


## 本设施的真菜单项（MENU.DAT 第 menu_index 组解码）+ 末项「離開」。
## 缺转换产物 / 未定 menu_index 时只返回 ["離開"]，headless 与冒烟不受影响。
func menu_labels() -> PackedStringArray:
	var out := PackedStringArray()
	if _type != null and _type.menu_index >= 0:
		out = TextDb.menu(_converted_dir, _type.menu_index)
	out.append("離開")
	return out


func title_text() -> String:
	return _title.text if _title != null else ""


func shopkeeper_texture() -> Texture2D:
	return _shopkeeper.texture if _shopkeeper != null else null
