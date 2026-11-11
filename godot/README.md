# Godot 工程（M0：walking skeleton）

Godot 4.7 + GDScript。OpenVoyage 引擎的可玩骨架；逻辑（`sim/`）与表现（`game/`）分离，
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

冒烟验收 `smoke_test.gd` 现在覆盖：主菜单 → 新开一局 → 开场剧情演完 → 港内行走与 HUD → 进设施 →
交易所买卖 → 银行存款 → 出航到第二座港卖货获利 → 存档/读档 → 标题「繼續航程」→ exit 0。
新功能往 `smoke_test.gd` 追加步骤，永久生效。

## 导出

导出预设在 `export_presets.cfg`（Windows / Linux / macOS）。CI 的 Export workflow 在打 `v*` 标签、
手动触发或 PR 改到导出配置时运行，并把三个平台的压缩包发布到 GitHub Release。
