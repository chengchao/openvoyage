## EventInterpreter（events/ 命令表 → 对话节拍）单元测试。纯逻辑、headless。
##
## 命令表语义（引擎验证，见 docs/09）：branch AC=if-set / AD=if-clear、jump、label、end；
## say/window/portrait/wait 产对话节拍；set/arith/query/cond/sound/music/raw = 记日志的安全 no-op。
## 节拍词表（open/portrait/line/wait/end）由 DialogueDirector 鸭子类型驱动。
extends GutTest

# 一段含两条分支的脚本（仿 SNR1 公爵府门）：
#   L_door: AD flag0 -> L_alt ;  AC flag5 -> L_alt2 ;  say0 ; jump L_end
#   L_alt:  say1 ; end
#   L_alt2: say2 ; end
#   L_end:  end
const SCRIPT := [
	{"label": "L_door"},
	{"op": "branch", "if": "clear", "flag": 0, "to": "L_alt"},
	{"op": "branch", "if": "set", "flag": 5, "to": "L_alt2"},
	{"op": "window", "arg": 1},
	{"op": "portrait", "kao": 6},
	{"op": "say", "text": "snr1/0"},
	{"op": "wait"},
	{"op": "jump", "to": "L_end"},
	{"label": "L_alt"},
	{"op": "say", "text": "snr1/1"},
	{"op": "wait"},
	{"op": "end"},
	{"label": "L_alt2"},
	{"op": "say", "text": "snr1/2"},
	{"op": "wait"},
	{"op": "end"},
	{"label": "L_end"},
	{"op": "end"},
]
const WORDS := [
	"〔守衛〕\n$n，今天不能進去。",
	"空無一人。",
	"〔$s夫人〕\n哎呀，$n。",
]


func _script() -> EventScript:
	return EventScript.new({"scenario": 1, "chapters": [{"index": 0, "entries": [], "script": SCRIPT}]}, WORDS)


func _state(flags := {}, names := {"n": "阿明", "s": "大人"}) -> GameState:
	var s := GameState.new(1, 0)
	for k in flags:
		s.set_flag(int(k), bool(flags[k]))
	for k in names:
		s.set_name(str(k), str(names[k]))
	return s


func _say_bodies(it: EventInterpreter) -> Array:
	var out: Array = []
	for _i in range(200):
		var b := it.next_beat()
		if b["kind"] == "line":
			out.append(b["body"])
		if b["kind"] == "end":
			break
	return out


func test_start_missing_label_returns_false() -> void:
	var it := EventInterpreter.new(_script(), _state(), 0)
	assert_false(it.start("L_nope"))
	assert_eq(it.next_beat()["kind"], "end", "未开始→直接 end")


# flag0 clear（默认）→ 第一条 AD 跳 L_alt，演 say1，end
func test_branch_clear_polarity_takes_jump() -> void:
	var it := EventInterpreter.new(_script(), _state({}), 0)
	assert_true(it.start("L_door"))
	assert_eq(_say_bodies(it), ["空無一人。"])


# flag0 set, flag5 clear → 两条分支都不跳，落到 say0（管家挡门），jump L_end → end
func test_fallthrough_to_butler_line_with_substitution() -> void:
	var it := EventInterpreter.new(_script(), _state({0: true, 5: false}), 0)
	it.start("L_door")
	assert_eq(_say_bodies(it), ["阿明，今天不能進去。"], "$n 已代入；jump 越过 alt 段到 end")


# flag0 set, flag5 set → 第二条 AC 跳 L_alt2，演 say2（$s 代入）
func test_branch_set_polarity_takes_jump() -> void:
	var it := EventInterpreter.new(_script(), _state({0: true, 5: true}), 0)
	it.start("L_door")
	assert_eq(_say_bodies(it), ["哎呀，阿明。"])


func test_full_beat_vocabulary_for_butler_path() -> void:
	var it := EventInterpreter.new(_script(), _state({0: true, 5: false}), 0)
	it.start("L_door")
	var kinds: Array = []
	for _i in range(20):
		var b := it.next_beat()
		kinds.append(b["kind"])
		if b["kind"] == "end":
			break
	assert_eq(kinds, ["open", "portrait", "line", "wait", "end"])


func test_portrait_and_line_payload() -> void:
	var it := EventInterpreter.new(_script(), _state({0: true, 5: false}), 0)
	it.start("L_door")
	assert_eq(it.next_beat()["kind"], "open")
	assert_eq(it.next_beat()["face"], 6, "CC 头像号")
	var line := it.next_beat()
	assert_eq(line["index"], 0, "say 的台词下标")
	assert_eq(line["speaker"], "守衛")
	assert_eq(line["body"], "阿明，今天不能進去。")


