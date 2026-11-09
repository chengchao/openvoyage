"""自定义双字节文本编码 → Unicode 解码（M5 交付物）。

码表 `koukai2/data/code_table.json`（2059 码）由 OCR 游戏自带字库 1.PAT/2.PAT 的字模建立
（见 docs/HANDOFF-claude-code.md、docs/koukai2-docs/07 §7.5）。本测试既验证纯逻辑（固件层，
无需原档），也在 KOUKAI2_DIR 存在时对真实 MES/MENU 端到端校验已知明文。
"""
import hashlib
import os
from pathlib import Path

import pytest

from koukai2 import text_decode as td


# ---------------------------------------------------------------- 固件层 --

def test_table_loads():
    t = td.load_table()
    assert len(t) == 2066
    assert t["8131"] == "，"          # 符号行实证标点
    assert t["9495"] == "存" and t["A0A0"] == "款"


def test_decode_ascii_glyph_and_var():
    # 'A' + 双字节(，) + 变量 $n
    rec = b"\x41\x81\x31\x24n"
    assert td.decode(rec) == "A，$n"


def test_decode_inner_nul_is_separator():
    # MENU 组内 0x00 分隔多个标签 → 渲染为换行
    assert td.decode(b"\x41\x00\x42") == "A\nB"


def test_decode_unknown_code_is_marked():
    out = td.decode(b"\xd8\xc7")       # 越界/未表内码
    assert "〔D8C7〕" in out


def test_decode_keep_vars_false_uses_placeholder():
    assert td.decode(b"\x24n", keep_vars=False) == "□"


# ---------------------------------------------------------- 原版档层（gated） --

GAMEDIR = os.environ.get("KOUKAI2_DIR", "")
needs_game = pytest.mark.skipif(
    not (GAMEDIR and Path(GAMEDIR).is_dir()),
    reason="set KOUKAI2_DIR to the original game directory",
)


@needs_game
def test_decode_snr1_first_line():
    lines = td.decode_file((Path(GAMEDIR) / "SNR1.MES").read_bytes(), "SNR1.MES")
    assert len(lines) == 1176
    assert hashlib.sha256(lines[0][:lines[0].index("〕") + 1].encode()).hexdigest() == "ac41bcb354761e69b3f55dcde8388124038b47ee4a4c1a2c79c728e9524a98b9"
    assert "公爵有令" in lines[0]


@needs_game
def test_decode_menu_contains_known_labels():
    groups = td.decode_file((Path(GAMEDIR) / "MENU.DAT").read_bytes(), "MENU.DAT")
    assert len(groups) == 61
    flat = "\n".join(groups)
    assert "存" in flat and "款" in flat          # 银行「存款」
    assert "工作介紹" in flat                       # 行会


@needs_game
def test_decode_message_count_and_plaintext():
    msgs = td.decode_file((Path(GAMEDIR) / "MESSAGE.DAT").read_bytes(), "MESSAGE.DAT")
    assert len(msgs) == 1022


@needs_game
def test_decode_item_descriptions():
    items = td.decode_file((Path(GAMEDIR) / "ITEM.MES").read_bytes(), "ITEM.MES")
    assert any("武器" in it for it in items)        # 道具说明含「武器」
