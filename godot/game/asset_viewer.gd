## 资料查看器（调试工具）：列出占位包/转换产物里的图片并预览。纯组件，只发 back_requested。
class_name AssetViewer
extends Control

signal back_requested

var _pack: AssetPack


func _ready() -> void:
	_pack = AssetPack.load_pack()
	var list := %ItemList as ItemList
	for entry in _pack.items():
		list.add_item(str(entry.get("id", "?")))
	list.item_selected.connect(_on_item_selected)
	(%BackButton as Button).pressed.connect(func() -> void: back_requested.emit())
	if _pack.items().size() > 0:
		_show(0)


func _on_item_selected(index: int) -> void:
	_show(index)


func _show(index: int) -> void:
	var entry: Dictionary = _pack.items()[index]
	var img := _pack.load_image(entry)
	if img == null:
		return
	(%Preview as TextureRect).texture = ImageTexture.create_from_image(img)
	(%InfoLabel as Label).text = "%s  (%d×%d)" % [entry.get("id", "?"), int(entry.get("w", 0)), int(entry.get("h", 0))]


## 供冒烟验收：逐项解码图片，返回成功条数（只解码 Image，不创建纹理）。
func load_all_images() -> int:
	var ok := 0
	for entry in _pack.items():
		if _pack.load_image(entry) != null:
			ok += 1
	return ok
