"""最小索引（调色板）PNG 编码器，仅用 stdlib（zlib/struct），无第三方依赖。

输出 colortype=3（索引）、bitdepth=8 的 PNG：忠实保留 4bit 索引 + 独立调色板，
体积小、便于后续校准调色板而不动像素数据。供转换管线把解码出的索引图写成 PNG。
"""
from __future__ import annotations

import struct
import zlib
from pathlib import Path

_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class PngError(ValueError):
    pass


def _chunk(ctype: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + ctype
        + data
        + struct.pack(">I", zlib.crc32(ctype + data) & 0xFFFFFFFF)
    )


def encode_indexed_png(
    indices: list[int],
    width: int,
    height: int,
    palette: list[tuple[int, int, int]],
    transparent_index: int | None = None,
) -> bytes:
    """把行优先索引列表编码为索引 PNG 字节。transparent_index 给定时写 tRNS，使该调色板项全透明。"""
    if width <= 0 or height <= 0:
        raise PngError(f"invalid dimensions {width}x{height}")
    if len(indices) != width * height:
        raise PngError(f"expected {width * height} indices, got {len(indices)}")
    if not 0 < len(palette) <= 256:
        raise PngError(f"palette must have 1..256 entries, got {len(palette)}")
    ncolors = len(palette)
    if any(not 0 <= i < ncolors for i in indices):
        raise PngError("index out of palette range")

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 3, 0, 0, 0)
    plte = bytes(c for rgb in palette for c in rgb)
    blob = _SIGNATURE + _chunk(b"IHDR", ihdr) + _chunk(b"PLTE", plte)

    if transparent_index is not None:
        if not 0 <= transparent_index < ncolors:
            raise PngError("transparent_index out of palette range")
        # tRNS：到 transparent_index 的 alpha 列表，该项 0（全透明），其余 255（不透明）
        alpha = bytes(0 if i == transparent_index else 255 for i in range(transparent_index + 1))
        blob += _chunk(b"tRNS", alpha)

    raw = bytearray()
    for row in range(height):
        raw.append(0)  # filter None
        start = row * width
        raw.extend(indices[start : start + width])
    blob += _chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + _chunk(b"IEND", b"")
    return blob


def write_indexed_png(
    path,
    indices: list[int],
    width: int,
    height: int,
    palette: list[tuple[int, int, int]],
    transparent_index: int | None = None,
) -> None:
    Path(path).write_bytes(encode_indexed_png(indices, width, height, palette, transparent_index))
