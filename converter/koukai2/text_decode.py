"""自定义双字节文本编码 → Unicode（M5 交付物）。

游戏内中文文本是 **自定义双字节码** `(hi, lo)`，字模取自游戏自带字库 1.PAT/2.PAT
（字模号算式见 `font.py`，逆向自 MAIN.EXE 0x4554）。把字模 OCR 成 Unicode 即得码表
`data/code_table.json`（2059 码）。本模块用该表把 MES/MENU/MESSAGE/ITEM 容器解码为可读文本。

来历与校验见 `docs/HANDOFF-claude-code.md`、`docs/koukai2-docs/07 §7.5 / 08 §8.2`。

容器（复用 text_table 的偏移表切分；ITEM.MES 为 0x00 分隔）：
  SNRn.MES                : BE32 偏移表（每条一句台词）
  MESSAGE.DAT / MENU.DAT  : BE16 偏移表（MENU 每条是「菜单组」，组内 0x00 再分标签）
  ITEM.MES                : 0x00 分隔的道具说明

记录内控制码：`0x0A` 换行；`0x00` 组内分隔（→换行）；`0x24 xx` 变量
  （$n 主角名 / $s 动态名 / $r.. 港口引用 / $d.. 数值）。ASCII 0x20–0x7E 原样保留。

忠实性：表映射到游戏**实际显示字形**，保留 1994 中文版译写怪癖（討閥＝討伐）；
A956 字形为「餞」形而源文火焔→映射 焰；D8C6 无字模→兒（這兒/那兒 上下文）。
"""
from __future__ import annotations

import json
import os
from functools import lru_cache

from . import text_table

_DATA = os.path.join(os.path.dirname(__file__), "data", "code_table.json")


@lru_cache(maxsize=1)
def load_table(path: str | None = None) -> dict[str, str]:
    """载入 `code_table.json`，返回 `{大写四位十六进制码: 字符}`。"""
    raw = json.load(open(path or _DATA, encoding="utf-8"))
    return {k: v["c"] for k, v in raw.items()}


def decode(rec: bytes, *, keep_vars: bool = True, sep: str = "\n") -> str:
    """解码单条记录字节为字符串。

    - `keep_vars=True`：变量保留为 `$n`/`$s`/… ；`False`：统一替换为 `□`。
    - 组内 `0x00`（MENU 标签分隔）渲染为 `sep`；尾随分隔/换行会被去除。
    - 未在码表内的双字节码渲染为 `〔HHHH〕`（便于发现遗漏）。
    """
    table = load_table()
    out: list[str] = []
    i, n = 0, len(rec)
    while i < n:
        b = rec[i]
        if b == 0x00:                                   # 组内分隔
            out.append(sep); i += 1; continue
        if b == 0x0A:                                   # 换行
            out.append("\n"); i += 1; continue
        if b == 0x24 and i + 1 < n:                     # 变量 $x
            out.append("□" if not keep_vars else "$" + chr(rec[i + 1]))
            i += 2; continue
        if 0x81 <= b <= 0xD8 and i + 1 < n:             # 双字节字模
            key = f"{b:02X}{rec[i + 1]:02X}"
            out.append(table.get(key, f"〔{key}〕"))
            i += 2; continue
        if 0x20 <= b < 0x7F:                            # 半角 ASCII / 数字
            out.append(chr(b))
        i += 1
    return "".join(out).strip("\n")


# 文件名 → 偏移表宽度（SNRn.MES=4，MESSAGE/MENU=2）；ITEM.MES 走 0x00 分隔分支
_BE16 = {"MESSAGE.DAT", "MENU.DAT"}


def decode_file(data: bytes, fname: str, **kw) -> list[str]:
    """按文件类型切分容器并逐条解码，返回字符串列表。"""
    upper = fname.upper()
    if upper == "ITEM.MES":
        return [decode(r, **kw) for r in data.split(b"\x00")]
    width = 2 if upper in _BE16 else 4
    return [decode(r, **kw) for r in text_table.parse_records(data, width)]
