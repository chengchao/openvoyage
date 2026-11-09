## 港口 NPC 群（纯逻辑）：每个 NPC 一个 GridWalker，自主游走，行为仿原版
## （docs/08 §8.4「NPC 用同一套系统自主游走」，节奏/避让对照原版实机与参照实现）：
## · 节流：每次移动尝试后歇 2–5 拍再动（NPC 不连续行走，步—停—步）；
## · 方向：上一步顺利则 75% 沿原方向继续（走直线），撞墙/被挡后重新四向均匀随机；
## · 身位：角色画 2 格宽×2 格高（32×32px，锚格=脚下左格）→ 任两角色锚格切比雪夫
##   距离 <2 即身体相叠；试图踏入与其他 NPC（或 blocked 锚格，如玩家）相叠的格子
##   视为相撞，原地不动。撞墙/越界同样原地不动（GridWalker 足迹判定）。
## 注入 RNG → 固定种子可复现，headless 可测。
## 原版无每港 NPC 路径表，故位置 = 出生点 + 自主游走。表现层据 pos/facing/char_set 渲染。
class_name NpcCrowd
extends RefCounted

const DIRS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const KEEP_DIR_CHANCE := 0.75  # 原版：上一步未受阻时 75% 沿原方向继续
const SKIP_MIN := 2            # 移动间歇 2–5 拍（原版节流）
const SKIP_MAX := 5
const MIN_CHAR_DIST := 2       # 角色锚格最小切比雪夫距离（身位 2×2 格）

# 每个 agent: {walker: GridWalker, char_set: int, cooldown: int, moved: bool, bumped: bool}
var agents: Array = []


func _init(map: PortMap, passability: TilePassability, spawns: Array,
		char_sets: Array, footprint := [Vector2i.RIGHT]) -> void:
	for i in spawns.size():
		agents.append({
			"walker": GridWalker.new(map, passability, spawns[i], footprint),
			"char_set": int(char_sets[i % char_sets.size()]) if not char_sets.is_empty() else 0,
			"cooldown": 0,
			"moved": false,
			"bumped": false,
		})


## 两角色锚格是否身体相叠（角色 2 格宽×2 格高 → 切比雪夫距离 <2 即相叠）。
static func bodies_collide(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) < MIN_CHAR_DIST and absi(a.y - b.y) < MIN_CHAR_DIST


## 推进一拍：冷却中等待；否则按原版模型选向（75% 直行）走一格，
## 与其他 NPC、blocked 锚格（如玩家）保持身位距离，撞墙/相撞则原地转向。
func step(rng: RandomNumberGenerator, blocked: Array = []) -> void:
	for a in agents:
		a.moved = false
		if a.cooldown > 0:
			a.cooldown -= 1
			continue
		a.cooldown = rng.randi_range(SKIP_MIN, SKIP_MAX)
		var w: GridWalker = a.walker
		var dir: Vector2i
		if not a.bumped and rng.randf() < KEEP_DIR_CHANCE:
			dir = w.facing
		else:
			dir = DIRS[rng.randi() % DIRS.size()]
		w.facing = dir  # 撞墙/被挡也转向（与主角一致）
		var target: Vector2i = w.pos + dir
		# 先验角色身位、再委托 GridWalker 走格（墙体/足迹判定与主角同一套）。
		a.moved = _clear_of_characters(target, a, blocked) and w.try_move(dir)
		a.bumped = not a.moved  # 受阻 → 下次重新随机选向


## 某格是否与任一 NPC 身体相叠（供玩家移动判定等外部查询）。
func blocks(cell: Vector2i) -> bool:
	for a in agents:
		if bodies_collide(cell, a.walker.pos):
			return true
	return false


## target 是否与其他角色（其余 NPC + blocked 锚格）保持身位距离。
func _clear_of_characters(target: Vector2i, self_a: Dictionary, blocked: Array) -> bool:
	for other in agents:
		if other != self_a and bodies_collide(target, other.walker.pos):
			return false
	for c in blocked:
		if bodies_collide(target, c):
			return false
	return true


func count() -> int:
	return agents.size()


func pos_of(i: int) -> Vector2i:
	return agents[i].walker.pos


func facing_of(i: int) -> Vector2i:
	return agents[i].walker.facing


func moved_last(i: int) -> bool:
	return agents[i].moved


func char_set_of(i: int) -> int:
	return agents[i].char_set
