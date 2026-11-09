"""通用大端偏移表文本容器解析测试（MESSAGE.DAT / MENU.DAT / SNRn.MES 共用）。

格式（已验证，见 docs/koukai2-docs/08 §8.2、05 §5.1）：
  表头 = count 个 width 字节大端绝对偏移（自文件头），count = 第一个偏移 / width；
  之后各条记录以 0x00 终止。MESSAGE/MENU 用 width=2，SNRn.MES 用 width=4。
  （MENU 每条是「菜单组」，组内还有多个 0x00 分隔的标签——故必须按偏移表切分，
   不能按 0x00 扫描切分。）

原版实测：MESSAGE.DAT=1022 条、MENU.DAT=61 条，且偏移自洽（无缝无重叠）。
"""
import os
from pathlib import Path

import pytest

from koukai2 import text_table as tt


# ---------------------------------------------------------------- 固件层 --

def _build(records: list[bytes], width: int = 2) -> bytes:
    """把若干记录编码为合法偏移表容器（每条补 1 个 0x00 终止符）。"""
    table_size = len(records) * width
    offsets = []
    body = bytearray()
    off = table_size
    for rec in records:
        offsets.append(off)
        chunk = rec + b"\x00"
        body += chunk
        off += len(chunk)
    header = b"".join(o.to_bytes(width, "big") for o in offsets)
    return header + bytes(body)


def test_roundtrip_records_be16():
    records = [b"AB", b"C", b"", b"hello"]
    parsed = tt.parse_records(_build(records, 2), width=2)
    assert parsed == records


def test_roundtrip_records_be32():
    records = [b"x", b"yz"]
    parsed = tt.parse_records(_build(records, 4), width=4)
    assert parsed == records


def test_count_derived_from_first_offset():
    records = [b"a", b"bb", b"ccc"]
    assert len(tt.parse_records(_build(records, 2), width=2)) == 3


def test_menu_group_internal_separators_preserved():
    """组内 0x00 分隔的多个标签必须保留（按偏移表切分，不按 0x00 切分）。"""
    group = b"item1\x00item2\x00item3"  # 组内已含 0x00
    parsed = tt.parse_records(_build([group], 2), width=2)
    assert parsed == [group]
    assert parsed[0].split(b"\x00") == [b"item1", b"item2", b"item3"]


def test_rejects_truncated_header():
    with pytest.raises(tt.TextTableError):
        tt.parse_records(b"\x00", width=2)


def test_rejects_zero_first_offset():
    with pytest.raises(tt.TextTableError):
        tt.parse_records(b"\x00\x00\x00\x00", width=2)


def test_rejects_first_offset_not_multiple_of_width():
    # first offset = 3, not divisible by width 2 → 非法表
    with pytest.raises(tt.TextTableError):
        tt.parse_records(b"\x00\x03\x00\x05ab", width=2)


def test_rejects_table_exceeding_file():
    # first offset = 0x1000 远超文件长度
    with pytest.raises(tt.TextTableError):
        tt.parse_records(b"\x10\x00ab", width=2)


def test_to_json_obj_emits_hex():
    obj = tt.to_json_obj([b"\x81\x39", b""])
    assert obj == ["8139", ""]


# ------------------------------------------------------------- 原版档层 --

GAMEDIR = os.environ.get("KOUKAI2_DIR", "")
needs_game = pytest.mark.skipif(
    not (GAMEDIR and Path(GAMEDIR).is_dir()),
    reason="set KOUKAI2_DIR to the original game directory",
)


@needs_game
@pytest.mark.parametrize("name,expected_count", [("MESSAGE.DAT", 1022), ("MENU.DAT", 61)])
def test_original_text_tables(name, expected_count):
    data = (Path(GAMEDIR) / name).read_bytes()
    records = tt.parse_records(data, width=2)
    assert len(records) == expected_count
    # 偏移自洽：表大小 + Σ(每条载荷+1 个终止符) 恰好用尽整个文件，无缝无重叠
    reconstructed = expected_count * 2 + sum(len(r) + 1 for r in records)
    assert reconstructed == len(data)
