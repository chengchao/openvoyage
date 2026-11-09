## 港口场景（表现层）：渲染港图、放置主角、镜头跟随、方向键行走。
## 数据由 PortLoader 提供（自制文本港图）；移动/碰撞判定全委托 sim 层 GridWalker。
## 图块按种类上色（程序员美术，见 TILE_COLORS），不用原版 PORTCHIP。
class_name PortScene
extends Node2D

const TILE := 16
# 原生 16px 图块、相机不缩放；基准分辨率 640×400（见 project.godot）。
const CAMERA_ZOOM := 1.0
# 港图取景矩形：居中 384×384(24×24 图块)，两侧 HUD 面板（左 88 / 右 168px）。实测自原版截图。
const MAP_VIEW := Rect2i(88, 8, 384, 384)

const CHAR_CHUNK := 0  # 主角精灵套号（CharacterSprite 色调）
const NPC_SETS := [1, 2, 3]    # NPC 精灵套号（色调区分）
const NPC_COUNT := 4           # 港内游走 NPC 数
const NPC_SEED := 0x6E7063     # 固定种子 → NPC 布局/游走可复现
# NPC 游走节拍（NpcCrowd.step 调用间隔）：与主角持键步速同阶（docs/08：一格约 0.2–0.4s）；
# NPC 自带 2–5 拍节流 → 实际每 3–6 拍走一格，步—停—步，仿原版实机观感。
const WANDER_INTERVAL := 0.35
# 主角网格相对图块网格右移半格(8px)：原版主角居于两格之间，故能正对 2 格宽的门居中（见 docs/04）。
const CHAR_X_SHIFT := TILE * 0.5
const MOVE_TIME := 0.14  # 一格移动的动画时长（docs/08 §8.4：≈2×8px 子步）

var _move_tween: Tween

var map: PortMap
var passability: TilePassability
var player: Player          # 主角 avatar（身份 + 移动/朝向）
var walker: GridWalker      # = player.walker（移动判定，兼容现有用法）
var facilities: FacilityTable  # 本港设施门口坐标表

var _data: PortData
var _camera: Camera2D
var _char: CharacterSprite  # 可复用走路精灵组件
var doors := DoorFlow.new()  # 撞门 → 剧情/设施/菜单流程

var _npcs: NpcCrowd
var _npc_sprites: Array = []
var _npc_rng: RandomNumberGenerator
var _wander_accum := 0.0


## 注入港口数据（测试/外部调用）。须在加入场景树前调用（_ready 会读取它）。
func inject_data(data: PortData) -> void:
	_data = data


## 注入剧情（事件脚本 + 运行时状态），见 DoorFlow。
func inject_story(event_script: EventScript, state: GameState) -> void:
	doors.inject_story(event_script, state)


func _ready() -> void:
	if _data == null:
		_data = PortLoader.load_default()
	map = _data.map
	passability = _data.passability
	# 主角精灵右移半格、身体探入右邻格 → 足迹含右格，防止贴右墙时身体嵌入墙里。
	walker = GridWalker.new(map, passability, _data.spawn, [Vector2i.RIGHT])
	player = Player.new(walker, CHAR_CHUNK)
	facilities = FacilityTable.new(_data.facilities)
	doors.port_id = _data.port_id
	add_child(doors)

	_camera = Camera2D.new()
	_camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	# 主角居于取景矩形中心（而非整屏中心）：偏移=屏中心−取景矩形中心。
	_camera.offset = get_viewport_rect().size * 0.5 \
		- (Vector2(MAP_VIEW.position) + Vector2(MAP_VIEW.size) * 0.5)
	add_child(_camera)
	_camera.make_current()
	_update_camera_limits()
	_update_camera()
	_setup_character()
	_build_hud()
	_spawn_npcs()
	queue_redraw()


## 港内 NPC：选若干可站立格出生，自主游走（NpcCrowd）。固定种子可复现。
func _spawn_npcs() -> void:
	_npc_rng = RandomNumberGenerator.new()
	_npc_rng.seed = NPC_SEED
	var spawns := _npc_spawn_tiles(NPC_COUNT, _npc_rng)
	if spawns.is_empty():
		return
	_npcs = NpcCrowd.new(map, passability, spawns, NPC_SETS, [Vector2i.RIGHT])
	for i in _npcs.count():
		var spr := CharacterSprite.new()
		spr.z_index = 1
		add_child(spr)
		spr.load_set(_npcs.char_set_of(i))
		spr.set_facing(_npcs.facing_of(i))
		spr.position = _cell_render_pos(_npcs.pos_of(i))
		_npc_sprites.append(spr)


