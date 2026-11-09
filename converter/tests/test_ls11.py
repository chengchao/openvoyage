"""LS10/LS11 解码器测试。

两层验证：
1. 自制固件（无版权问题）：编码器→解码器 roundtrip、手工构造位流。
2. 原版档全量校验（skip-if-missing）：需要环境变量 KOUKAI2_DIR 指向原版目录。
"""
import os
import struct
from pathlib import Path

import pytest

from koukai2 import ls11


# ---------------------------------------------------------------- 固件层 --

def test_magic_rejected():
    with pytest.raises(ls11.LS11Error):
        ls11.parse_header(b"LS99" + b"\x00" * 0x200)


def test_roundtrip_single_chunk():
    payload = bytes([1, 2, 3, 250, 255, 0, 0, 7])
    container = ls11.encode([payload])
    assert ls11.decode(container) == [payload]


def test_roundtrip_multiple_chunks_and_magic_ls10():
    chunks = [b"hello world", bytes(range(256)), b"\x00" * 100]
    container = ls11.encode(chunks, magic=b"LS10")
    assert ls11.decode(container) == chunks


def test_entry_table_offsets_are_contiguous():
    chunks = [b"aaa", b"bbbb"]
    container = ls11.encode(chunks)
    _, _, entries = ls11.parse_header(container)
    assert entries[1].offset == entries[0].offset + entries[0].compressed_size


def test_backreference_copy():
    """手工构造含回溯拷贝的位流：'AB' + 复制 distance=2,length=6 → 'ABABABAB'。"""
    w = ls11._BitWriter()
    w.code(ord("A"))          # 字面量（identity 字典）
    w.code(ord("B"))
    w.code(0x100 + 2)         # 匹配：distance 2
    w.code(3)                 # length = 3+3 = 6
    stream = w.to_bytes()
    out = ls11.decode_chunk(stream, 8, bytes(range(256)))
    assert out == b"ABABABAB"


def test_overlapping_backreference_acts_as_rle():
    w = ls11._BitWriter()
    w.code(ord("X"))
    w.code(0x100 + 1)         # distance 1：逐字节复制自身 → RLE
    w.code(4)                 # length = 7
    out = ls11.decode_chunk(w.to_bytes(), 8, bytes(range(256)))
    assert out == b"XXXXXXXX"


def test_dictionary_indirection():
    """code 是字典下标，不是字节值本身。"""
    dictionary = bytes([0xEE] + [0] * 255)
    w = ls11._BitWriter()
    w.code(0)                 # → dictionary[0] = 0xEE
    out = ls11.decode_chunk(w.to_bytes(), 1, dictionary)
    assert out == b"\xee"


def test_exp_golomb_code_ranges():
    """k 个前缀 1 → 取值区间 [2^(k+1)-2, 2^(k+2)-3]，抽查边界值。"""
    for value in (0, 1, 2, 5, 6, 13, 14, 0xFF, 0x100, 0x1FF):
        w = ls11._BitWriter()
        w.code(value)
        r = ls11._BitReader(w.to_bytes())
        assert r.code() == value


def test_encode_rejects_empty_chunk():
    """空块的压缩流长度为 0，会与条目表的 0 终止符冲突 → 必须拒绝而非静默丢数据。"""
    with pytest.raises(ls11.LS11Error):
        ls11.encode([b""])
    # 中间的空块尤其危险：会截断其后所有块
    with pytest.raises(ls11.LS11Error):
        ls11.encode([b"A", b"", b"B"])


def test_decode_zero_distance_raises_clean_error():
    """distance=0（code 0x100）是退化回溯，应抛 LS11Error 而非 IndexError。"""
    w = ls11._BitWriter()
    w.code(ord("A"))          # 先产出 1 字节，避免在空输出上触发别的路径
    w.code(0x100)             # distance = 0
    w.code(0)                 # length = 3
    with pytest.raises(ls11.LS11Error):
        ls11.decode_chunk(w.to_bytes(), 8, bytes(range(256)))


# ------------------------------------------------------------- 原版档层 --

GAMEDIR = os.environ.get("KOUKAI2_DIR", "")
needs_game = pytest.mark.skipif(
    not (GAMEDIR and Path(GAMEDIR).is_dir()),
    reason="set KOUKAI2_DIR to the original game directory",
)

# 逆向阶段已验证的事实（docs/koukai2-docs/03、04、08）
EXPECTED = {
    # 128 张大头像 (1920B=48×80, 索引 0–127) + 128 张小头像 (864B=48×36, 索引 128–255)
    "KAO.LZW": dict(magic=b"LS11", chunks=256, sizes={1920, 864}),
    "PORTMAP.LZW": dict(magic=b"LS11", chunks=101, sizes={9216}),
    # 3 条纵向条带（各 1350 chunk 偏移表 + 位掩码 chunk，见 docs/04 §4.5）
    "WORLDMAP.LZW": dict(magic=b"LS11", chunks=3, sizes={25394, 21973, 23907}),
    "PORTCHIP.LZW": dict(magic=b"LS11", chunks=14, sizes={30720, 4}),
    "CHAR.LZW": dict(magic=b"LS10", chunks=7, sizes=None),
    "OPGRAPH.LZW": dict(magic=b"LS10", chunks=14, sizes=None),
    "DATA1.LZW": dict(magic=b"LS11", chunks=19, sizes=None),
    "IAE1.LZW": dict(magic=b"LS10", chunks=35, sizes=None),
    **{f"IAP{i}.LZW": dict(magic=b"LS10", chunks=35, sizes=None) for i in range(1, 7)},
}


@needs_game
@pytest.mark.parametrize("name", sorted(EXPECTED))
def test_original_archive_decodes_fully(name):
    path = Path(GAMEDIR) / name
    data = path.read_bytes()
    magic, _, entries = ls11.parse_header(data)
    exp = EXPECTED[name]
    assert magic == exp["magic"]
    assert len(entries) == exp["chunks"]
    chunks = ls11.decode(data)
    for entry, chunk in zip(entries, chunks):
        assert len(chunk) == entry.raw_size
    if exp["sizes"]:
        assert {len(c) for c in chunks} == exp["sizes"]
