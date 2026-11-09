"""WINDCUR.DAT（风向/海流格网）解析测试。

格式（见 docs/koukai2-docs/05 §5.2、07）：1350 字节，每格 1 字节编码风向/海流。
原版实测 121 个不同取值（=11²）。**网格的二维尺寸与高低半字节的精确语义尚未验证**
（docs 标注「疑」分别编码风与海流），故此处只做：尺寸校验 + 原始格值 + 试探性半字节拆分，
不臆造 2D 形状，待航海里程碑（M6/M7）校准。
"""
import os
from pathlib import Path

import pytest

from koukai2 import windcur


def test_rejects_wrong_size():
    with pytest.raises(windcur.WindCurError):
        windcur.parse(b"\x00" * 100)


def test_parses_flat_cells():
    cells = windcur.parse(bytes(windcur.EXPECTED_SIZE))
    assert len(cells) == windcur.EXPECTED_SIZE
    assert all(c == 0 for c in cells)


def test_split_nibbles_tentative():
    # 0x29 → 高半字节 2、低半字节 9（语义未验证，仅结构拆分）
    assert windcur.split_nibbles(0x29) == (2, 9)


GAMEDIR = os.environ.get("KOUKAI2_DIR", "")
needs_game = pytest.mark.skipif(
    not (GAMEDIR and Path(GAMEDIR).is_dir()),
    reason="set KOUKAI2_DIR to the original game directory",
)


@needs_game
def test_original_windcur():
    data = (Path(GAMEDIR) / "WINDCUR.DAT").read_bytes()
    assert len(data) == windcur.EXPECTED_SIZE
    cells = windcur.parse(data)
    assert len(set(cells)) == 121  # 已验证的不同取值数
