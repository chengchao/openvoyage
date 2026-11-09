## GameMenu（游戏内选单表，纯逻辑）：真相源 res://data/game_menu.json。
extends GutTest

const INFO := 0
const FLEET := 1
const SYSTEM := 3


func before_each() -> void:
	GameMenu._reset()


func test_table_has_the_four_command_groups_in_order() -> void:
	var keys := []
	var sizes := []
	for i in GameMenu.categories().size():
		keys.append(GameMenu.categories()[i]["key"])
		sizes.append(GameMenu.items(i).size())
	assert_eq(keys, ["info", "fleet", "items", "system"])
	assert_eq(sizes, [10, 6, 2, 5])


func test_every_category_and_item_is_fully_described() -> void:
	var seen := {}
	for i in GameMenu.categories().size():
		assert_ne(GameMenu.categories()[i].get("label", ""), "", "分类 %d 有标题" % i)
		for item: Dictionary in GameMenu.items(i):
			var key: String = item.get("key", "")
			assert_ne(key, "", "项有 key")
			assert_false(seen.has(key), "key %s 唯一" % key)
			seen[key] = true
			assert_ne(item.get("label", ""), "", "%s 有标题" % key)
			assert_ne(item.get("desc", ""), "", "%s 有说明" % key)


func test_live_items_resolve_to_their_actions() -> void:
	assert_eq(GameMenu.action_of(INFO, 3), &"status", "主角情報")
	assert_eq(GameMenu.action_of(SYSTEM, 3), &"title", "回到標題")
	assert_eq(GameMenu.action_of(SYSTEM, 4), &"quit", "結束遊戲")


func test_unopened_or_out_of_range_items_have_no_action() -> void:
	assert_eq(GameMenu.action_of(FLEET, 0), &"", "尚未開放的项")
	assert_eq(GameMenu.action_of(INFO, 99), &"")
	assert_eq(GameMenu.action_of(INFO, -1), &"")
	assert_eq(GameMenu.action_of(4, 0), &"")
	assert_eq(GameMenu.action_of(-1, 0), &"")
	assert_eq(GameMenu.items(9).size(), 0)
