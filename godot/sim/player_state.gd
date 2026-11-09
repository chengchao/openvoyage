## 玩家经济状态（纯逻辑，RefCounted）：现金（手持金幣）与银行存款。
## 跨场景共用的玩家资金原语；设施（银行存取、交易、补给…）经此读写。
## 语义保守：只建模「钱在手上 / 钱在银行」两处与其守恒搬移，不臆造利息/汇率（待后续里程碑校准）。
class_name PlayerState
extends RefCounted

var gold: int = 0  # 现金（手持）
var bank: int = 0  # 银行存款


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
