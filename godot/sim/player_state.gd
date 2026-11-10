## 玩家经济状态（纯逻辑，RefCounted）：现金（手持金幣）、银行存款与船舱货物。
## 跨场景共用的玩家资金原语；设施（银行存取、交易、补给…）经此读写。
## 语义保守：钱只在「手上 / 银行」两处守恒搬移，货物按调用方给的单价买卖，不臆造利息/汇率（待后续里程碑校准）。
class_name PlayerState
extends RefCounted

var gold: int = 0  # 现金（手持）
var bank: int = 0  # 银行存款
var cargo: Dictionary = {}  # 货物 key → 件数，不留 0 条目
var hold := 100  # 船舱容量（件；占位，待船只系统接手）


func _init(starting_gold := 0, starting_bank := 0) -> void:
	gold = starting_gold
	bank = starting_bank


## 能否存入 amount（正数且不超过现金）。
func can_deposit(amount: int) -> bool:
	return amount > 0 and amount <= gold


## 存款：现金→存款，成功返回 true；不合法则不变返回 false。
func deposit(amount: int) -> bool:
	if not can_deposit(amount):
		return false
	gold -= amount
	bank += amount
	return true


## 能否取出 amount（正数且不超过存款）。
func can_withdraw(amount: int) -> bool:
	return amount > 0 and amount <= bank


## 取款：存款→现金，成功返回 true；不合法则不变返回 false。
func withdraw(amount: int) -> bool:
	if not can_withdraw(amount):
		return false
	bank -= amount
	gold += amount
	return true


## 船舱已占用的格数（各种货物合计）。
func cargo_used() -> int:
	var used := 0
	for qty: int in cargo.values():
		used += qty
	return used


## 能否以单价 unit_price 买进 qty 件（正数、付得起、装得下）。
func can_buy(qty: int, unit_price: int) -> bool:
	return qty > 0 and unit_price >= 0 and qty * unit_price <= gold and cargo_used() + qty <= hold


## 买进：现金→货物，成功返回 true；不合法则不变返回 false。
func buy(good: String, qty: int, unit_price: int) -> bool:
	if not can_buy(qty, unit_price):
		return false
	gold -= qty * unit_price
	cargo[good] = int(cargo.get(good, 0)) + qty
	return true


## 能否卖出 qty 件 good（正数且不超过持有量）。
func can_sell(good: String, qty: int) -> bool:
	return qty > 0 and qty <= int(cargo.get(good, 0))


## 卖出：货物→现金，成功返回 true；不合法则不变返回 false。卖光的货物从 cargo 里删掉。
func sell(good: String, qty: int, unit_price: int) -> bool:
	if not can_sell(good, qty) or unit_price < 0:
		return false
	gold += qty * unit_price
	cargo[good] -= qty
	if cargo[good] == 0:
		cargo.erase(good)
	return true


func to_dict() -> Dictionary:
	return {"gold": gold, "bank": bank, "hold": hold, "cargo": cargo.duplicate()}


## 不合法（缺字段、负数、非整数、货物超过船舱）返回 null。
static func from_dict(d: Variant) -> PlayerState:
	if typeof(d) != TYPE_DICTIONARY or typeof(d.get("cargo")) != TYPE_DICTIONARY:
		return null
	for k: String in ["gold", "bank", "hold"]:
		if not World.is_whole(d.get(k), 0):
			return null
	var p := PlayerState.new(int(d["gold"]), int(d["bank"]))
	p.hold = int(d["hold"])
	for good: Variant in d["cargo"]:
		if typeof(good) != TYPE_STRING or good == "" or not World.is_whole(d["cargo"][good], 1):
			return null
		p.cargo[good] = int(d["cargo"][good])
	return p if p.cargo_used() <= p.hold else null
