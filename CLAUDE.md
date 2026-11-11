# OpenVoyage — 大航海题材游戏的 Godot 开源引擎

用 Godot 4.x (GDScript) 写的开源大航海题材游戏。**玩家游玩时不需要原版游戏**：发行包自带自制内容即可完整游玩（不附带任何原版素材），游戏运行时不读取原版数据。《大航海時代 II》DOS 中文版的数据只作开发时的参照（逆向资料 + `converter/`），用来理解原作的规则与结构。完整规格与里程碑见 `docs/koukai2-godot-plan.md`，原版逆向资料见 `docs/koukai2-docs/`（LS11 压缩、像素格式、SNR 字节码、ZA_DAT 等均已破解并验证）。

## 三条铁律（任何工作必须遵守）

1. **每次 commit 后 repo 都是可玩的游戏**——做不完的功能用 feature flag 关闭；Godot 工程建立后，冒烟验收（headless 启动→核心循环→无错退出）必须通过才能 commit。
2. **每次 commit 都有完整的测试与验收**——新代码必须带测试；commit 信息注明测试情况，如 `M3: 港口行走碰撞 [tests: 12 new, all green]`。
3. **TDD**——先写失败测试（红），再最小实现（绿），再重构。不允许先写实现。

## commit 前必须执行（全绿才允许 commit）

```bash
cd converter && uv run pytest -q              # 转换管线测试（uv 管理依赖）
# 本地有原版资产时跑全量校验：
KOUKAI2_DIR=~/Documents/Claude/Projects/sea/KOUKAI2 uv run pytest -q
# Godot 工程建立（M0）后追加：
godot --headless --path godot -s addons/gut/gut_cmdln.gd   # GUT 全部测试
godot --headless --path godot -s tests/smoke/smoke_test.gd # 冒烟验收
```

Python 一律用 `uv`（`uv sync` 装依赖、`uv run` 执行、`uv add` 加包）；`uv.lock` 入库。

## 架构原则

- 逻辑与表现分离：sim 层（经济/航海/战斗/SNR 解释器）是纯 `RefCounted` 类，不依赖场景树，headless 可测；场景只做渲染输入。
- 游戏代码只消费 Godot 资源，不解析原版格式。原版档→Godot 资源由 `converter/`（Python）离线完成。
- SNR 剧本字节码例外：运行时解释（语义仍在逆向中）。
- 模拟系统注入 RNG，固定种子可复现。

## 法律边界（不可违反）

- 原版游戏文件和**转换产物**（衍生品）一律不进 repo：原版档在 `~/Documents/Claude/Projects/sea/KOUKAI2/`（只读参照），转换产物写到 `assets-converted/`（已 gitignore）。
- CI 与冒烟测试使用 `placeholder/` 自制占位资产。
- **美术方针（2026-11-07 更正）：游戏不用原版美术**——港口图块/建筑、人物走路精灵、店主画、对话头像一律自制
  （当前为程序员美术：`godot/data/placeholder/` + 灰盒 3D 港口）；港口版图也自制（手工摆放的 3D 场景
  `godot/game/port3d/ports/*.tscn`），不用 PORTMAP/ZA_DAT 坐标。
  converter 已删除 KAO/PORTCHIP/PORTMAP/CHAR/GRAPH.DAT/IAP 图像提取；仍转换文本、剧本、字库与数据表。
- **内容方针（2026-11-09）：游玩不依赖原版档**——文字、菜单、剧情、字体、数值表都要有自制版本随包发行，是唯一的数据源；
  **已整体放弃原档兼容**：原版档与转换产物只供开发者参照，不是游戏的输入，也不做「玩家导入原档」功能。新代码不得读 `assets-converted/`。
  设施菜单标签与店主招呼已自撰（`godot/data/facility_actions.json` 的 `label` / `greetings`，由 `FacilityActions` 解析）；
  游戏代码里读转换产物的路径（TextDb / MesText / FontCodec / EventScript.load / 字模图集）已于 2026-11-09 删除。
  下文「当前状态」里提到这些类与「真 MENU / MESSAGE.DAT 台词」之处是历史记录。自撰开场剧情已随包（2026-11-09，`godot/data/story/main.json`，见「当前状态」的随包剧本一条）。
- 依赖原版档的测试标记 skip-if-missing。

