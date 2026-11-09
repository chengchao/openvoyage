# OpenVoyage

用 Godot 4.x 写的大航海题材游戏开源引擎。它能读取并运行玩家**自备**的《大航海時代 II》DOS 中文版数据文件；
仓库本身不含任何原版美术、文字或数据。

OpenVoyage 是独立的爱好者项目，与 KOEI Tecmo 无关，也未获其认可。「大航海時代」是其权利人的商标，这里只用于说明兼容哪款游戏。

- 计划与里程碑：[docs/koukai2-godot-plan.md](docs/koukai2-godot-plan.md)
- 原版逆向资料：[docs/koukai2-docs/](docs/koukai2-docs/)
- 工作守则（铁律/TDD/法律边界）：[CLAUDE.md](CLAUDE.md)

本仓库不含任何原版游戏资产。运行与测试需要用户自备原版游戏目录，经 `converter/` 离线转换后使用；CI 与冒烟测试使用 `placeholder/` 自制占位资产。

## 布局

```
converter/        Python 转换管线（原版档 → PNG/TileSet/JSON）+ pytest
placeholder/      自制占位资产（CI 用）
godot/            Godot 工程（M0 创建）
docs/             计划 + 逆向文档
assets-converted/ 转换产物（untracked）
```

## 快速开始

```bash
cd converter
uv sync                                   # 安装依赖（含 dev 组 pytest）
uv run pytest                             # 跑转换管线测试
KOUKAI2_DIR=<原版目录> uv run pytest      # 含原版档全量校验
uv run python convert.py <KOUKAI2目录> ../assets-converted/   # 转换原版资产（M1 完成后）
```

## 许可

代码以 [MIT](LICENSE) 发布。`godot/addons/gut/` 是第三方插件 GUT，沿用其自带许可（见该目录 LICENSE.md）。
原版游戏数据不在本仓库内，也不在本许可范围内。
