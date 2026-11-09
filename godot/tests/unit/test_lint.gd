## 代码 lint：扫描游戏代码，禁止已经咬过人的写法。每条规则写明为什么；确有必要时在该行加
## `# lint-allow: <规则 id>` 并在同行说明理由。
## 规则带 requires 时：regex 第 1 组捕获变量名，同文件里必须出现 requires % 变量名，否则违规。
extends GutTest

const SCAN_DIRS := ["res://game", "res://sim", "res://data"]
const RULES := [
	{
		"id": "process-mode-disabled",
		"regex": "PROCESS_MODE_DISABLED",
		"why": "用 process_mode 停用碰撞体会把它移出物理空间，恢复时若在 Area3D 内会再触发 body_entered"
			+ "（HD-2D 港口曾因此出了设施立刻被门拉回去）。只想停移动就用 set_physics_process(false)。",
	},
	{
		"id": "full-rect-mouse-filter",
		"regex": "(\\w+)\\.set_anchors_and_offsets_preset\\(Control\\.PRESET_FULL_RECT\\)",
		"requires": "%s.mouse_filter",
		"why": "全屏 Control 默认 MOUSE_FILTER_STOP，会吞掉下层所有点击（对话框压暗层曾让设施菜单点不动）。"
			+ "显式写 mouse_filter：只压暗用 IGNORE，模态挡点击用 STOP。",
	},
	{
		"id": "gui-input-mouse-filter",
		"regex": "(\\w+)\\.gui_input\\.connect",
		"requires": "%s.mouse_filter",
		"why": "Label/TextureRect 等默认 MOUSE_FILTER_IGNORE，接了 gui_input 也永远收不到点击（设施菜单「離開」曾点不动）。"
			+ "同文件里给它设 mouse_filter = MOUSE_FILTER_STOP。",
	},
]


func _gd_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir.path_join(d)))
	return out


static func violations(source: String, path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var lines := source.split("\n")
	for rule in RULES:
		var re := RegEx.create_from_string(rule["regex"])
		for i in lines.size():
			var m := re.search(lines[i])
			if m == null or lines[i].contains("lint-allow: " + rule["id"]):
				continue
			if rule.has("requires") and source.contains(rule["requires"] % m.get_string(1)):
				continue
			out.append("%s:%d [%s] %s" % [path, i + 1, rule["id"], rule["why"]])
	return out


func test_rule_catches_disabling_a_body_via_process_mode() -> void:
	var bad := "	player.process_mode = PROCESS_MODE_DISABLED if busy else PROCESS_MODE_INHERIT"
	assert_eq(violations(bad, "x.gd").size(), 1)


func test_rule_allows_pausing_physics_step_and_explicit_opt_out() -> void:
	assert_eq(violations("	player.set_physics_process(not busy)", "x.gd").size(), 0)
	var opted := "	hud.process_mode = PROCESS_MODE_DISABLED  # lint-allow: process-mode-disabled 纯 UI 节点"
	assert_eq(violations(opted, "x.gd").size(), 0)


func test_full_screen_overlay_must_choose_mouse_filter() -> void:
	var bad := "	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)\n	add_child(dim)"
	assert_eq(violations(bad, "x.gd").size(), 1, "全屏层默认 STOP 会吞掉下层点击")
	var ok := bad + "\n	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE"
	assert_eq(violations(ok, "x.gd").size(), 0)


func test_gui_input_handler_must_set_mouse_filter() -> void:
	var bad := "	item.gui_input.connect(_on_item_input)"
	assert_eq(violations(bad, "x.gd").size(), 1, "Label 默认 IGNORE，gui_input 永远不触发")
	var ok := "	item.mouse_filter = Control.MOUSE_FILTER_STOP\n" + bad
	assert_eq(violations(ok, "x.gd").size(), 0)


func test_game_code_has_no_lint_violations() -> void:
	var found := PackedStringArray()
	for dir in SCAN_DIRS:
		for path in _gd_files(dir):
			found.append_array(violations(FileAccess.get_file_as_string(path), path))
	assert_eq(found.size(), 0, "\n".join(found))