# set/arith/query/cond/sound/music/raw 均为记日志的安全 no-op，不影响控制流
func test_noop_ops_are_logged_and_skipped() -> void:
	var script := EventScript.new({"scenario": 1, "chapters": [{"index": 0, "entries": [], "script": [
		{"label": "L0"},
		{"op": "set", "code": "0x0f", "args": [1, 7]},
		{"op": "arith", "fn": "add", "args": [3, 1]},
		{"op": "query", "code": "0xdc", "args": [9, 2]},
		{"op": "cond", "code": "0x8e", "args": [1, 66], "to": "L_unreached"},
		{"op": "sound", "id": 7},
		{"op": "music", "id": 3},
		{"op": "raw", "code": "0xeb", "bytes": [1, 2, 3]},
		{"op": "say", "text": "snr1/1"},
		{"op": "wait"},
		{"op": "end"},
		{"label": "L_unreached"},
		{"op": "say", "text": "snr1/0"},
		{"op": "end"},
	]}]}, WORDS)
	var it := EventInterpreter.new(script, _state(), 0)
	it.start("L0")
	assert_eq(_say_bodies(it), ["空無一人。"], "cond 不评估→不跳转（取直落分支）")
	# 各 no-op 操作码都被记录（便于经验映射旗标/变量语义）
	var joined := "/".join(it.get_log())
	for code in ["set", "arith", "query", "cond", "sound", "music", "raw"]:
		assert_true(joined.contains(code), "应记录 no-op: " + code)


func test_portrait_from_var() -> void:
	var script := EventScript.new({"scenario": 1, "chapters": [{"index": 0, "entries": [], "script": [
		{"label": "L0"},
		{"op": "portrait", "from_var": 50},
		{"op": "say", "text": "snr1/1"},
		{"op": "wait"},
		{"op": "end"},
	]}]}, WORDS)
	var st := _state()
	st.set_var(50, 19)
	var it := EventInterpreter.new(script, st, 0)
	it.start("L0")
	assert_eq(it.next_beat()["face"], 19, "CD：头像号取自变量")


# 无 wait 的死循环跳转必须被守卫终止（不挂起 headless）
func test_infinite_jump_loop_is_guarded() -> void:
	var script := EventScript.new({"scenario": 1, "chapters": [{"index": 0, "entries": [], "script": [
		{"label": "L0"},
		{"op": "jump", "to": "L0"},
	]}]}, WORDS)
	var it := EventInterpreter.new(script, _state(), 0)
	it.start("L0")
	assert_eq(it.next_beat()["kind"], "end", "死循环→守卫终止为 end")


# 跨节（unresolved）跳转无法跟随→视为 end
func test_unresolved_jump_ends() -> void:
	var script := EventScript.new({"scenario": 1, "chapters": [{"index": 0, "entries": [], "script": [
		{"label": "L0"},
		{"op": "jump", "to": "L9999", "unresolved": true},
	]}]}, WORDS)
	var it := EventInterpreter.new(script, _state(), 0)
	it.start("L0")
	assert_eq(it.next_beat()["kind"], "end")


func _once_script() -> EventScript:
	return EventScript.new({"scenario": 1, "chapters": [{"index": 0, "entries": [], "script": [
		{"label": "L0"},
		{"op": "branch", "if": "set", "flag": 3, "to": "L_done"},
		{"op": "set_flag", "flag": 3},
		{"op": "say", "text": "snr1/1"},
		{"op": "wait"},
		{"label": "L_done"},
		{"op": "end"},
	]}]}, WORDS)


func test_set_flag_makes_a_scene_play_only_once() -> void:
	var st := _state()
	var first := EventInterpreter.new(_once_script(), st, 0)
	first.start("L0")
	assert_eq(_say_bodies(first), ["空無一人。"])
	assert_true(st.flag(3))
	var again := EventInterpreter.new(_once_script(), st, 0)
	again.start("L0")
	assert_eq(_say_bodies(again), [])


func test_set_flag_can_clear() -> void:
	var st := _state({3: true})
	var it := EventInterpreter.new(EventScript.new({"scenario": 1, "chapters": [{"index": 0, "entries": [], "script": [
		{"label": "L0"}, {"op": "set_flag", "flag": 3, "value": false}, {"op": "end"},
	]}]}, WORDS), st, 0)
	it.start("L0")
	it.next_beat()
	assert_false(st.flag(3))


func test_has_content_tells_whether_anything_will_play_without_consuming_it() -> void:
	var st := _state()
	var it := EventInterpreter.new(_once_script(), st, 0)
	it.start("L0")
	assert_true(it.has_content())
	assert_true(it.has_content(), "问两次结果一样")
	assert_eq(_say_bodies(it), ["空無一人。"], "问过之后台词一句不少")
	var again := EventInterpreter.new(_once_script(), st, 0)
	again.start("L0")
	assert_false(again.has_content(), "旗标已立：这段一句都不演")
