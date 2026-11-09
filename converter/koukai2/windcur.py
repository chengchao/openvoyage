"""WINDCUR.DAT —— 风向/海流格网（帆船航速模拟查找表）。

格式（见 docs/koukai2-docs/05 §5.2、07）：1350 字节，每格 1 字节。原版实测含 121 个
不同取值（=11²）。**网格二维尺寸（1350 可分解为 45×30/50×27/54×25… 多种）与高低半字节
的精确语义（docs 标注「疑」分别编码风/海流）尚未验证**——故此处只做尺寸校验与原始格值
提取，并提供一个试探性的半字节拆分助手；真正的 2D 形状与语义由航海里程碑（M6/M7）校准。
"""
from __future__ import annotations

EXPECTED_SIZE = 1350


class WindCurError(ValueError):
    pass


def parse(data: bytes) -> list[int]:
    """校验尺寸并返回 1350 个原始格值（行优先与否未定，故仍按一维返回）。"""
    if len(data) != EXPECTED_SIZE:
        raise WindCurError(f"expected {EXPECTED_SIZE} bytes, got {len(data)}")
    return list(data)


def split_nibbles(cell: int) -> tuple[int, int]:
    """试探性拆分：(高半字节, 低半字节)，疑分别对应风/海流——语义未验证。"""
    return (cell >> 4, cell & 0xF)


def to_json_obj(cells: list[int]) -> list[int]:
    return list(cells)
