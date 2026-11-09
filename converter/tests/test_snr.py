"""SNDT 容器解析 + SNR 字节码普查（M1「普查报告」交付物）。

格式（自主逆向并对原档验证，见 docs/koukai2-docs/07 §7.1、08 §8.1）：
  0x00  "SNDT"
  0x04  BE16 剧本号（SNR1–6 = 0..5，SNR0 = 0x80）
  0x10  BE32 分节偏移表，0xFFFFFFFF 终止
  之后  各分节字节码

普查方法（字节扫描，复现已验证事实）：统计载荷区各字节频率（指令直方图）；
对 C8/CC 读其后 BE16 操作数并给出范围/在界比例。已验证：SNR1 共 1174 个 C8 字节、
操作数 99.4% 落在 [0,1176)（MES 台词数）；CC 操作数 99.2% 落在 [0,256)。
"""
import os
import struct
from pathlib import Path

import pytest

from koukai2 import snr


# ---------------------------------------------------------------- 固件层 --

def _build(scenario_id: int, sections: list[bytes]) -> bytes:
    header = snr.MAGIC + scenario_id.to_bytes(2, "big")
    header += b"\x00" * (snr.SECTION_TABLE_OFFSET - len(header))
    table_size = (len(sections) + 1) * 4
    off = snr.SECTION_TABLE_OFFSET + table_size
    offsets = []
    for s in sections:
        offsets.append(off)
        off += len(s)
    table = b"".join(o.to_bytes(4, "big") for o in offsets) + b"\xff\xff\xff\xff"
    return header + table + b"".join(sections)


def test_parse_container_basic():
    c = snr.parse_container(_build(0x80, [b"\x01\x02\x03", b"\xc7"]))
    assert c.scenario_id == 0x80
    assert c.section_count == 2
    # 两节范围相邻、末节到 EOF
    (s0, e0), (s1, e1) = c.sections
    assert e0 == s1 and e1 == c.file_size


def test_reject_bad_magic():
    with pytest.raises(snr.SnrError):
        snr.parse_container(b"XXXX" + b"\x00" * 0x20)


def test_reject_unterminated_section_table():
    bad = snr.MAGIC + b"\x00\x00" + b"\x00" * 10 + b"\x00\x00\x00\x20"  # 无 FFFFFFFF
    with pytest.raises(snr.SnrError):
        snr.parse_container(bad)


def test_census_counts_opcodes_and_be_operands():
    section = b"\xc8\x00\x05" + b"\xc8\x04\x00" + b"\xcc\x00\x0a" + b"\xc7"
    rep = snr.census(_build(0, [section]), mes_line_count=10)
    c8 = rep["opcodes"]["C8"]
    assert c8["count"] == 2
    assert c8["operand_min"] == 5 and c8["operand_max"] == 0x0400  # BE16
    assert c8["in_range_hi"] == 10 and c8["in_range_count"] == 1   # 仅 5 在界
    cc = rep["opcodes"]["CC"]
    assert cc["count"] == 1 and cc["operand_max"] == 10 and cc["in_range_count"] == 1
    assert rep["opcodes"]["C7"]["count"] == 1
    # 直方图是载荷区字节频率
    assert rep["histogram"]["c8"] == 2 and rep["histogram"]["c7"] == 1


def test_census_trailing_opcode_without_operand_does_not_crash():
    # C8 在区末，无法读满 2 字节操作数 → 计数但不纳入操作数统计，且不报错
    rep = snr.census(_build(0, [b"\xc7\xc8"]), mes_line_count=10)
    assert rep["opcodes"]["C8"]["count"] == 1
    assert rep["opcodes"]["C8"]["operand_min"] is None  # 无可读操作数


def test_static_walk_terminates_on_unknown_opcodes():
    region = b"\xc8\x00\x01\x99\x99\xc7\xfe"  # 含未知操作码 0x99/0xFE
    walk = snr.static_walk(region)
    assert walk["consumed"] >= len(region)  # 走完，不崩
    assert 0x99 in walk["unknown_opcodes"]


# ------------------------------------------------------------- 原版档层 --

GAMEDIR = os.environ.get("KOUKAI2_DIR", "")
needs_game = pytest.mark.skipif(
    not (GAMEDIR and Path(GAMEDIR).is_dir()),
    reason="set KOUKAI2_DIR to the original game directory",
)

# (文件序号, 剧本号, 分节数, MES台词数, C8字节数) —— 实测自原档
SNR_FACTS = [
    (0, 0x80, 13, 192, 194),
    (1, 0x00, 6, 1176, 1174),
    (2, 0x01, 8, 917, 919),
    (3, 0x02, 6, 532, 527),
    (4, 0x03, 5, 234, 234),
    (5, 0x04, 4, 326, 327),
    (6, 0x05, 6, 926, 930),
]


@needs_game
@pytest.mark.parametrize("n,sid,sects,mes,c8", SNR_FACTS)
def test_original_snr_census(n, sid, sects, mes, c8):
    dat = (Path(GAMEDIR) / f"SNR{n}.DAT").read_bytes()
    mesd = (Path(GAMEDIR) / f"SNR{n}.MES").read_bytes()
    mes_lines = struct.unpack(">I", mesd[:4])[0] // 4
    assert mes_lines == mes

    c = snr.parse_container(dat)
    assert c.scenario_id == sid
    assert c.section_count == sects

    rep = snr.census(dat, mes_line_count=mes_lines)
    assert rep["opcodes"]["C8"]["count"] == c8       # 复现文档的 C8 计数
    assert rep["mes_lines"] == mes
    # C8 操作数绝大多数落在台词索引区间内（SNR1 实证 99.4%）
    pct = 100 * rep["opcodes"]["C8"]["in_range_count"] / c8
    assert pct > 95.0
    # 静态遍历整篇字节码不崩
    payload = dat[c.payload_start :]
    assert snr.static_walk(payload)["consumed"] >= len(payload)
