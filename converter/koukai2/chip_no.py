"""CHIP_NO.DAT —— 每港使用的图块组编号（文化圈皮肤）。

格式（见 docs/koukai2-docs/05、08）：原始未压缩档，每港 1 字节 = 图块组编号 0–6
（配合 PORTCHIP.LZW 的 7 组文化圈图块库）。

原版实测为 100 字节，取值集合恰为 {0..6}。注意它比港口数（101，见 ZA_DAT/PORTMAP）
少一个——docs/08 旧称「101 字节」有误，已据原档校正；100↔101 的成因待玩法里程碑确认。
"""
from __future__ import annotations

EXPECTED_SIZE = 100
MAX_GROUP = 6  # 图块组编号 0–6（7 个文化圈）


class ChipNoError(ValueError):
    pass


def parse(data: bytes) -> list[int]:
    """逐字节解析为图块组编号列表，校验取值 0..MAX_GROUP。"""
    if len(data) == 0:
        raise ChipNoError("empty CHIP_NO data")
    groups = []
    for i, b in enumerate(data):
        if b > MAX_GROUP:
            raise ChipNoError(f"port {i}: tile-group {b} out of 0..{MAX_GROUP}")
        groups.append(b)
    return groups


def to_json_obj(groups: list[int]) -> list[int]:
    return list(groups)
