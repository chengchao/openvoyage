## EventScript（events/ 命令表脚本 + text/ 台词 + 触发入口查找）单元测试。纯逻辑、headless。
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


func test_words_can_ship_inside_the_events_document() -> void:
	var s := EventScript.new({"scenario": 1, "chapters": [], "words": ["第一句。"]})
	assert_eq(s.text("main/0"), "第一句。")


func test_shipped_story_loads_and_every_line_resolves() -> void:
	var s := EventScript.load_shipped()
	assert_not_null(s, "随包剧本读不出来")
	assert_gte(s.scenario, 0)
	assert_eq(int(s.goal["target"]), 10000)
	assert_ne(str(s.goal["text"]), "")
	assert_ne(str(s.names.get("n", "")), "", "主角有名字")
	var says := 0
	for step: Dictionary in s.chapter_script(0):
		match step.get("op", ""):
			"say":
				says += 1
				assert_ne(s.text(step["text"]), "", "台词 %s 没有文字" % step["text"])
			"branch", "jump":
				assert_gte(s.label_index(0, step["to"]), 0, "跳转目标 %s 不存在" % step["to"])
	assert_gt(says, 0)
	for e: Dictionary in s.chapters[0]["entries"]:
		assert_gte(s.label_index(0, e["label"]), 0, "入口 %s 不存在" % e["label"])
