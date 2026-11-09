## GameState（剧情旗标 + 脚本变量 + $n/$s 名字 + 当前剧本/章节）单元测试。纯逻辑、headless。
extends GutTest


func test_flags_default_clear_and_settable() -> void:
	var s := GameState.new()
	assert_false(s.flag(0), "未设旗标默认为 clear")
	assert_false(s.flag(17))
	s.set_flag(5, true)
	assert_true(s.flag(5))
	s.set_flag(5, false)
	assert_false(s.flag(5))


func test_vars_default_zero_and_settable() -> void:
	var s := GameState.new()
	assert_eq(s.get_var(50), 0, "未设变量默认 0")
	s.set_var(50, 19)
	assert_eq(s.get_var(50), 19)


func test_substitute_names() -> void:
	var s := GameState.new()
	s.set_name("n", "阿明")
	s.set_name("s", "海燕")
	assert_eq(s.substitute("$n登上$s號。"), "阿明登上海燕號。")
	# 未提供的变量（$r/$d 等查询型，语义未解）原样保留
	assert_eq(s.substitute("航向$r$d。"), "航向$r$d。")


func test_scenario_and_chapter() -> void:
	var s := GameState.new(1, 0)
	assert_eq(s.scenario, 1)
	assert_eq(s.chapter, 0)
	s.chapter = 2
	assert_eq(s.chapter, 2)
