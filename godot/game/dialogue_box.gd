## 对话窗（表现层，可复用）：底部信息框 = 头像 + 名字栏 + 逐字显示正文 + 按键推进/关闭。
## 吃 MesText.parse 出的 token；ASCII 用系统字体绘制，双字节字形经 FontCodec→字模图集绘制，
## 未映射字形画占位框（码表破解后自动变正确字形，UI 不改）。剧本对话与设施对话共用。
class_name DialogueBox
extends CanvasLayer

signal closed

const CELL := 16
const REVEAL_PER_SEC := 30.0
const BOX_H := 88
const FONT_ATLAS := "images/font/font1.png"

var _speaker: Array = []
var _body: Array = []
var _portrait: Texture2D
var _atlas: Texture2D
var _reveal := 0.0
var _text: Control


## 把可读 Unicode 串拆成逐字 "text" token（每字一格，系统字体绘制）。
## 用于现成可读文本（设施名等占位台词）；真 MES 文本用 glyph token 经字模图集渲染。
static func text_tokens(s: String) -> Array:
	var out: Array = []
	for ch in s:
		out.append({"type": "text", "ch": ch})
	return out


func setup(speaker: Array, body: Array, portrait: Texture2D = null, converted_dir := "") -> void:
	_speaker = speaker
	_body = body
	_portrait = portrait
	if converted_dir != "":
		_atlas = _load_texture(converted_dir.path_join(FONT_ATLAS))


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.25)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 只压暗，不吞下层菜单的点击
	add_child(dim)

	var vp := get_viewport().get_visible_rect().size
	var panel := Panel.new()
	panel.position = Vector2(8, vp.y - BOX_H - 8)
	panel.size = Vector2(vp.x - 16, BOX_H)
	add_child(panel)

	if _portrait != null:
		var pr := TextureRect.new()
		pr.texture = _portrait
		pr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pr.position = Vector2(6, 6)
		pr.custom_minimum_size = Vector2(40, BOX_H - 12)
		pr.size = pr.custom_minimum_size
		panel.add_child(pr)

	var tx := 52 if _portrait != null else 8
	_text = Control.new()
	_text.position = Vector2(tx, 6)
	_text.size = Vector2(panel.size.x - tx - 8, BOX_H - 12)
	_text.draw.connect(_draw_text)
	panel.add_child(_text)


func _process(delta: float) -> void:
	if _reveal < _body.size():
		_reveal = min(_body.size(), _reveal + delta * REVEAL_PER_SEC)
		_text.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		if not is_fully_revealed():
			reveal_all()
		else:
			closed.emit()
		get_viewport().set_input_as_handled()


# --- 渲染 ---

func _draw_text() -> void:
	var font := ThemeDB.fallback_font
	var x := 0
	var y := 0
	var cols := int(_text.size.x / CELL)
	# 名字栏（说话人）画在第一行
	if not _speaker.is_empty():
		_draw_run(_speaker, font, Vector2(0, 0), _speaker.size(), Color(1, 0.9, 0.5))
		y = 1
	var shown := int(_reveal)
	var col := 0
	for i in min(shown, _body.size()):
		var tok: Dictionary = _body[i]
		if tok.type == "newline":
			col = 0; y += 1; continue
		_draw_token(tok, font, Vector2(col * CELL, y * CELL), Color(0.95, 0.95, 0.9))
		col += 1
		if col >= cols:
			col = 0; y += 1


func _draw_run(toks: Array, font: Font, origin: Vector2, n: int, color: Color) -> void:
	for i in min(n, toks.size()):
		_draw_token(toks[i], font, origin + Vector2(i * CELL, 0), color)


func _draw_token(tok: Dictionary, font: Font, pos: Vector2, color: Color) -> void:
	match tok.type:
		"ascii", "text":
			_text.draw_string(font, pos + Vector2(2, CELL - 3), str(tok.ch),
				HORIZONTAL_ALIGNMENT_LEFT, -1, CELL - 2, color)
		"var":
			_text.draw_string(font, pos + Vector2(0, CELL - 3), "$",
				HORIZONTAL_ALIGNMENT_LEFT, -1, CELL - 2, color)
		"glyph":
			var g := FontCodec.glyph(tok.code)
			if g.is_empty() or _atlas == null:
				_text.draw_rect(Rect2(pos + Vector2(1, 1), Vector2(CELL - 2, CELL - 2)), color, false)
			else:
				var cell := FontCodec.atlas_cell(0)  # index via g (待破解)
				var src := Rect2(cell.col * CELL, cell.row * CELL, CELL, CELL)
				_text.draw_texture_rect_region(_atlas, Rect2(pos, Vector2(CELL, CELL)), src, color)


# --- 查询/控制（测试用） ---

func reveal_count() -> int:
	return int(_reveal)


func is_fully_revealed() -> bool:
	return _reveal >= _body.size()


func reveal_all() -> void:
	_reveal = _body.size()
	if _text != null:
		_text.queue_redraw()


func _load_texture(path: String) -> Texture2D:
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			return res
	var img := Image.new()
	if img.load(path) == OK:
		return ImageTexture.create_from_image(img)
	return null
