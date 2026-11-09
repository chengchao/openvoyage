## HD-2D 主角：3D 胶囊碰撞 + 只绕竖轴朝向镜头的像素精灵。方向键在 XZ 平面自由移动。
class_name Avatar3D
extends CharacterBody3D

const SPEED := 4.0
const GRAVITY := 20.0
const PIXEL_SIZE := 0.06  # 32px 高占位精灵 ≈ 1.9 单位，建筑 4–7 单位高

var sprite: Sprite3D


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	shape.shape = capsule
	shape.position.y = 0.8
	add_child(shape)

	sprite = Sprite3D.new()
	sprite.texture = CharacterSprite.PLACEHOLDER
	sprite.pixel_size = PIXEL_SIZE
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = true
	sprite.offset.y = sprite.texture.get_height() * 0.5
	add_child(sprite)


## 方向键意图（XZ 平面单位向量，上 = -Z = 朝北）。
static func input_dir() -> Vector3:
	var d := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	return Vector3(d.x, 0, d.y)


func _physics_process(delta: float) -> void:
	var dir := input_dir()
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	if dir.x != 0.0:
		sprite.flip_h = dir.x < 0.0
	move_and_slide()
