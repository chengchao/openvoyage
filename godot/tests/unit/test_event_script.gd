## EventScript（events/ 命令表脚本 + text/ 台词 + 触发入口查找）单元测试。纯逻辑、headless。
## 末尾含真原档（assets-converted）skip-if-missing 用例：SNR1 公爵府 chapter 0 演到 end。
extends GutTest

const EVENTS := {
	"scenario": 1,
	"home_port": 0,
	"chapters": [
		{
			"index": 0,
			"entries": [
				{"trigger_id": "0007", "label": "L002c", "type": "facility", "port": 0, "facility": "house", "facility_code": 7},
				{"trigger_id": "a001", "label": "L083a", "type": "stage", "port": null, "facility": "tavern", "facility_code": 1, "stage": 0xa0},
			],
			"script": [
				{"label": "L002c"},
				{"op": "say", "text": "snr1/0"},
				{"op": "end"},
			],
		},
	],
}
const WORDS := ["〔守衛〕\n$n，今天不能進去。", "第二句。"]


func _script() -> EventScript:
	return EventScript.new(EVENTS, WORDS)


func test_chapter_script_and_count() -> void:
	var s := _script()
	assert_eq(s.scenario, 1)
	assert_eq(s.chapter_count(), 1)
	assert_eq(s.chapter_script(0).size(), 3)
	assert_eq(s.chapter_script(9).size(), 0, "越界章节→空")


func test_text_resolution_by_id() -> void:
	var s := _script()
	assert_true(s.text("snr1/0").begins_with("〔守衛〕"))
	assert_eq(s.text("snr1/1"), "第二句。")
	assert_eq(s.text("snr1/999"), "", "越界 id→空串")
	assert_eq(s.text("garbage"), "", "非法 id→空串")


func test_label_index() -> void:
	var s := _script()
	assert_eq(s.label_index(0, "L002c"), 0)
	assert_eq(s.label_index(0, "L_missing"), -1)


# 触发入口查找：撞门时按 (章, 港, 设施码) 找事件入口标签（events 的 entries 即触发表）
func test_find_entry_label() -> void:
	var s := _script()
	assert_eq(s.find_entry(0, 0, 7), "L002c", "里斯本(港0) house(7) → 公爵府入口")
	assert_eq(s.find_entry(0, 0, 6), "", "无此设施事件且无兜底→空")
	assert_eq(s.find_entry(0, 99, 7), "", "非本港→空")


# 引擎搜索语义（docs/09 §9.A.3，byte-verified）：首个命中即返回、低字节 0xFF 兜底、
# 高字节 0xA3 位置无关通配（港<阈值），专属项优先于兜底。
func test_find_entry_default_and_wildcard() -> void:
	var ev := {
		"scenario": 1,
		"chapters": [{"index": 0, "entries": [
			{"trigger_id": "0007", "label": "L_house"},
			{"trigger_id": "a305", "label": "L_stage"},
			{"trigger_id": "00ff", "label": "L_default"},
		], "script": []}],
	}
	var s := EventScript.new(ev, WORDS)
	assert_eq(s.find_entry(0, 0, 7), "L_house", "专属项 0007 命中")
	assert_eq(s.find_entry(0, 0, 6), "L_default", "港0 任意设施→该港兜底 00ff")
	assert_eq(s.find_entry(0, 0, 5), "L_stage", "0007 lo 7≠5 跳过 → a305 通配命中设施5")
	# 主角轨阈值 0x64：港 ≥ 0x64 时 0xA3 通配失效
	assert_eq(s.find_entry(0, 5, 5), "L_stage", "港5<0x64 → a305 通配命中设施5")
	assert_eq(s.find_entry(0, 0x70, 5), "", "港0x70≥0x64 → 通配失效，且非港0 无兜底")


func test_load_missing_dir_is_empty_and_safe() -> void:
	var s := EventScript.load("", 1)
	assert_eq(s.chapter_count(), 0, "缺产物→空脚本，保证 headless 可玩")
	assert_eq(s.find_entry(0, 0, 7), "")


# ----------------------------------------------------- 原版档层（skip-if-missing）--

func _real_snr1() -> EventScript:
	var dir := TextDb.converted_dir()
	var s := EventScript.load(dir, 1)
	return s


func test_real_snr1_chapter0_butler_refusal_line() -> void:
	# flag0=set, flag5=clear → 管家挡门单句（$n 代入）。引擎验证的 AC/AD 分支极性。
	var s := _real_snr1()
	if s.chapter_count() == 0:
		pending("no assets-converted/events/snr1.json (set up original game + run converter)")
		return
	var entry := s.find_entry(0, 0, 7)   # 港0 里斯本, 设施7 house = 公爵府
	assert_ne(entry, "", "应有公爵府入口")
	var st := GameState.new(1, 0)
	st.set_name("n", "阿明")
	st.set_flag(0, true)
	st.set_flag(5, false)
	var it := EventInterpreter.new(s, st, 0)
	assert_true(it.start(entry))
	var bodies: Array = []
	for _i in range(500):
		var b := it.next_beat()
		if b["kind"] == "line":
			bodies.append(b["body"])
		if b["kind"] == "end":
			break
	assert_eq(bodies.size(), 1, "该旗标态下只演一句")
	assert_eq(bodies[0].sha256_text(), "51fd327b9f202dc92111a6020a64f5de4a724f4d0cb42d45963341bece0f9bf2", "$n 已代入的管家挡门台词（原文不入库，比哈希）")


func test_real_snr1_chapter0_intro_runs_to_end() -> void:
	# 全旗标 clear（首次游玩态）→ 公爵府正剧情：父亲召见主角，演到 end（台词比哈希，原文不入库）。
	var s := _real_snr1()
	if s.chapter_count() == 0:
		pending("no assets-converted/events/snr1.json")
		return
	var st := GameState.new(1, 0)
	st.set_name("n", "阿明")
	st.set_name("s", "大人")
	var it := EventInterpreter.new(s, st, 0)
	assert_true(it.start(s.find_entry(0, 0, 7)))
	var bodies: Array = []
	var ended := false
	for _i in range(2000):
		var b := it.next_beat()
		if b["kind"] == "line":
			bodies.append(b["body"])
		if b["kind"] == "end":
			ended = true
			break
	assert_true(ended, "公爵府开场应跑到 end，不挂起")
	assert_gt(bodies.size(), 10, "开场是多句对话")
	assert_eq(bodies[0].sha256_text(), "56aa5386f11d5b335aca98e2df9bc9764fbb2833db5f53c090110c5d9e0a6677", "公爵府开场首句")
	assert_true(bodies[1].contains("阿明"), "$n 代入到公爵台词")
