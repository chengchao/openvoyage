## 港口 HUD（表现层）：顶上一条 = 港名、日期、现金、船舱、目标；底下一行操作提示，只在走路时显示。
## 不自己盯数值：DoorFlow 每次让界面跟上 session 时调 refresh()。
class_name PortHud
extends CanvasLayer

const HINT := "方向鍵移動　朝門前進可進入設施　Enter 確定　Esc 選單/取消"
const BAR_H := 22
const FONT_SIZE := 14

var _session: PortSession
var _bar := ColorRect.new()
var _status := Label.new()
var _hint := Label.new()


func setup(session: PortSession) -> void:
	_session = session


func _ready() -> void:
	layer = 1
	_bar.color = Color(0, 0, 0, 0.55)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_bar.offset_bottom = BAR_H
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)

	_status.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", FONT_SIZE)
	_bar.add_child(_status)

	_hint.text = HINT
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_bottom = -6
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", FONT_SIZE)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 4)
	add_child(_hint)
	refresh()


func refresh() -> void:
	var p := _session.player_state
	var parts := PackedStringArray([Market.port_name(_session.port_id), "第 %d 日" % _session.world.day,
		"現金 %d" % p.gold, "船艙 %d/%d" % [p.cargo_used(), p.hold]])
	var goal := _session.world.goal()
	if not goal.is_empty():
		parts.append("目標已達成" if goal["met"] else "目標　資產 %d/%d" % [goal["progress"], goal["target"]])
	_status.text = "　".join(parts)
	_hint.visible = _session.mode == PortSession.Mode.WALKING
	_bar.visible = _session.mode != PortSession.Mode.GAME_MENU  # 选单占满全屏、自带资金栏，叠着会互相遮挡


func status_text() -> String:
	return _status.text


func status_visible() -> bool:
	return _bar.visible


func hint_visible() -> bool:
	return _hint.visible
