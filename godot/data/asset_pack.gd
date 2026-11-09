## 薄加载层：读资产清单（占位包或转换产物）并按需解码 PNG。
##
## 用 Image.load 直接从磁盘解码 PNG（不依赖 Godot 的导入产物 .ctex），
## 因此对 res:// 占位图与 assets-converted/ 外部转换产物可用同一套路径逻辑。
class_name AssetPack
extends RefCounted

var manifest_path: String = ""
var base_dir: String = ""
var data: Dictionary = {}


static func load_pack(path := "res://data/placeholder/manifest.json") -> AssetPack:
	var pack := AssetPack.new()
	pack.manifest_path = path
	pack.base_dir = path.get_base_dir()
	pack.data = GameConfig.load_manifest(path)
	return pack


func pack_name() -> String:
	return data.get("pack", "")


## 清单中的图片条目数组：每项 {id, kind, file, w, h}。
func items() -> Array:
	return data.get("images", [])


## 解码某条目为 Image；失败返回 null。
func load_image(entry: Dictionary) -> Image:
	var path := base_dir.path_join(str(entry.get("file", "")))
	if path.begins_with("res://"):
		var resource := ResourceLoader.load(path)
		if resource is Texture2D:
			return (resource as Texture2D).get_image()
		if resource is Image:
			return resource as Image
		return null

	var img := Image.new()
	if img.load(path) != OK:
		return null
	return img
