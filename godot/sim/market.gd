## 港口表与行情（纯逻辑，RefCounted）：真相源 res://data/goods.json（货物）+ res://data/ports.json（各港名称、场景、价格、航线）。
## 买进价 = 该港列出的单价；卖出价 = 其九折（去尾）。没列价的货物在该港不交易。
class_name Market
extends RefCounted

const GOODS_PATH := "res://data/goods.json"
const PORTS_PATH := "res://data/ports.json"

static var _goods: Array = []
static var _ports: Array = []


static func _load() -> void:
	if _goods.is_empty():
		_goods = _read(GOODS_PATH).get("goods", [])
		_ports = _read(PORTS_PATH).get("ports", [])


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func _port(port_id: int) -> Dictionary:
	_load()
	for p: Dictionary in _ports:
		if int(p.get("id", -1)) == port_id:
			return p
	return {}


## 该港交易的货物，按货物表顺序：[{key, label, buy, sell}]；未知港返回 []。
static func goods(port_id: int) -> Array:
	var prices: Dictionary = _port(port_id).get("prices", {})
	var out := []
	for g: Dictionary in _goods:
		if prices.has(g["key"]):
			var buy := int(prices[g["key"]])
			@warning_ignore("integer_division")
			out.append({"key": g["key"], "label": g["label"], "buy": buy, "sell": buy * 9 / 10})
	return out


## 货物显示名；未知返回 ""。
static func label(good: String) -> String:
	_load()
	for g: Dictionary in _goods:
		if g["key"] == good:
			return g["label"]
	return ""


## 未知港返回 ""。
static func port_name(port_id: int) -> String:
	return _port(port_id).get("name", "")


## 该港的港口场景路径；未知港返回 ""。
static func port_scene(port_id: int) -> String:
	return _port(port_id).get("scene", "")


## 从该港可直达的港：[{to, name, days}]；未知港返回 []。
static func routes(port_id: int) -> Array:
	var out := []
	for r: Dictionary in _port(port_id).get("routes", []):
		out.append({"to": int(r["to"]), "name": port_name(int(r["to"])), "days": int(r["days"])})
	return out


## 仅供测试：清空静态缓存。
static func _reset() -> void:
	_goods = []
	_ports = []
