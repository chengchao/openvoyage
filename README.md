# OpenVoyage

用 Godot 4.x 写的开源大航海题材游戏。**游玩不需要原版游戏**：发行包自带自制的美术、文字与数据。
游戏运行时不读取原版数据；《大航海時代 II》DOS 中文版只是开发时的参照对象。仓库本身不含任何原版美术、文字或数据。

OpenVoyage 是独立的爱好者项目，与 KOEI Tecmo 无关，也未获其认可。「大航海時代」是其权利人的商标，这里只用于说明开发时参照了哪款游戏。

- 计划与里程碑：[docs/koukai2-godot-plan.md](docs/koukai2-godot-plan.md)
- 原版逆向资料：[docs/koukai2-docs/](docs/koukai2-docs/)
- 工作守则（铁律/TDD/法律边界）：[CLAUDE.md](CLAUDE.md)

本仓库不含任何原版游戏资产。设施菜单、店主台词、开场剧情、货物与价格都是随包的自撰内容。
`converter/` 是开发者研究原版数据用的参照工具，玩家不需要它；CI 与冒烟测试使用 `placeholder/` 自制占位资产。

## 试玩

从 [Releases](https://github.com/chengchao/openvoyage/releases) 下载对应平台的压缩包，解压后直接运行，不需要安装 Godot，也不需要原版游戏。

- Windows：运行 `OpenVoyage.exe`。
- Linux：`chmod +x OpenVoyage.x86_64` 后运行。
- macOS：解压后双击 `OpenVoyage.app`。v0.1.1 起的包经过签名与公证，可直接打开；v0.1.0 的包会被系统拦下，请改下新版。

操作：方向键走路，朝门前进进入设施，Enter 确定，Esc 开选单或取消。
目前可玩的内容：里斯本与塞维利亚两座港、交易所买卖、银行存取、港务局出航、存读档，目标是把总资产做到 10000。

也可以从源码运行：装好 Godot 4.7 后执行 `godot --path godot`。

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