## 当前状态

- [x] 仓库脚手架、converter 含已验证的 LS11 解码器 + pytest
- [x] M0：Godot 工程 + GUT + 冒烟框架 + 占位资产包 v0（主菜单可达，headless 全绿）
- [x] M1：转换管线 ①（LZW 全量校验、表格→JSON、SNR 普查报告）—— 仅 D2.MML 整表未吃透（前缀已解）
- [x] M2：转换管线 ②（两种像素布局→PNG：KAO 256/PORTCHIP 7/IAP 875/PORTMAP 101；
  Godot 资料查看器 + 占位包 v1）——**图像提取部分已于 2026-11-07 删除**（美术方针更正，仅留字库）
- [x] M3：港口场景 —— 最初是 2D 网格港（文本港图 + GridWalker），**已于 2026-11-09 删除**，由下面的 HD-2D 港口取代；
  留下 CharacterSprite（占位精灵按套号上色）
- [~] M4：设施进入 —— 12 槽门（自制港图门字符）+ FacilityTable 触发（sim）+ 面门撞入 + 设施合成场景
  （占位店主画 + 菜单壳）+ 进出闭环；冒烟「走到门口→进入→见店主→退出」通过。
  槽位↔设施映射据招牌共现+实机进门验证（6/8/9 已逐门实证，其余 0/1/2/3/4/5/7/10/11 待逐门复核——旧「已证」字样不完全可靠）。
  **2026-06-10 实机校正：{银行,道具屋,行会} 在槽 6/8/9 上是 3-循环错位**——逐门进门实证：槽 6（纹章盾 224）=行会（块 19+組 1）、槽 8（金器 234）=银行（块 14+組 0 存款/提款）、槽 9（柱卷 235）=道具屋（块 15+組 5 買進/賣出）；原误判 6=银行/8=道具屋/9=行会。招牌随门位不变（portmap 实测复核），仅 facilities.json 的 slot→key/name/keeper_block/menu_index 轮转归位（详见 docs/08 §8.3 校正注）。注意：银行=slot 8（M5 银行存取代码按 ft.key==bank 路由，与槽号无关）。
  待办：各设施实际功能（菜单/交易/对话=M5+）
