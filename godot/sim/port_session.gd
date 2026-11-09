## 港口玩法状态机（纯逻辑）：在港里走 → 撞门（剧情优先，docs/09 §9.A）→ 设施菜单 ⇄ 金额输入 → 离开。
## 不依赖场景树：表现层（DoorFlow）按 mode 渲染，agent 可直接驱动。转换只在合法 mode 下生效，否则返回 false/""。
class_name PortSession
extends RefCounted

enum Mode { WALKING, CUTSCENE, FACILITY_MENU, AMOUNT_ENTRY }

const STARTING_GOLD := 2000  # 开局现金（占位，待开场剧情/存档校准）
const NOT_OPEN_YET := "（此功能尚未開放）"

var port_id: int
var player_state := PlayerState.new(STARTING_GOLD, 0)
var event_script: EventScript  # 为空 = 无剧情
var game_state: GameState

var mode := Mode.WALKING
var slot := -1                       # 当前（或剧情后将进入的）设施槽号
var interp: EventInterpreter         # CUTSCENE 时有效
var amount_action := &""             # AMOUNT_ENTRY 时有效：&"deposit" / &"withdraw"
var amount_cap := 0
var amount_prompt := ""


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
		_:
			return NOT_OPEN_YET


## 确认金额：0..amount_cap 内才搬钱并回到菜单，返回余额；否则 ""、仍在输入。
func confirm_amount(amount: int) -> String:
	if mode != Mode.AMOUNT_ENTRY or amount < 0 or amount > amount_cap:
		return ""
	if amount_action == &"deposit":
		player_state.deposit(amount)
	else:
		player_state.withdraw(amount)
	_end_amount()
	return balance_line()


func cancel_amount() -> bool:
	if mode != Mode.AMOUNT_ENTRY:
		return false
	_end_amount()
	return true


func balance_line() -> String:
	return "現金 %d　存款 %d" % [player_state.gold, player_state.bank]


func _end_amount() -> void:
	amount_action = &""
	amount_cap = 0
	amount_prompt = ""
	mode = Mode.FACILITY_MENU


func _story_at(door_slot: int) -> EventInterpreter:
	if event_script == null or game_state == null or game_state.scenario < 0:
		return null
	var label := event_script.find_entry(game_state.chapter, port_id, door_slot)
	if label == "":
		return null
	var it := EventInterpreter.new(event_script, game_state, game_state.chapter)
	return it if it.start(label) else null
