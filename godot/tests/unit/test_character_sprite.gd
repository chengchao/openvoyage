## CharacterSprite 单元测试：可复用的走路精灵组件（方向→帧 + 走路两帧 + 程序员美术占位精灵）。
extends GutTest


func _cs() -> CharacterSprite:
	var cs := CharacterSprite.new()
	add_child_autofree(cs)
	cs.load_set(0)
	return cs


func test_loads_placeholder_texture() -> void:
	var cs := _cs()
	assert_not_null(cs.texture, "应有纹理")
	assert_eq(cs.texture.get_width(), 32)
	assert_eq(cs.texture.get_height(), 32)  # 32×32（角色横跨两半块，取全宽）


func test_current_frame_follows_facing_and_walk() -> void:
	var cs := _cs()
	cs.set_facing(Vector2i.DOWN)
	assert_eq(cs.current_frame(), cs.DIR_FRAMES[Vector2i.DOWN][0])
	cs.step_walk()
	assert_eq(cs.current_frame(), cs.DIR_FRAMES[Vector2i.DOWN][1])
	cs.set_facing(Vector2i.UP)
	cs.step_walk()  # 回到第 0 步
	assert_eq(cs.current_frame(), cs.DIR_FRAMES[Vector2i.UP][0])


func test_step_walk_toggles() -> void:
	var cs := _cs()
	assert_eq(cs.walk_step(), 0)
	cs.step_walk()
	assert_eq(cs.walk_step(), 1)
	cs.step_walk()
	assert_eq(cs.walk_step(), 0)


func test_variants_are_tinted_apart() -> void:
	# 程序员美术只有一张精灵：主角/NPC 靠色调区分。
	var a := _cs()
	var b := CharacterSprite.new()
	add_child_autofree(b)
	b.load_set(1)
	assert_eq(a.texture, b.texture, "同一张占位精灵")
	assert_ne(a.modulate, b.modulate, "不同套号色调不同")
