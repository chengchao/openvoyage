## 港口玩法状态机（纯逻辑）：在港里走 → 撞门（剧情优先，docs/09 §9.A）→ 设施菜单 ⇄ 金额输入 → 离开；在港里走 ⇄ 游戏内选单。
## 交易所买卖多一步：设施菜单 → 选货 → 金额输入（件数）→ 设施菜单。
## 不依赖场景树：表现层（DoorFlow）按 mode 渲染，agent 可直接驱动。转换只在合法 mode 下生效，否则返回 false/""。
class_name PortSession
extends RefCounted

enum Mode { WALKING, CUTSCENE, FACILITY_MENU, AMOUNT_ENTRY, GAME_MENU, GOODS_PICK }

const STARTING_GOLD := 2000  # 开局现金（占位，待开场剧情/存档校准）
const NOT_OPEN_YET := "（此功能尚未開放）"

var port_id: int
var player_state := PlayerState.new(STARTING_GOLD, 0)
var event_script: EventScript  # 为空 = 无剧情
var game_state: GameState

var mode := Mode.WALKING
var slot := -1                       # 当前（或剧情后将进入的）设施槽号
var interp: EventInterpreter         # CUTSCENE 时有效
var amount_action := &""             # GOODS_PICK / AMOUNT_ENTRY 时有效：&"deposit" / &"withdraw" / &"buy_goods" / &"sell_goods"
var amount_cap := 0
var amount_step := 100               # 金额输入的小步；货物按件数调
var amount_prompt := ""
var pick_prompt := ""                # GOODS_PICK 时有效
var pick_options: Array = []         # GOODS_PICK 时有效：[{key, name, label, price, cap}]，label 带单价
var pending_good: Dictionary = {}    # 买卖的 AMOUNT_ENTRY 时有效：选中的那一行


func _init(p_port_id := 0) -> void:
	port_id = p_port_id


func enter_door(door_slot: int) -> bool:
	if mode != Mode.WALKING:
		return false
	slot = door_slot
	interp = _story_at(door_slot)
	mode = Mode.CUTSCENE if interp != null else Mode.FACILITY_MENU
	return true


func story_finished() -> bool:
	if mode != Mode.CUTSCENE:
		return false
	interp = null
	mode = Mode.FACILITY_MENU
	return true


func leave() -> bool:
	if mode != Mode.FACILITY_MENU:
		return false
	slot = -1
	mode = Mode.WALKING
	return true


## 选菜单项（不含「離開」，那是 leave）。返回店主要说的话；进金额输入时返回 ""。
func choose(index: int) -> String:
	if mode != Mode.FACILITY_MENU:
		return ""
	var ft := FacilityType.of(slot)
	var action := FacilityActions.action_of(ft.key, index) if ft != null else &""
	match action:
		&"deposit", &"withdraw":
			var cap := player_state.gold if action == &"deposit" else player_state.bank
			if cap <= 0:
				return balance_line()
			amount_action = action
			amount_cap = cap
			amount_prompt = "%s多少？" % ("存款" if action == &"deposit" else "提款")
			mode = Mode.AMOUNT_ENTRY
			return ""
		&"buy_goods", &"sell_goods":
			var buying := action == &"buy_goods"
			var rows := _buy_rows() if buying else _sell_rows()
			if rows.is_empty():
				return "您的現金或船艙空位不夠了。" if buying else "您船上沒有這裡收的貨。"
			amount_action = action
			pick_options = rows
			pick_prompt = "要買哪一種？" if buying else "要賣哪一種？"
			mode = Mode.GOODS_PICK
			return ""
		&"show_prices":
			return price_list()
		_:
			return NOT_OPEN_YET


## 选定一种货物，进金额输入（件数，上限 = 该行的 cap）。越界或不在选货时返回 false。
func pick(index: int) -> bool:
	if mode != Mode.GOODS_PICK or index < 0 or index >= pick_options.size():
		return false
	pending_good = pick_options[index]
	amount_cap = pending_good["cap"]
	amount_step = 1
	amount_prompt = "%s%s（單價 %d）幾件？" % [
		"買進" if amount_action == &"buy_goods" else "賣出", pending_good["name"], pending_good["price"]]
	pick_options = []
	pick_prompt = ""
	mode = Mode.AMOUNT_ENTRY
	return true


func cancel_pick() -> bool:
	if mode != Mode.GOODS_PICK:
		return false
	_end_amount()
	return true


