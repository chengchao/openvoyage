# Godot 工程（M0：walking skeleton）

Godot 4.3 + GDScript。OpenVoyage 引擎的可玩骨架；逻辑（`sim/`）与表现（`game/`）分离，
全部测试 headless 可跑。

## 目录

| 目录 | 职责 |
|---|---|
| `sim/` | 纯逻辑 `RefCounted` 类（不依赖场景树），如 `GameConfig` |
| `game/` | 场景、UI、输入（薄壳）：`main`（主控制器）、`main_menu`、`new_game_stub` |
| `data/` | 薄加载层 + 占位资产清单（`data/placeholder/manifest.json`） |
| `tests/unit/` | GUT 单元测试 |
| `tests/smoke/` | 冒烟验收（`smoke_test.gd`，SceneTree 脚本） |
| `addons/gut/` | 第三方测试框架 GUT（MIT，已 vendored） |

## 本地运行（commit 前门禁，须全绿）

```bash
# 首次或拉取后：导入资源（跑两遍以生成缓存）
godot --headless --path godot --import || true
godot --headless --path godot --import

# GUT 全部单元测试
godot --headless --path godot -s addons/gut/gut_cmdln.gd

# 冒烟验收（启动 → 主菜单 → 无错退出，exit 0）
godot --headless --path godot -s tests/smoke/smoke_test.gd

# 打开编辑器人工查看
godot --path godot
```

## 「可玩」定义（随里程碑加严）

当前 M0：headless 启动 → 主场景实例化 → 主菜单可达（开始/退出按钮存在且已接线）→ exit 0。
后续里程碑往 `smoke_test.gd` 追加步骤（港口行走、进设施、对话、存读档…），永久生效。
