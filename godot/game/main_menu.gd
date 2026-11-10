## 主菜单（纯表现层）。只把按钮点击翻译成意图信号，不碰场景树、不切场景、不退出，
## 以便单元测试可独立实例化、零副作用地验证。导航/退出由上层 Main 路由处理。
class_name MainMenu
extends Control

signal start_requested
signal continue_requested
signal view_requested
signal quit_requested

var save_path := SaveFile.DEFAULT_PATH  # 测试换成临时路径
var debug_tools := OS.is_debug_build()  # 资料检视器是开发工具，发行版不给玩家看；测试可改


func _ready() -> void:
	(%StartButton as Button).pressed.connect(func() -> void: start_requested.emit())
	var resume := %ContinueButton as Button
	resume.disabled = SaveFile.load(save_path) == null  # 读不出来的存档也不给点，免得点了没反应
	resume.pressed.connect(func() -> void: continue_requested.emit())
	var viewer := %ViewButton as Button
	viewer.visible = debug_tools
	viewer.pressed.connect(func() -> void: view_requested.emit())
	(%Version as Label).text = "v%s" % ProjectSettings.get_setting("application/config/version", "")
	(%QuitButton as Button).pressed.connect(func() -> void: quit_requested.emit())
