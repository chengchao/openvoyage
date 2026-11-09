# 任务：把游戏文本解码成可读 Unicode（最后一跳）

## 现状（已完成，见 `docs/koukai2-docs/07` §7.5）
- 文本容器/控制码/标点已破并测试：`converter/koukai2/text_wip.py`
- 已反汇编出**内码 → 中文系统字模码**的精确变换 `text_wip.to_font_code(hi, lo)`
  （源自 MAIN.EXE 0x43A1，带回归测试 `tests/test_text_wip.py`）。
- **已坐实（像素级实证）：in‑game 汉字字形来自外部中文系统（int 15h AX=5000h），
  不是 1.PAT/2.PAT**。实机截图采样出的 `里斯本港` 字模与 1.PAT/2.PAT 全部 12209 个
  字模均不匹配（容错汉明距离 13–45/256，真匹配应 ≤5）。1.PAT/2.PAT 是另一套字库
  （部首序、不同字形），不是显示字体。
- 缺最后一步：**字模码 → Unicode**，需 DOSBox‑X 实际渲染本游戏所用的中文字库。

## ⛔ 已排除，勿再尝试
- ❌ **OCR 1.PAT/2.PAT 来认 in‑game 字**——字库不对（像素实证）。
- ❌ 文本码按 Big5/GBK/GB18030/SJIS 直接解码；❌ 1.PAT/2.PAT 当 Big5 码序（实为部首序）；
  ❌ `(hi-0x81)·188+rank(lo)` 直接索引；❌ 当作密排子集。

## 目标
把 `SNR0–6.MES`、`MESSAGE.DAT`、`MENU.DAT`、`ITEM.MES`、`NAME.TBL` 解成
可读繁体中文，输出到 `assets-converted/text/*.json`（gitignored），并补测试。

## 推荐做法（择一，按可靠度排序）

### A. 建「字模码 → Unicode」表，一次建表全量解码（首选）
1. 确认 `to_font_code()` 测试通过：`cd converter && uv run pytest tests/test_text_wip.py`
2. 收集全部文本里**出现过的不同字模码**（约 2793 个，去重）：对每个 (hi,lo) 跑
   `to_font_code()`，按出现频率排序（高频字优先建表、优先校验）。
3. 取这些字模码对应的 **16×16 字形位图**——来源是 **DOSBox‑X 实际渲染本游戏所用的
   中文字库**（不是 1.PAT/2.PAT！见上「已排除」）。定位 DOSBox‑X.app 里的 CJK 字体
   资源（FONTX2/HZK/内置点阵），确认其编码/索引方式，把 `to_font_code()` 输出映射到
   字库槽位渲染出 16×16 位图。先用已知明文（截图里的港名、菜单项）核对几个
   字模码→字库槽位的对应，确认映射方向无误。
4. **用 Claude 自己的视觉模型识字（不用 PaddleOCR/Tesseract）**：
   - 这是 16×16 点阵繁体字，传统 OCR 对低分辨率古字不稳；Claude 多模态对
     「看字模认字」更准，且量小（~2793 去重字模）。
   - 把字模**放大渲染成网格图**（建议每张 ≤100 字、放大到每字 ≥48px、留间距），
     用 `mcp__visualize` 或直接存 PNG，**让 Claude 逐格转写**成 Unicode。
   - 利用上下文：同部首/同区段聚在一起更易认；高频字先认、先用已知明文校。
   - 产出 `字模码 → Unicode` JSON 表（人工/Claude 抽查纠正高频字）。
5. 用该表 + `text_wip` 容器解析，批量解码全部 MES/DAT，输出 JSON。
6. 验收：抽几条与实机截图（店主招呼、菜单项）逐字对上；
   错的字回到第 4 步让 Claude 重看那几格；写 pytest 固定几条已知明文。

