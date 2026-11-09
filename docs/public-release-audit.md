# 公开仓库前的原版素材审计

审计对象：`origin/main` @ `c6a341e`，外加全部 git 历史。审计日期 2026-11-08。
本文不是法律意见。公开前请找懂游戏知识产权的人确认。

## 进度（引擎路线 A）

- [x] §1 原版美术：10 张样张已删，`converter/tests/test_repo_hygiene.py` 防止图片再进 repo（41e2edd）
- [x] §2 原版文字：台词、人名、菜单全表移出；依赖原档的测试改比 SHA-256，对本地原档全跑通过（bae1863）
- [x] §3 `code_table.json`：保留。字形来自外部中文系统（docs/07 §7.5），表是 OCR 得到的字码→字符映射，属事实性编码表
- [x] §4 改名 OpenVoyage：工程名、标题画面、README（含非关联与商标说明）、CLAUDE/AGENTS、计划文档、converter 描述。
  对原作的事实性提及（逆向文档、兼容说明、wiki 主题）保留。内部标识 `koukai2`（Python 包名、`docs/koukai2-docs/`）未改，公开仓库名用 `openvoyage`
- [x] `docs/wiki.html` 主角卡片：保留（名字与身份是事实，简介是自写；用户决定 2026-11-08）
- [ ] 已知遗留：2D 港口 HUD 标签（`port_scene.gd` 的商業價值等）仿原版界面，随 2D 港口删除一并消失
- [ ] §6 新建公开仓库，放清理后的快照

## 结论

现在不能直接公开。有 4 类原版素材必须先处理，其中原版美术同时存在于 main 和历史里，光删文件不够。

## 1. 原版美术（必须处理）

| 文件 | 内容 | 首次提交 |
|---|---|---|
| `docs/koukai2-docs/samples/keepers_all.png` | 16 幅原版店主画（GRAPH.DAT 块 6–21） | 421fcec |
| `docs/koukai2-docs/samples/keeper_marketplace.png` | 原版交易所店主画 | 421fcec |
| `docs/koukai2-docs/samples/kao_sample.png` | 原版人物头像（KAO） | 1f10518 |
| `docs/koukai2-docs/samples/char_walker.png` | 原版走路精灵（CHAR.LZW） | d2b0b1d |
| `docs/koukai2-docs/samples/walker_true_colors.png` | 原版走路精灵（调色板校准） | fab26f6 |
| `docs/koukai2-docs/samples/portchip_tiles.png` | 原版港口图块（PORTCHIP） | 1f10518 |
| `docs/koukai2-docs/samples/facility_signs.png` | 原版设施招牌 | bca4412 |
| `docs/koukai2-docs/samples/iap_npc.png` | 原版 IAP 人物 | 1f10518 |
| `docs/koukai2-docs/samples/iap1_seven_groups.png` | 原版 IAP 人物 | 24b0390 |
| `docs/koukai2-docs/samples/iap_identity_evidence.png` | 原版 IAP 人物 | 24b0390 |

`keepers_all.png` 已打开目视确认；其余 9 张的内容是按文件名和提交信息判断的。

处理：删除这 10 个文件，并从全部历史中清除（见第 6 节）。引用它们的文档段落改成文字描述。

已核对、可保留：`godot/data/placeholder/images/*.png` 是自制程序员美术（色块小人、棋盘格，125–193 字节）；
`char_placeholder.png` 虽在「用真 CHAR.LZW」那个提交（5cc600b）里加入，但它是无原档时的自制回退图。
`godot/addons/gut/` 是 GUT 插件自带素材（MIT）。
历史里从未提交过原版档或转换产物（`assets-converted/`、`.LZW/.DAT/.SNR/.EXE` 均无）。

## 2. 原版文字（必须处理）

