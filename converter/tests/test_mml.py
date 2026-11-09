"""D2.MML 头部偏移表解析测试。

格式（见 docs/koukai2-docs/06 §6.2）：小端 u16 偏移表，按「若干声道偏移 + 0 终止」为一组
（一组=一曲），各偏移指向编译后的 MML 字节码流。

⚠ 实测：干净的「升序声道偏移 + 0」模型只在**前 16 曲**成立（15 曲 4 声道 + 1 曲 3 声道，
止于 ~160 字节），其后头部出现 > 文件长度的值（疑为编译数据，非偏移），结构尚未吃透。
故本解析器只提取**已验证的干净前缀**并显式标记 partial，绝不臆造其余部分；完整解码
留待音频里程碑 M14（由播放需求拉动）。
"""
import os
import struct
from pathlib import Path

import pytest

from koukai2 import mml


def _build(tracks: list[list[int]]) -> bytes:
    """把若干「声道偏移组」编为 LE16 表（每组补 1 个 0 终止），再补足数据区。"""
    vals = []
    for t in tracks:
        vals += t + [0]
    header = b"".join(struct.pack("<H", v) for v in vals)
    return header + b"\x00" * 64  # 数据区占位（够大即可）


def test_parses_clean_prefix():
    rep = mml.parse_header(_build([[10, 14], [12]]))
    assert rep["tracks"] == [[10, 14], [12]]
    assert rep["channels_per_track"] == [2, 1]
    assert rep["track_count_clean"] == 2
    assert rep["partial"] is False


def test_rejects_implausible_first_offset():
    with pytest.raises(mml.MmlError):
        mml.parse_header(b"\x00\x00\x00\x00")  # data_start = 0


def test_marks_partial_on_out_of_range_offset():
    # data_start=8 → 读 4 个 u16: [8,0,9999,0]；第二组偏移 9999 越界 → partial 截断
    data = struct.pack("<HHHH", 8, 0, 9999, 0) + b"\x00" * 16
    rep = mml.parse_header(data)
    assert rep["tracks"] == [[8]]
    assert rep["partial"] is True
    assert rep["track_count_clean"] == 1


def test_marks_partial_on_non_ascending():
    data = struct.pack("<HHHH", 8, 0, 9, 7) + b"\x00" * 16  # 第二组 [9,7] 非升序
    rep = mml.parse_header(data)
    assert rep["partial"] is True
    assert rep["tracks"] == [[8]]


GAMEDIR = os.environ.get("KOUKAI2_DIR", "")
needs_game = pytest.mark.skipif(
    not (GAMEDIR and Path(GAMEDIR).is_dir()),
    reason="set KOUKAI2_DIR to the original game directory",
)


@needs_game
def test_original_d2_mml_clean_prefix():
    data = (Path(GAMEDIR) / "D2.MML").read_bytes()
    rep = mml.parse_header(data)
    assert rep["data_start"] == 1122
    # 已验证：前 16 曲干净（15×4 声道 + 1×3 声道），其后结构未明
    assert rep["track_count_clean"] == 16
    assert rep["channels_per_track"] == [4] * 15 + [3]
    assert rep["partial"] is True
    # 所有解析出的声道偏移都落在数据区内
    for track in rep["tracks"]:
        for off in track:
            assert rep["data_start"] <= off < len(data)