## 收集可站立格（排除主角出生点与设施门），随机选 n 个、彼此及与出生点身位不相叠
## （与移动期同一条 NpcCrowd.bodies_collide 规则）。
func _npc_spawn_tiles(n: int, rng: RandomNumberGenerator) -> Array:
	var cand: Array = []
	for y in map.height:
		for x in map.width:
			var c := Vector2i(x, y)
			if c == _data.spawn or facilities.facility_at(c) >= 0:
				continue
			# 仅取主角附近（约取景矩形内 ±11 格）→ NPC 落在可见街区
			if absi(x - _data.spawn.x) > 11 or absi(y - _data.spawn.y) > 11:
				continue
			if walker.can_enter(c):
				cand.append(c)
	for i in range(cand.size() - 1, 0, -1):  # 种子洗牌
		var j := rng.randi() % (i + 1)
		var t: Vector2i = cand[i]; cand[i] = cand[j]; cand[j] = t
	var chosen: Array = []
	for c in cand:
		if chosen.size() >= n:
			break
		if NpcCrowd.bodies_collide(c, _data.spawn):
			continue
		var ok := true
		for s in chosen:
			if NpcCrowd.bodies_collide(c, s):
				ok = false
				break
		if ok:
			chosen.append(c)
	return chosen


## 格 → 渲染中心（与主角同样的 +8px 半格偏移，居于两格之间）。
func _cell_render_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE * 0.5 + CHAR_X_SHIFT, cell.y * TILE)


func _process(delta: float) -> void:
	if _npcs == null or doors.is_in_facility():
		return
	_wander_accum += delta
	if _wander_accum < WANDER_INTERVAL:
		return
	_wander_accum = 0.0
	_npcs.step(_npc_rng, [walker.pos])  # 与玩家身位保持距离
	var headless := DisplayServer.get_name() == "headless"
	for i in _npcs.count():
		var spr: CharacterSprite = _npc_sprites[i]
		spr.set_facing(_npcs.facing_of(i))
		if not _npcs.moved_last(i):
			continue  # 未移动只转向，不开补间
		spr.step_walk()
		var target := _cell_render_pos(_npcs.pos_of(i))
		# NPC 与主角同一套移动系统（docs/08 §8.4）→ 滑步时长同 MOVE_TIME；
		# 节流间歇 ≥3 拍(≥1s) ≫ MOVE_TIME → 补间不会重叠。
		if headless or not is_inside_tree():
			spr.position = target
		else:
			create_tween().tween_property(spr, "position", target, MOVE_TIME)


func walker_pos() -> Vector2i:
	return walker.pos


func move(delta: Vector2i) -> bool:
	if doors.is_busy():
		return false   # 设施模态层 / 剧情演出中不处理港口移动
	# 面门撞入：要走入的目标格是设施门 → 转向面门并进入，不踏上门格。
	var slot := facilities.facility_at(player.pos + delta)
	if slot >= 0:
		walker.facing = delta
		_char.set_facing(delta)
		_update_character_pos()
		doors.open(slot)
		return false
	var moved := false
	if _npcs != null and _npcs.blocks(player.pos + delta):
		walker.facing = delta   # 撞 NPC 身位同撞墙：只转向不移动
	else:
		moved = player.try_move(delta)
	_char.set_facing(player.facing)   # 撞墙也转向
	if moved:
		_char.step_walk()
		_animate_step()   # 平滑移动一格（headless 直接吸附）
	else:
		_update_character_pos()  # 仅转向，原地吸附
	return moved


## 主角渲染中心目标（含 +8px 半格偏移）。
func _char_target() -> Vector2:
	return Vector2(player.pos.x * TILE + TILE * 0.5 + CHAR_X_SHIFT, player.pos.y * TILE)


## 相机目标（与主角同步右移半格）。
func _cam_target() -> Vector2:
	return Vector2(walker.pos.x * TILE + TILE * 0.5 + CHAR_X_SHIFT, walker.pos.y * TILE + TILE * 0.5)


## 把主角+相机移到新格：游戏内补间动画，headless（测试/冒烟）直接吸附以保持同步可测。
func _animate_step() -> void:
	var ct := _char_target()
	var mt := _cam_target()
	if _camera == null or DisplayServer.get_name() == "headless" or not is_inside_tree():
		_char.position = ct
		if _camera:
			_camera.position = mt
		return
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween().set_parallel(true)
	_move_tween.tween_property(_char, "position", ct, MOVE_TIME)
	_move_tween.tween_property(_camera, "position", mt, MOVE_TIME)