| 位置 | 内容 |
|---|---|
| `godot/tests/unit/test_event_script.gd`、`test_event_interpreter.gd` | 原版 SNR1 剧情台词与人名：「〔管家麥克〕…公爵有令，不許您進家門。」「聽說父親叫我。」「門口無人。」、若昂 |
| `CLAUDE.md`、`AGENTS.md` | 引用同一句剧情台词、「歡迎光臨！」 |
| `godot/tests/unit/test_text_db.gd`、`docs/TASK-text-decode.md` | 店主台词「歡迎光臨！」「您買什麼？」「賣點什麼？」 |
| `converter/tests/test_facility_menu.py`、`godot/data/facility_actions.json`、`docs/wiki.html`、`docs/koukai2-docs/08-剧本对话与港口建筑.md` | 原版 MENU.DAT 菜单项全表（買進/賣出/投資/物價、晉見國王/申請國籍、存款/提款/貸款/還款…） |
| `godot/tests/smoke/smoke_test.gd`、`test_door_flow.gd`、`test_port_session.gd`、`test_port_agent.gd` | 合成剧情用了原版人名与台词式样（若昂、歡迎光臨） |

处理：测试改用自造台词和人名（测试只需要「有台词、$n 被代入」，不需要原文）。
菜单项是否算受保护的表达，单个词风险低，整张菜单表风险高一些；建议 `facility_actions.json` 只留 key 和序号，标签运行时从玩家自己的原档读。

## 3. 从原版推导出的数据（需要判断）

| 文件 | 内容 | 风险判断（推断） |
|---|---|---|
| `converter/koukai2/data/code_table.json` | 2059 个原版字码 → Unicode 的对照表 | 中。是事实性映射，但整表源自原版字库；可改为运行时由转换器从玩家原档生成 |
| `godot/data/facilities.json` | 槽位 → 设施种类、店主画块号、菜单组号 | 低。事实性索引，不含原版表达 |
| `docs/koukai2-docs/*.md` | 文件格式、压缩算法、字节码语义、内存地址 | 低到中。互操作性逆向说明；`02-可执行文件分析.md` 有少量汇编行（≤6 行）与地址表 |
| `docs/wiki.html`、`docs/wiki_data/` | 设施 wiki | 菜单原文见第 2 节；台词已按设计只存编号 |

测试里没有嵌入原版字节（无长字节字面量），依赖原档的测试都是 skip-if-missing。

## 4. 名称与商标（必须处理）

「大航海時代」「Uncharted Waters」「KOEI」共出现 29 行，主要在：
`README.md`、`godot/project.godot`（游戏名 `Uncharted Waters II Remake`）、`godot/game/main_menu.tscn`（标题画面）、
`godot/README.md`、`CLAUDE.md`、`AGENTS.md`、`docs/koukai2-godot-plan.md`、`docs/koukai2-docs/`、`converter/pyproject.toml`、
若干 converter 源码注释。仓库名 `my-koukai2` 本身也是原作罗马字。

处理：改成自己的游戏名；说明文字可写「受 1990 年代大航海题材游戏启发」，不用商标作产品名。

## 5. 删不掉的结构性绑定

清理完上面四类，仓库仍然是一款特定商业游戏的复刻：

- `converter/` 专门读取原版档（LS11、SNR、MENU、MESSAGE、ZA_DAT…）。
- sim 层 `EventInterpreter` 执行原版剧本字节码，事件键、槽位号沿用原版。
- 文档完整描述原版剧情结构与数据格式。

「不附带原档、要求玩家自备」是 ScummVM / OpenMW 一类项目的常见模式，风险较低，但仍取决于法律判断。

## 6. 历史怎么办

原版美术从第一个提交（1f10518，2026-06-04）起就在历史里。两种做法：

1. **新开公开仓库（推荐）**：清理后的快照作为新仓库的第一个提交，私有仓库保留完整历史。简单，不会漏。
2. **改写历史**：`git filter-repo --path docs/koukai2-docs/samples --invert-paths` 等；所有提交号都会变，所有 clone 和 worktree 都要重建，PR 历史里的旧提交仍可能被引用。

## 两条路线

- **A. 引擎路线**：完成 1–4，走第 6 节第 1 种做法，公开一个「需要玩家自备原版档」的引擎。保留逆向成果，仍有第 5 节的风险。
- **B. 原创路线**：在 A 的基础上，再去掉对原版档的依赖（剧本、文字、数据都自写），成为一款原创的大航海题材游戏。HD-2D 港口、PortSession、PortAgent 都可以直接带走。风险最低，工作量最大。
