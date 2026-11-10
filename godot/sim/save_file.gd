## 存档文件（纯逻辑，RefCounted）：World ⇄ JSON。格式 {"version": 1, "world": World.to_dict()}。
class_name SaveFile
extends RefCounted

const DEFAULT_PATH := "user://save.json"
const VERSION := 1


static func exists(path := DEFAULT_PATH) -> bool:
	return FileAccess.file_exists(path)


static func save(world: World, path := DEFAULT_PATH) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	# 先写临时文件再改名：写到一半崩溃或磁盘满，原有存档还在。
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"version": VERSION, "world": world.to_dict()}))
	var written := f.get_error() == OK
	f.close()
	return written and DirAccess.rename_absolute(tmp, path) == OK


## 没有文件、不是本版本的存档、或内容不合法都返回 null。
static func load(path := DEFAULT_PATH) -> World:
	if not exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return null
	var version: Variant = json.data.get("version")
	if not World.is_whole(version) or int(version) != VERSION:
		return null
	return World.from_dict(json.data.get("world"))
