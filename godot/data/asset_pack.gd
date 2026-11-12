## 占位资产包（资料检视器用）：读清单，按条目取图。
class_name AssetPack
extends RefCounted

var base_dir: String = ""
var data: Dictionary = {}


## 清单缺失或格式错误时 data 为空（没有条目）。
static func load_pack(path := "res://data/placeholder/manifest.json") -> AssetPack:
	var pack := AssetPack.new()
	pack.base_dir = path.get_base_dir()
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			pack.data = parsed
	return pack


func pack_name() -> String:
	return data.get("pack", "")


## 清单中的图片条目数组：每项 {id, kind, file, w, h}。
func items() -> Array:
	return data.get("images", [])


## 取某条目的图片；失败返回 null。
func load_image(entry: Dictionary) -> Image:
	var texture := load(base_dir.path_join(str(entry.get("file", "")))) as Texture2D
	return texture.get_image() if texture != null else null