func _unhandled_input(event: InputEvent) -> void:
	if doors.is_busy():
		return   # 设施层自行处理输入（ESC 退出）
	if event.is_action_pressed("ui_right"):
		move(Vector2i.RIGHT)
	elif event.is_action_pressed("ui_left"):
		move(Vector2i.LEFT)
	elif event.is_action_pressed("ui_up"):
		move(Vector2i.UP)
	elif event.is_action_pressed("ui_down"):
		move(Vector2i.DOWN)


# 图块种类 → 颜色（下标 = PortLoader.ROAD/PIER/SEA/WALL/DOOR）。ponytail: 纯色块，换正式图块集时改 TileMapLayer。
const TILE_COLORS := [
	Color(0.76, 0.70, 0.55),  # 街道
	Color(0.55, 0.38, 0.22),  # 码头
	Color(0.12, 0.30, 0.55),  # 海
	Color(0.62, 0.30, 0.22),  # 墙
	Color(0.20, 0.12, 0.06),  # 门
]
const HUD_PARCHMENT := Color(0.87, 0.81, 0.65)  # 羊皮纸面板
const HUD_INK := Color(0.13, 0.09, 0.06)        # 深褐字
const HUD_MENU_BG := Color(0.46, 0.11, 0.09)    # 暗红竖排菜单
const HUD_MENU_INK := Color(0.93, 0.88, 0.72)
const HUD_FRAME := Color(0.18, 0.28, 0.52)      # 蓝色描边
const HUD_WATER := Color(0.09, 0.16, 0.38)      # 深蓝水纹底

## 港口 HUD：左=日期/时钟/User Data，右=港名/商业值/竖排菜单/罗盘。布局与配色仿原版（实测截图）。
## 数值与港名为占位（真数据待 M6 经济层、港名待文本解码）；原版羊皮纸/罗盘美术在 GRAPH.DAT
## 640×400 块，其整帧编解码(0x132D)尚未破，故此处用绘制还原版式而非贴原图。
func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.layer = 1  # 压在港图/主角之上、设施模态(layer 5)之下
	add_child(hud)
	var vp := get_viewport_rect().size
	var lw := MAP_VIEW.position.x          # 左面板宽 88
	var rx := int(MAP_VIEW.end.x)          # 右面板起点 472
	var rw := int(vp.x) - rx               # 右面板宽 168
	var menu_w := 24
	var info_w := rw - menu_w              # 右侧信息区宽（菜单条之外）
	# 蓝色水纹底：只铺取景矩形之外（左右面板 + 上下边条），不遮挡港图
	_rect(hud, Rect2(0, 0, lw, vp.y), HUD_WATER)
	_rect(hud, Rect2(rx, 0, rw, vp.y), HUD_WATER)
	_rect(hud, Rect2(lw, 0, MAP_VIEW.size.x, MAP_VIEW.position.y), HUD_WATER)
	_rect(hud, Rect2(lw, MAP_VIEW.end.y, MAP_VIEW.size.x, vp.y - MAP_VIEW.end.y), HUD_WATER)

	# 左面板：日期卷轴 + 时钟 + User Data
	_scroll(hud, Rect2(4, 4, lw - 8, 40))
	_text(hud, "A.D.1522", Vector2(9, 6))
	_text(hud, "5.19", Vector2(9, 23))
	_scroll(hud, Rect2(4, 150, lw - 8, 24))
	_text(hud, "1:40 P.M", Vector2(9, 152))
	_scroll(hud, Rect2(4, 184, lw - 8, vp.y - 188))
	_text(hud, "User Data", Vector2(9, 188), HUD_INK, 13)
	var y := 214
	for f in [["聲望", "0"], ["現金", "···"], ["金幣", "2000"], ["金塊", "0"]]:
		_text(hud, f[0], Vector2(9, y))
		_rtext(hud, f[1], Vector2(8, y + 17), lw - 18)
		y += 44

	# 右面板：港名卷轴 + 商业数值 + 竖排菜单 + 罗盘
	_scroll(hud, Rect2(rx + 2, 4, info_w - 4, 44))
	_text(hud, "伊比利", Vector2(rx + 8, 5))
	_text(hud, "里斯本港", Vector2(rx + 8, 24))
	_scroll(hud, Rect2(rx + 2, 54, info_w - 4, 196))
	y = 60
	for c in [["商業價值", "780"], ["商業投資額", "0"], ["工業價值", "770"],
			["工業投資額", "0"], ["平均物價", "100%"]]:
		_text(hud, c[0], Vector2(rx + 6, y), HUD_INK, 13)
		_rtext(hud, c[1], Vector2(rx + 6, y + 16), info_w - 14)
		y += 38
	# 竖排红条菜单（最右）
	_rect(hud, Rect2(vp.x - menu_w, 0, menu_w, vp.y), HUD_MENU_BG)
	var ty := 10
	for item in ["情報", "経營", "命令", "航海術"]:
		for ci in item.length():
			_text(hud, item[ci], Vector2(vp.x - menu_w + 4, ty), HUD_MENU_INK)
			ty += 17
		ty += 12
	# 罗盘（右下）
	_compass(hud, Vector2(rx + info_w * 0.5, vp.y - 52), 34)