- [~] M5：文本与对话 —— **文本解码已解**（`text_decode` + `code_table.json` 2059 码，
  MESSAGE/MENU/ITEM/SNR→Unicode，convert 产 text/*.json）；对话窗（名字栏/头像/逐字）+
  设施进门真台词（MESSAGE.DAT 店主招呼，TextDb）。
  **SNR 对话系统已通（逻辑/表现分离）**：converter 解出脚本程序（事件表+字节码→`snr/snrN.json`，
  分节头块字节长 N 与事件入口偏移基准 start+N 已逆向定型）；sim 层 `SnrInterpreter`（纯逻辑）
  从事件入口产对话节拍 open(C0)/portrait(CC)/line(C8)/wait(C7)/end，`SnrScript` 做事件查找 +
  〔说话人〕拆分 + $n/$s/$r/$d 代入；`DialogueDirector`（表现协调器）把节拍泵进 DialogueBox、
  按键推进、载占位头像；`StoryState` 持「设施门→事件号」触发表，港口撞门「事件表优先」派发
  （命中演剧情、否则进常规设施）。实证：真 SNR1 节0 事件0007 演出管家挡门台词（$n 已代入；原文不入库，测试比哈希）。
  **跳转/分支已逆向并接通（取代上面旧的「单段线性」局限）**：引擎验证的字节码长度模型（4 组分派 +
  组3 64 项跳转表）由 `snr_transpile.py` 解出**带标签的命令表脚本** events/snrN.json（say/window/
  portrait/wait + branch AC=if-set / AD=if-clear / jump / end，未命名演出操作码以 raw 无损保留）
  与 triggers/index.json（(剧本,章,港,设施)→事件标签）；契约 `converter/schema/*.json` + jsonschema 测试。
  sim 层新增 `GameState`（旗标 + 变量 + $名字 + 剧本/章）、`EventScript`（命令表/标签/入口/台词）、
  `EventInterpreter`（按旗标走 branch/jump/end，产同款节拍；set/arith/query/cond/sound/music/raw =
  记日志的安全 no-op，旗标/变量含义不臆造）；`DialogueDirector` 已鸭子类型化、新旧运行器通吃。
  实证：真 SNR1 第0章公爵府——全旗标 clear 演父亲召见正剧情 33 句到 end；flag0-set/flag5-clear 演管家挡门单句。
  衍生品 events/triggers 走 assets-converted（gitignore）。
  **撞门触发已端到端打通（Cowork 反汇编交付 P0，docs/09 §9.A，byte-verified 并对 SNR1 章0 实证）**：
  事件键 =（当前港号<<8 | 脚下设施码），设施码=ZA_DAT 槽位号 0..0x0B；`EventScript.find_entry` 逐字节
  复刻引擎搜索（表B 顺序线扫，hi==港 或 港<阈值且 hi==0xA3 通配，lo==设施码 或 lo==0xFF 兜底，首命中即返回；
  阈值主角轨 0x64/公共轨 0x82）；`PortData.port_id`（里斯本=0）；撞门 find_entry（现由 sim 层 PortSession 调）→EventInterpreter→
  DialogueDirector，冒烟全链路通。地址约定：docs「映像偏移 X」=文件偏移−0x5200，事件 VM 段 0x2E09。
  其余已逆向定型（docs/09）：章节推进 = 脚本 F1(章)/F0(次级) 操作码、事件结束时 VM 主循环执行（持久于 KOUKAI2.DAT）；
  cond `10 BB CC AA`（BB/CC=操作数类型，AA=比较 0=`==`/1=`!=`/2=`>`/3=`>=`，假则跳，`0x8E[1,66]`=`if var[1]<66`）；
  双轨：公共 SNR0 旗标@DS:0xD60/变量@0xD68、主角 SNRn 旗标@DS:0xCD6/变量@0xCDE（SNR1 旗标 #N 即 0xCD6 第 N 位）；
  查询 DC/D0 子分派 `table[subtype]:base+index*stride+field`（$s/$r/$d 源）。
  旧 SnrInterpreter/SnrScript/StoryState（sim 层）+ snr/ 步格式（converter snr.decode_script/decode_section）
  已删除——全被引擎验证的 EventInterpreter/events/ 路径取代；snr.census 普查独立、保留不动。
  待办：旗标/变量**语义**（哪位=哪剧情）靠脚本经验映射（反汇编只给位置，不臆造，见 §9.C）；F0/F1 与 (major,minor)
  在 KOUKAI2.DAT 的字节位置需 dump 存档；剩余演出操作码（CB/E9/EB…）；minor 次级阶段表B 接入转译器。
  **设施菜单已接真 MENU 并可交互**：FacilityScene 渲染 MENU.DAT 第 menu_index 组真菜单 + 末项「離開」，
  光标上下导航（回绕/黄高亮）、ui_accept 选定——末项→退出，其余→发 `menu_selected(index,label)` 信号。
  **menu_selected 已表驱动派发（M5）**：sim 层 `FacilityActions`（纯逻辑）据 `res://data/facility_actions.json`
  把 (设施 key, 菜单项序号) 解析为行为原语名；PortSession.choose 按 action 名 match 分发——有分支=已实装、落 default=
  「尚未開放」占位（取代旧的按中文 label/ft.key 硬编码）。已实装 deposit/withdraw（银行存取，金额模态→PlayerState）；
  余原语随各里程碑加 match 分支即生效，菜单表无需改。待办：贷款/还款/交易/出航… = M6+ 各自里程碑连原语。
- [~] HD-2D 港口（唯一的港口实现，开始游戏直接进入）：港口是手工摆放的 3D 场景
  `godot/game/port3d/ports/*.tscn`（当前灰盒里斯本，Forward+ 渲染，景深/泛光/SSAO/体积雾）。
  港口契约 = 根 `PortScene3D.port_id` + `Spawn` + `PortDoor`（slot 0..11 = SNR 事件键低字节，门位可变、槽号不可变）
  + `Departure`，由 test_port3d 逐港校验；站在门触发区内且朝门里（门节点 -Z）推方向键才进门。
  **玩法状态在 sim 层 `PortSession`**（WALKING/CUTSCENE/FACILITY_MENU/AMOUNT_ENTRY，转换只在合法模式生效；
  剧情查找、存取款、金额上限都在这里）；`DoorFlow` 只按 mode 建/拆剧情、设施面板、金额输入、游戏内选单。
  **agent 接口 `PortAgent`**：observe() 返回可序列化局面，act() 执行 walk/choose/leave/amount/cancel/next，headless 可玩。
  代码 lint 写在 `tests/unit/test_lint.gd`（随 GUT 跑；规则表：process-mode-disabled / full-rect-mouse-filter /
  gui-input-mouse-filter / accept-needs-mouse，违规须修或同行 `# lint-allow: <id>` 写明理由）。
  关卡几何 lint 写在 `tests/unit/test_lint_ports.gd`（每个 ports/*.tscn 从 Spawn 用主角胶囊洪泛：
  port-void 走得到却脚下没地面 / port-ledge 无遮挡落差 > 一级台阶 / port-unreachable 门或出航区走不到）。
  里斯本现有八扇门：交易所/酒馆/港务局/造船所（码头一排）、教会/王宫/行会（台地）、银行（槽 8，广场东侧，门朝西——从广场往东走进去）。
  塞維利亞（港 1，河港：广场北排交易所/酒馆/港务局、西侧银行门朝东、东岸栈桥出航）是第二座港。
  待办：港内 NPC（旧 2D 的 NpcCrowd 已随网格港删除，需按 3D 重做）；主角像素走路动画。
- [~] 游戏内选单（港里按 ESC 开/关）：内容表驱动——`godot/data/game_menu.json`
  （分类 情報/艦隊/隨身物/系統 仿原版指令分组，标题与说明自撰）→ sim 层 `GameMenu`；`PortSession.Mode.GAME_MENU`
  （只能从 WALKING 开、开着时不能进门/走动）+ `menu_detail`；表现层 `GameMenuPanel`（页签/项目/详情三栏 + 资金顶栏，键鼠皆可）。
  agent：`menu` / `menu_select` / `menu_activate`（选定光标项）/ `close`，observe 带 `game_menu` 与 `day`。已实装 action：
  `status`（主角情報，详情栏显示港名、第几日与资金）、`cargo`（貨物一覽）、`save`（儲存進度）、`load`（讀取進度）、
  `title`（回到標題）、`quit`（結束遊戲）；其余项 action 为空 = 「尚未開放」（灰字），随各里程碑在表里填 action 并加分支。
- [x] 存读档 + 跨场景状态：sim 层 `World`（player/story/port_id/day；`World.current` 跨场景存活，`new_game()` 开新局）是
  唯一的可存档状态，`PortSession` 只是在某个 world 上玩（`player_state`/`game_state`/`port_id` 都是 world 的视图）；
  `PortScene3D._ready` 把会话绑到 `World.current` 并写入所在港。`SaveFile` 存取 `user://save.json`（带 `version`，
  先写临时文件再改名）；`World.from_dict` 是信任边界——缺字段/类型不对/未知港一律整档拒收返回 null。
  主菜单「開始遊戲」= `World.new_game()`、「繼續航程」读档进港（存档读不出来则禁用）；进港统一走 `PortScene3D.enter`，
  港口场景路径只在 `data/ports.json`（`Market.port_scene`）。测试存档一律写 `user://test_tmp/`，不碰真存档。
  待办：`EventScript` 不在存档里（等随包剧本）。
- [~] 交易所买卖（贸易的第一步）：货物表 `godot/data/goods.json` + 港口表 `godot/data/ports.json`
  （按港号列买进单价，卖出 = 九折去尾；没列价的货物该港不交易；名称与价格均自撰）→ sim 层 `Market`。
  `PlayerState` 加 `cargo`（货物→件数）/ `hold`（船舱 100 件，占位）/ `buy` / `sell`。
  `PortSession.Mode.PICK`（通用单选步骤，货物与出航目的地共用）：採購/出售 → 选货（只列买得起、装得下 / 手上有的）→
  金额输入（件数，步长 1/10）→ 回菜单；`pick` / `confirm_amount` 按 `pending_action` 分发；「查看行情」回多行价目（店主对话框只容 3 行 = 6 种货）。
  表现层 `PickList`（单选列表模态，键鼠皆可）；agent：`pick` / `cancel`，observe 带 `cargo` 与 `pick`。
  游戏内选单「貨物一覽」已实装（action `cargo`）。两港六种货都有标价（`test_market` 断言：双向各至少两种货有赚头、买得到的货对岸都收）。
  待办：出資入股、行情涨跌。
- [~] 直达航行（核心循环：低买 → 航行 → 高卖）：`ports.json` 每港带 `routes: [{to, days}]`（`Market.routes`）。
  港务局「啟航出海」（`set_sail`）或走进 `Departure` 出航区（`PortSession.open_departure`，取消回到走路）→ 单选目的地 →
  `world.day += days`、`world.port_id = 目的港`、`world.notice` = 抵港通知（不进存档，下个港口场景显示几秒并清空）→
  `Mode.SAILED`（终态，本会话不再接受任何动作）；`DoorFlow.pick` 见到 SAILED 就调 `enter_port`（默认 `PortScene3D.enter`，
  测试注入假函数以免换掉 GUT 的场景）。agent：observe 带 `port {id, name}`，启航后旧 port 被释放，用 `PortAgent.current(tree)` 取新港。
  冒烟：里斯本买毛織品 → 啟航 → 塞維利亞卖出现金高于开局 → 在塞維利亞存档/读档/繼續航程。
  航行目前免费、瞬间到达。待办：世界地图航海、补给与水手、海上事件。
- [~] 随包剧本与目标：`godot/data/story/main.json`（自撰，EventScript 命令表格式 + `names` / `goal` / `words`），
  `EventScript.load_shipped()` 读取；`World.new_game()` 与读档都挂上它（`World.story_script`，内容不进存档，旗标进存档）。
  自撰剧本用 `set_flag` 操作码立旗标（逆向来的 `set` 仍是记日志的 no-op）；`EventInterpreter.has_content()` 让
  「旗标挡掉、一句不演」的剧情不开对话。抵港剧情 = 事件码 `PortSession.ARRIVAL`(0x10)：`PortSession.arrive()`
  WALKING → CUTSCENE → WALKING（开场只演一次，旗标 0）。目标「現金加存款達到 10000」在 `World.goal()`
  （达成即立旗标 1，之后花掉也算）；达成后进里斯本王宫演一次道贺（旗标 2），游戏照常继续。
  主角情報与 `PortAgent.observe()["goal"]` 都显示目标与进度。
- [~] 港口 HUD 与主菜单：`PortHud`（CanvasLayer layer 1，由 DoorFlow 持有，`_sync()` 时 refresh）——顶上一条
  港名/日期/现金/船舱/目标进度（游戏内选单开着时让位），底下一行操作提示只在走路时显示；抵港通知排在这条下面。
  主菜单全繁体（開始遊戲/繼續航程/結束遊戲）+ 标题 + 版本号（`project.godot` 的 `config/version`）；
  資料檢視器是开发工具，只在 `OS.is_debug_build()` 时显示按钮（`MainMenu.debug_tools` 可注入）。
- [ ] M6+：世界航海 / 贸易 / 战斗 / …（见 docs/koukai2-godot-plan.md §2）

## 逆向资料快速索引

- **Text decoding is solved — see `docs/HANDOFF-claude-code.md`; `code_table.json` is authoritative.**（取代旧的 `docs/TASK-text-decode.md` 待办/假说）
- LS10/LS11 解压算法：`docs/koukai2-docs/03-LS10-LS11压缩格式.md`（参照实现 `converter/koukai2/ls11.py`，已对原版全部 14 个容器验证）
- 像素格式（两种布局）：`docs/koukai2-docs/04-图形系统.md`
- SNR 脚本/对话/设施坐标：`docs/koukai2-docs/08-剧本对话与港口建筑.md`
- 全部 59 个原版文件的格式：`docs/koukai2-docs/05-数据文件格式目录.md`
- 逆向新发现请回写 docs，并同步更新相应测试断言。

## Agent skills

### Issue tracker

Issues 用 GitHub Issues 跟踪（gh CLI 操作）；外部 PR 不作为 triage 请求来源。见 `docs/agents/issue-tracker.md`。

### Triage labels

五个 triage 角色全部用默认标签名（needs-triage / needs-info / ready-for-agent / ready-for-human / wontfix）。见 `docs/agents/triage-labels.md`。

### Domain docs

单 context 布局：仓库根 `CONTEXT.md` + `docs/adr/`。见 `docs/agents/domain.md`。
