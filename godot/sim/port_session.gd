## 港口玩法状态机（纯逻辑）：在港里走 → 撞门（剧情优先，docs/09 §9.A）→ 设施菜单 ⇄ 金额输入 → 离开；在港里走 ⇄ 游戏内选单。
## 抵港剧情（开场）：在港里走 → 剧情 → 回到在港里走。剧情演完去哪只看 slot：有门进设施，没门回去走路。
## 交易所买卖多一步：设施菜单 → 单选（选货）→ 金额输入（件数）→ 设施菜单。
## 出航：港务局「啟航出海」或走进出航区 → 单选（选目的地）→ SAILED。world 当场改到目的港，
## 本会话到此为止；表现层见到 SAILED 就换进 world 所在港的场景，那边另建会话。
## 不依赖场景树：表现层（DoorFlow）按 mode 渲染，agent 可直接驱动。转换只在合法 mode 下生效，否则返回 false/""。
## 玩家与剧情状态不在这里：都在 world 里，会话只是在它上面玩；换场景 = 换会话、不换 world。
class_name PortSession
extends RefCounted

enum Mode { WALKING, CUTSCENE, FACILITY_MENU, AMOUNT_ENTRY, GAME_MENU, PICK, SAILED }

const NOT_OPEN_YET := "（此功能尚未開放）"
const ARRIVAL := 0x10  # 抵港事件键的低字节。设施槽只到 0x0B，撞不上门

var world: World
var port_id: int:
	get: return world.port_id
	set(v): world.port_id = v
var player_state: PlayerState:
	get: return world.player
	set(v): world.player = v
var game_state: GameState:
	get: return world.story
	set(v): world.story = v
var event_script: EventScript:  # 为空 = 无剧情
	get: return world.story_script
	set(v): world.story_script = v
var save_path := SaveFile.DEFAULT_PATH  # 测试换成临时路径

var mode := Mode.WALKING
var slot := -1                       # 当前（或剧情后将进入的）设施槽号；-1 = 不在设施里
var interp: EventInterpreter         # CUTSCENE 时有效
var pending_action := &""            # PICK / AMOUNT_ENTRY 时有效：这一步在办的事 &"deposit" / &"withdraw" / &"buy_goods" / &"sell_goods" / &"set_sail"
var amount_cap := 0
var amount_step := 100               # 金额输入的小步；货物按件数调
var amount_prompt := ""
var pick_prompt := ""                # PICK 时有效
var pick_options: Array = []         # PICK 时有效，每行都有 label；货物行 {key, name, price, cap}，航线行 {to, name, days}
var pending_good: Dictionary = {}    # 买卖的 AMOUNT_ENTRY 时有效：选中的那一行
var _menu_notes := {}                # GAME_MENU 时有效：选单 action → 这次开选单以来的存/读档结果
var _armed := &""                    # GAME_MENU 时有效：按过一下、等第二下确认的选单 action


## 不给 world 就自带一局新的（不碰 World.current）。
func _init(p_world: World = null) -> void:
	world = p_world if p_world != null else World.new()


func enter_door(door_slot: int) -> bool:
	if mode != Mode.WALKING:
		return false
	slot = door_slot
	interp = _story_at(door_slot)
	mode = Mode.CUTSCENE if interp != null else Mode.FACILITY_MENU
	return true


## 进港时调一次：本港登记了还没演过的抵港剧情就演，返回 true。
func arrive() -> bool:
	if mode != Mode.WALKING:
		return false
	interp = _story_at(ARRIVAL)
	if interp == null:
		return false
	mode = Mode.CUTSCENE
	return true


func story_finished() -> bool:
	if mode != Mode.CUTSCENE:
		return false
	interp = null
	mode = Mode.FACILITY_MENU if slot >= 0 else Mode.WALKING
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
			pending_action = action
			amount_cap = cap
			amount_prompt = "%s多少？" % ("存款" if action == &"deposit" else "提款")
			mode = Mode.AMOUNT_ENTRY
			return ""
		&"buy_goods", &"sell_goods":
			var buying := action == &"buy_goods"
			var rows := _buy_rows() if buying else _sell_rows()
			if rows.is_empty():
				return "您的現金或船艙空位不夠了。" if buying else "您船上沒有這裡收的貨。"
			pending_action = action
			pick_options = rows
			pick_prompt = "要買哪一種？" if buying else "要賣哪一種？"
			mode = Mode.PICK
			return ""
		&"set_sail":
			return "" if _open_route_pick() else "眼下沒有從這裡出發的航線。"
		&"show_prices":
			return price_list()
		_:
			return NOT_OPEN_YET


## 走进出航区：从 WALKING 直接问去哪。没有航线或不在走路时返回 false。
func open_departure() -> bool:
	return mode == Mode.WALKING and _open_route_pick()


## 选定一行。货物 → 进金额输入（件数，上限 = 该行的 cap）；目的地 → 启航。越界或不在单选时返回 false。
func pick(index: int) -> bool:
	if mode != Mode.PICK or index < 0 or index >= pick_options.size():
		return false
	if pending_action == &"set_sail":
		_sail(pick_options[index])
		return true
	pending_good = pick_options[index]
	amount_cap = pending_good["cap"]
	amount_step = 1
	amount_prompt = "%s%s（單價 %d）幾件？" % [
		"買進" if pending_action == &"buy_goods" else "賣出", pending_good["name"], pending_good["price"]]
	pick_options = []
	pick_prompt = ""
	mode = Mode.AMOUNT_ENTRY
	return true


