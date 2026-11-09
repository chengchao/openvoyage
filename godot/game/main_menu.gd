## 主菜单（纯表现层）。只把按钮点击翻译成意图信号，不碰场景树、不切场景、不退出，
## 以便单元测试可独立实例化、零副作用地验证。导航/退出由上层 Main 路由处理。
class_name MainMenu
extends Control

signal start_requested
signal view_requested
signal quit_requested


func _ready() -> void:
	(%StartButton as Button).pressed.connect(func() -> void: start_requested.emit())
	(%ViewButton as Button).pressed.connect(func() -> void: view_requested.emit())
	(%QuitButton as Button).pressed.connect(func() -> void: quit_requested.emit())