## 确认金额：0..amount_cap 内才成交并回到菜单，返回店主的回话；否则 ""、仍在输入。
func confirm_amount(amount: int) -> String:
	if mode != Mode.AMOUNT_ENTRY or amount < 0 or amount > amount_cap:
		return ""
	var line := ""
	match amount_action:
		&"deposit":
			player_state.deposit(amount)
			line = balance_line()
		&"withdraw":
			player_state.withdraw(amount)
			line = balance_line()
		&"buy_goods":
			if player_state.buy(pending_good["key"], amount, pending_good["price"]):
				line = "買進%s%d件，付出%d。\n" % [pending_good["name"], amount, amount * pending_good["price"]]
			line += hold_line()
		&"sell_goods":
			if player_state.sell(pending_good["key"], amount, pending_good["price"]):
				line = "賣出%s%d件，收入%d。\n" % [pending_good["name"], amount, amount * pending_good["price"]]
			line += hold_line()
	_end_amount()
	return line


func cancel_amount() -> bool:
	if mode != Mode.AMOUNT_ENTRY:
		return false
	_end_amount()
	return true


func open_menu() -> bool:
	if mode != Mode.WALKING:
		return false
	mode = Mode.GAME_MENU
	return true


func close_menu() -> bool:
	if mode != Mode.GAME_MENU:
		return false
	mode = Mode.WALKING
	return true


## 选单详情栏的文字：该项说明；主角情報追加所在港与资金，尚未開放的项追加提示。越界返回 ""。
func menu_detail(cat_index: int, item_index: int) -> String:
	var rows := GameMenu.items(cat_index)
	if item_index < 0 or item_index >= rows.size():
		return ""
	var text: String = rows[item_index].get("desc", "")
	match GameMenu.action_of(cat_index, item_index):
		&"status":
			text += "\n港口 %d　%s" % [port_id, balance_line()]
		&"cargo":
			for good: String in player_state.cargo:
				text += "\n%s　%d 件" % [Market.label(good), player_state.cargo[good]]
			text += "\n船艙 %d/%d" % [player_state.cargo_used(), player_state.hold]
		&"":
			text += "\n" + NOT_OPEN_YET
	return text


func balance_line() -> String:
	return "現金 %d　存款 %d" % [player_state.gold, player_state.bank]


func hold_line() -> String:
	return "現金%d　船艙%d/%d" % [player_state.gold, player_state.cargo_used(), player_state.hold]


## 本港行情，一行两种货物。
## ponytail: 店主对话框正文只有 3 行，一港超过 6 种货物会画出框外；到时改成专用行情面板。
func price_list() -> String:
	var cells := PackedStringArray()
	for g: Dictionary in Market.goods(port_id):
		cells.append("%s　買%d　賣%d" % [g["label"], g["buy"], g["sell"]])
	var lines := PackedStringArray()
	for i in range(0, cells.size(), 2):
		lines.append("　　".join(cells.slice(i, i + 2)))
	return "\n".join(lines)


func _buy_rows() -> Array:
	var room := player_state.hold - player_state.cargo_used()
	var rows := []
	for g: Dictionary in Market.goods(port_id):
		@warning_ignore("integer_division")
		var cap := mini(player_state.gold / g["buy"], room)
		if cap > 0:
			rows.append({"key": g["key"], "name": g["label"], "price": g["buy"], "cap": cap,
				"label": "%s　單價 %d" % [g["label"], g["buy"]]})
	return rows


func _sell_rows() -> Array:
	var rows := []
	for g: Dictionary in Market.goods(port_id):
		var held: int = player_state.cargo.get(g["key"], 0)
		if held > 0:
			rows.append({"key": g["key"], "name": g["label"], "price": g["sell"], "cap": held,
				"label": "%s　單價 %d　持有 %d" % [g["label"], g["sell"], held]})
	return rows


func _end_amount() -> void:
	amount_action = &""
	amount_cap = 0
	amount_step = 100
	amount_prompt = ""
	pick_prompt = ""
	pick_options = []
	pending_good = {}
	mode = Mode.FACILITY_MENU


func _story_at(door_slot: int) -> EventInterpreter:
	if event_script == null or game_state == null or game_state.scenario < 0:
		return null
	var label := event_script.find_entry(game_state.chapter, port_id, door_slot)
	if label == "":
		return null
	var it := EventInterpreter.new(event_script, game_state, game_state.chapter)
	return it if it.start(label) else null