func _rect(hud: CanvasLayer, rect: Rect2, color: Color) -> void:
	var r := ColorRect.new()
	r.position = rect.position
	r.size = rect.size
	r.color = color
	hud.add_child(r)


func _scroll(hud: CanvasLayer, rect: Rect2) -> void:
	_rect(hud, rect.grow(1), HUD_FRAME)       # 蓝色描边
	_rect(hud, rect, HUD_PARCHMENT)           # 羊皮纸面


func _text(hud: CanvasLayer, s: String, pos: Vector2, color := HUD_INK, size := 14) -> void:
	var l := Label.new()
	l.text = s
	l.position = pos
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	hud.add_child(l)


func _rtext(hud: CanvasLayer, s: String, pos: Vector2, width: int, color := HUD_INK) -> void:
	var l := Label.new()
	l.text = s
	l.position = pos
	l.size = Vector2(width, 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 14)
	hud.add_child(l)


func _compass(hud: CanvasLayer, center: Vector2, r: float) -> void:
	var c := Control.new()
	c.position = center - Vector2(r, r)
	c.size = Vector2(r * 2, r * 2)
	hud.add_child(c)
	var ctr := Vector2(r, r)
	c.draw.connect(func() -> void:
		c.draw_circle(ctr, r, Color(0.10, 0.16, 0.34))                  # 深蓝底盘
		c.draw_arc(ctr, r, 0.0, TAU, 40, Color(0.80, 0.55, 0.20), 2.0)  # 铜环
		c.draw_colored_polygon(PackedVector2Array([                      # 竖向星
			ctr + Vector2(0, -r * 0.82), ctr + Vector2(r * 0.22, 0),
			ctr + Vector2(0, r * 0.82), ctr + Vector2(-r * 0.22, 0)]),
			Color(0.32, 0.46, 0.78))
		c.draw_colored_polygon(PackedVector2Array([                      # 横向星
			ctr + Vector2(-r * 0.82, 0), ctr + Vector2(0, r * 0.22),
			ctr + Vector2(r * 0.82, 0), ctr + Vector2(0, -r * 0.22)]),
			Color(0.58, 0.72, 0.92)))


func _update_camera() -> void:
	_camera.position = _cam_target()


func _update_camera_limits() -> void:
	var view := get_viewport_rect().size / CAMERA_ZOOM
	var world := Vector2(map.width * TILE, map.height * TILE)
	if world.x > view.x:
		_camera.limit_left = 0
		_camera.limit_right = int(world.x)
	else:
		var pad_x := int((view.x - world.x) * 0.5)
		_camera.limit_left = -pad_x
		_camera.limit_right = int(world.x) + pad_x
	if world.y > view.y:
		_camera.limit_top = 0
		_camera.limit_bottom = int(world.y)
	else:
		var pad_y := int((view.y - world.y) * 0.5)
		_camera.limit_top = -pad_y
		_camera.limit_bottom = int(world.y) + pad_y


func _draw() -> void:
	# 程序员美术：按图块种类上色（主角是独立 Sprite2D）
	for y in map.height:
		for x in map.width:
			draw_rect(Rect2(x * TILE, y * TILE, TILE, TILE), TILE_COLORS[map.tile_at(x, y)])


## 装配可复用的走路精灵组件，按 player 身份加载帧。
func _setup_character() -> void:
	_char = CharacterSprite.new()
	_char.z_index = 1  # 压在图块/房间之上
	add_child(_char)
	_char.load_set(player.character_id)
	_char.set_facing(player.facing)
	_update_character_pos()


func _update_character_pos() -> void:
	# 16×32 精灵：脚底对齐当前格底部，身体向上探入上一格（Sprite2D 居中 → 中心 y = 格顶）。
	_char.position = _char_target()
