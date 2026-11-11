## DialogueDirector（表现层协调器）单元测试：把解释器节拍泵进对话窗，按推进逐句演出。
## headless 下用 advance() 模拟「按键越过当前句」，不依赖真实输入。
extends GutTest

const WORDS := ["〔守衛〕\n$n，請留步。", "〔夫人〕\n哎呀，$n。"]

# 协调器驱动 EventInterpreter（events/ 命令表运行器），节拍词表统一（鸭子类型）。
const EVENTS := {
	"scenario": 1,
	"chapters": [{"index": 0, "entries": [], "script": [
		{"label": "L0"},
		{"op": "branch", "if": "clear", "flag": 0, "to": "L_alt"},   # flag0 set → 不跳
		{"op": "window", "arg": 1},
		{"op": "portrait", "kao": 6},
		{"op": "say", "text": "snr1/0"},
		{"op": "wait"},
		{"op": "end"},
		{"label": "L_alt"},
		{"op": "say", "text": "snr1/1"},
		{"op": "wait"},
		{"op": "end"},
	]}],
}


func _director(out_started := [false]) -> DialogueDirector:
	var script := EventScript.new(EVENTS, WORDS)
	var st := GameState.new(1, 0)
	st.set_name("n", "阿明")
	st.set_flag(0, true)   # → branch(if clear) 不跳，落到管家句
	var interp := EventInterpreter.new(script, st, 0)
	interp.start("L0")
	var d := DialogueDirector.new()
	add_child_autofree(d)
	out_started[0] = d.play(interp)
	return d


func test_play_shows_first_line() -> void:
	var d := _director()
	assert_true(d.is_active())
	var line := d.current_line()
	assert_eq(line["speaker"], "守衛")
	assert_eq(line["body"], "阿明，請留步。", "$n 代入并显示首句")
	assert_eq(line["face"], 0x06)


func test_advance_past_last_line_finishes() -> void:
	var d := _director()
	watch_signals(d)
	d.advance()      # 越过唯一一句 → end → 结束
	assert_false(d.is_active())
	assert_signal_emitted(d, "finished")


func test_play_returns_false_when_no_content() -> void:
	# 入口指向只有 end 的标签 → 无可演内容，play 返回 false。
	var events := {"scenario": 1, "chapters": [{"index": 0, "entries": [], "script": [
		{"label": "L0"}, {"op": "end"},
	]}]}
	var script := EventScript.new(events, WORDS)
	var interp := EventInterpreter.new(script, GameState.new(1, 0), 0)
	interp.start("L0")
	var d := DialogueDirector.new()
	add_child_autofree(d)
	assert_false(d.play(interp), "无可演内容→不演出，调用方回退")
	assert_false(d.is_active())


func test_drives_event_interpreter_through_dialogue_ui() -> void:
	var d := _director()
	watch_signals(d)
	var line := d.current_line()
	assert_eq(line["speaker"], "守衛")
	assert_eq(line["body"], "阿明，請留步。")
	assert_eq(line["face"], 0x06)
	d.advance()   # 越过唯一一句 → end
	assert_false(d.is_active())
	assert_signal_emitted(d, "finished")


func test_portrait_beat_shows_placeholder_face() -> void:
	# 程序员美术：头像号 → 自制占位头像（不用原版 KAO）。
	var d := _director()
	assert_not_null(d._box._portrait, "CC 头像节拍应显示占位头像")


func test_one_click_advances_exactly_one_line() -> void:
	var events := {"scenario": 1, "chapters": [{"index": 0, "entries": [], "script": [
		{"label": "L0"},
		{"op": "say", "text": "snr1/0"}, {"op": "wait"},
		{"op": "say", "text": "snr1/1"}, {"op": "wait"},
		{"op": "end"},
	]}]}
	var interp := EventInterpreter.new(EventScript.new(events, WORDS), GameState.new(1, 0), 0)
	interp.start("L0")
	var d := DialogueDirector.new()
	add_child_autofree(d)
	d.play(interp)
	d._box.reveal_all()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	d._box._input(ev)
	assert_eq(d.current_line()["speaker"], "夫人", "点一下 → 下一句")