### B. 若 DOSBox‑X 字库是标准 Big5/ET，直接查表（更快，但需先验证编码）
- 先验证：取 1–2 个已知字（如截图里 `里`/`斯`/`本`）在 MES 里的内码，过
  `to_font_code()`，看输出是否落在该字库的 Big5/ET 槽位。若是，直接套
  `字模码 → Big5 → Unicode` 标准表，跳过 OCR。

### C. 兜底：截图 + Claude 视觉（不建表）
- 逐设施/逐对话在 DOSBox‑X 截图，让 Claude 直接读图转写。仅在 A/B 都受阻时用；
  5000+ 条不适合全量截图，适合抽样验证 A 的结果。

## 怎么启动 Claude Code
```bash
cd ~/code/my-koukai2
claude
```
开场说：「按 docs/TASK-text-decode.md 收尾文本解码，优先方案 A；先确认
to_font_code 测试通过，再去定位 DOSBox‑X 中文字库。」

## 注意
- 原版资产与解码产物**不进 repo**：文本 JSON 写 `assets-converted/text/`（已 gitignore）。
- 遵守 CLAUDE.md 三铁律：每 commit 可玩 + 带测试 + TDD。
- 字模码→Unicode 表本身（衍生自外部字库）也按衍生品处理，勿入库。

---

## 进展与交接（2026-06-07，「先 B 后 A」验证后收窄）

### 方案 B（验 `to_font_code` 输出 = 标准 Big5）→ **否决**
`to_font_code` 输出不是标准 Big5。试过的重建公式整句都不可读：
- `lead = font_high+0x80, trail = VALID[col−off]`（按 `to_font_code` 高/低半各自标定 off）
  → 干净汉字仅 **~67%**，整句乱（在 MESSAGE.DAT+SNR0.MES ~13k 字模上标定）。
- `lead = hi+0x20, trail = VALID[rank(lo)]`（`VALID` = Big5 尾字节 `0x40–0x7E ∪ 0xA1–0xFE`）
  → 逗号锚点完全吻合（`0x8131 → 0xA141`），但汉字全乱。

唯一已证锚点（，= rank 1）对得上、汉字对不上 → 内码/ROM 顺序**「类 Big5 但非标准 Big5」**，
无「码值→Big5→Unicode」标准表捷径。`bytes.decode('big5')` 不可用。

### 方案 A（渲染字模 + OCR）→ **卡在字库来源**
- 按本文档 idx 公式 `idx=(hi-0x81)*188+rank(lo)` 渲染 `1.PAT/2.PAT`：字形工整但**张冠李戴**——
  MENU.DAT 解出无意义汉字（不是预期的菜单项）。故该 idx 错，**或 `1.PAT/2.PAT` 根本不是正文字库**。
- 方案 A 真正需要 `to_font_code` 所指的**外部倚天/中文系統字库**（int 15h AX=5000h）：
  不在游戏档内；DOSBox-X 包内也无散装字库文件（编译进二进制）。

### 已确证可用（勿重做）
容器偏移表解析、控制码（00/0A/24）、标点行（0x81→，。？！）、`to_font_code` 变换
（MAIN.EXE 0x43A1 反汇编，回归测试 `tests/test_text_wip.py`）。

### ⭐ 交接给逆向侧的精确任务（最后一跳）
反汇编**「取字模位图」例程** = `to_font_code`(@0x43A1) 返回值的**消费方**：拿到 font code 后是
- **(a)** 调 `int 15h AX=5000h` 取外部倚天 ROM 位图，还是
- **(b)** 索引游戏自带 `1.PAT/2.PAT`（若是，精确 index 公式为何）？

定位该例程即可定论**位图来源 + 精确索引**，随后：
- 若 **(b)**：用 `1.PAT/2.PAT` 正确渲染 → Claude 视觉 OCR 建 `idx→Unicode` 表，跳过外部字库。
- 若 **(a)**：写小 DOS `.COM` 循环调 `int 15h AX=5000h` dump 16×16 位图 → OCR。

线索：`0x43A1` 的调用点 / 其返回寄存器的后续使用；以及游戏加载 `1.PAT/2.PAT` 的位置。