func cancel_pick() -> bool:
	if mode != Mode.PICK:
		return false
	_end_step()
	return true


## 确认金额：0..amount_cap 内才成交并回到菜单，返回店主的回话；否则 ""、仍在输入。
func confirm_amount(amount: int) -> String:
	if mode != Mode.AMOUNT_ENTRY or amount < 0 or amount > amount_cap:
		return ""
	var line := ""
	match pending_action:
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
	_end_step()
	return line


func cancel_amount() -> bool:
	if mode != Mode.AMOUNT_ENTRY:
		return false
	_end_step()
	return true


func open_menu() -> bool:
	if mode != Mode.WALKING:
		return false
	mode = Mode.GAME_MENU
	return true


func close_menu() -> bool:
	if mode != Mode.GAME_MENU:
		return false
	_menu_notes.clear()
	_armed = &""
	mode = Mode.WALKING
	return true


## 会丢掉没存进度的选单项（讀取進度/回到標題/結束遊戲）：同一项连按两下才算数，第一下只在详情栏提示。
func confirm(action: StringName) -> bool:
	if mode != Mode.GAME_MENU:
		return false
	var ok := _armed == action
	_armed = &"" if ok else action
	return ok


## 光标移开：作废等确认的那一下。
func disarm() -> void:
	_armed = &""


## 把 world 写进 save_path，结果显示在「儲存進度」的详情栏。只在选单里有效。
func save_game() -> bool:
	if mode != Mode.GAME_MENU:
		return false
	var ok := SaveFile.save(world, save_path)
	_menu_notes[&"save"] = "進度已儲存。" if ok else "存檔寫入失敗，進度沒有儲存。"
	return ok


## 读出 save_path 里的 world；没有存档或读不了返回 null，原因显示在「讀取進度」的详情栏。
## 只读不换：把它设为当前世界并进入其港口场景是表现层的事。
func load_game() -> World:
	if mode != Mode.GAME_MENU:
		return null
	var loaded := SaveFile.load(save_path)
	if loaded == null:
		_menu_notes[&"load"] = "存檔已損毀，無法讀取。" if SaveFile.exists(save_path) else "還沒有存檔。"
	return loaded


## 选单详情栏的文字：该项说明；主角情報追加目标与进度、所在港、日期与资金，存/读档追加结果，尚未開放的项追加提示。越界返回 ""。
func menu_detail(cat_index: int, item_index: int) -> String:
	var rows := GameMenu.items(cat_index)
	if item_index < 0 or item_index >= rows.size():
		return ""
	var text: String = rows[item_index].get("desc", "")
	var action := GameMenu.action_of(cat_index, item_index)
	match action:
		&"status":
			if world.goal_line() != "":
				text += "\n" + world.goal_line()
			text += "\n%s　第 %d 日　%s" % [Market.port_name(port_id), world.day, balance_line()]
		&"cargo":
			for good: String in player_state.cargo:
				text += "\n%s　%d 件" % [Market.label(good), player_state.cargo[good]]
			text += "\n船艙 %d/%d" % [player_state.cargo_used(), player_state.hold]
		&"":
			text += "\n" + NOT_OPEN_YET
	if _menu_notes.has(action):
		text += "\n" + _menu_notes[action]
	if _armed != &"" and _armed == action:
		text += "\n再按一次確定。"
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


func _open_route_pick() -> bool:
	var rows := Market.routes(port_id)
	if rows.is_empty():
		return false
	for r: Dictionary in rows:
		r["label"] = "%s　%d 日" % [r["name"], r["days"]]
	pending_action = &"set_sail"
	pick_options = rows
	pick_prompt = "要前往哪一座港口？"
	mode = Mode.PICK
	return true


## ponytail: 航行免费且瞬间到达；补给、水手、海上事件等世界航海做出来再接在这里。
func _sail(route: Dictionary) -> void:
	world.day += route["days"]
	world.port_id = route["to"]
	world.notice = "航行 %d 日，抵達%s。" % [route["days"], route["name"]]
	_end_step()
	slot = -1
	mode = Mode.SAILED


## 结束单选/金额输入，回到开它的地方：设施菜单，或（出航区开的单选）港里。
func _end_step() -> void:
	pending_action = &""
	amount_cap = 0
	amount_step = 100
	amount_prompt = ""
	pick_prompt = ""
	pick_options = []
	pending_good = {}
	mode = Mode.FACILITY_MENU if slot >= 0 else Mode.WALKING


## (本港, 事件码) 登记的剧情；没登记、或旗标让它这次一句都不演，返回 null。
func _story_at(code: int) -> EventInterpreter:
	if event_script == null or game_state.scenario < 0:
		return null
	var label := event_script.find_entry(game_state.chapter, port_id, code)
	if label == "":
		return null
	world.goal()  # 让「目标已达成」旗标跟上眼下的资产，剧本的分支才看得到
	var it := EventInterpreter.new(event_script, game_state, game_state.chapter)
	return it if it.start(label) and it.has_content() else null
