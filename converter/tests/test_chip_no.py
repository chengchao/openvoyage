"""CHIP_NO.DAT（每港图块组编号）解析测试。

格式（见 docs/koukai2-docs/05、08）：原始档，每港 1 字节 = 该港使用的图块组编号 0–6
（按文化圈：欧洲/伊斯兰/东亚…）。原版实测 100 字节、取值集合 {0..6}。

注意：原版 CHIP_NO.DAT 为 100 字节，比港口数（101，见 ZA_DAT/PORTMAP）少一个——
docs/08 旧称「101 字节」有误，已据原档校正。
"""
import os
from pathlib import Path

import pytest

from koukai2 import chip_no


def test_parses_byte_per_port():
    assert chip_no.parse(bytes([0, 6, 3, 1])) == [0, 6, 3, 1]


def test_rejects_empty():
    with pytest.raises(chip_no.ChipNoError):
        chip_no.parse(b"")


def test_rejects_group_out_of_range():
    with pytest.raises(chip_no.ChipNoError):
        chip_no.parse(bytes([0, 7]))  # 7 > MAX_GROUP


GAMEDIR = os.environ.get("KOUKAI2_DIR", "")
needs_game = pytest.mark.skipif(
    not (GAMEDIR and Path(GAMEDIR).is_dir()),
    reason="set KOUKAI2_DIR to the original game directory",
)


@needs_game
def test_original_chip_no():
    data = (Path(GAMEDIR) / "CHIP_NO.DAT").read_bytes()
    assert len(data) == chip_no.EXPECTED_SIZE  # 100（实测）
    groups = chip_no.parse(data)
    assert len(groups) == chip_no.EXPECTED_SIZE
    assert all(0 <= g <= chip_no.MAX_GROUP for g in groups)
