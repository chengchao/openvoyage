## 全局配置与资产清单加载（纯逻辑 RefCounted，不依赖场景树，headless 可测）。
##
## 数据层「薄加载」：游戏运行时读占位包（CI）或转换产物（本地）的清单。
## M0 仅需占位包清单；后续里程碑扩充字段（图块集、头像图集、港口表…）。
class_name GameConfig
extends RefCounted

const VERSION := "0.0.1-m0"

## 读取 JSON 资产清单。文件缺失或格式错误时返回空字典（调用方据此回退）。
static func load_manifest(path := "res://data/placeholder/manifest.json") -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed
