"""最小索引 PNG 编码器测试（无第三方依赖，stdlib zlib）。"""
import struct
import zlib

import pytest

from koukai2 import png


def _parse_chunks(blob: bytes) -> list[tuple[str, bytes]]:
    assert blob[:8] == b"\x89PNG\r\n\x1a\n"
    out, p = [], 8
    while p < len(blob):
        (length,) = struct.unpack(">I", blob[p : p + 4])
        ctype = blob[p + 4 : p + 8].decode("ascii")
        data = blob[p + 8 : p + 8 + length]
        crc = struct.unpack(">I", blob[p + 8 + length : p + 12 + length])[0]
        assert crc == zlib.crc32(blob[p + 4 : p + 8 + length]) & 0xFFFFFFFF
        out.append((ctype, data))
        p += 12 + length
    return out


def test_encodes_valid_indexed_png_structure():
    palette = [(0, 0, 0), (255, 0, 0), (0, 255, 0)]
    indices = [0, 1, 2, 1]  # 2x2
    blob = png.encode_indexed_png(indices, 2, 2, palette)
    chunks = dict(_parse_chunks(blob))
    assert "IHDR" in chunks and "PLTE" in chunks and "IDAT" in chunks
    w, h, depth, ctype = struct.unpack(">IIBB", chunks["IHDR"][:10])
    assert (w, h, depth, ctype) == (2, 2, 8, 3)  # colortype 3 = 索引
    assert chunks["PLTE"] == bytes([0, 0, 0, 255, 0, 0, 0, 255, 0])


def test_idat_roundtrips_to_filtered_scanlines():
    indices = [0, 1, 2, 3, 4, 5]  # 3x2
    blob = png.encode_indexed_png(indices, 3, 2, [(i, i, i) for i in range(6)])
    idat = b"".join(d for t, d in _parse_chunks(blob) if t == "IDAT")
    raw = zlib.decompress(idat)
    # 每行 = 1 个 filter 字节(0) + 3 个索引字节
    assert raw == bytes([0, 0, 1, 2, 0, 3, 4, 5])


def test_rejects_index_out_of_palette():
    with pytest.raises(png.PngError):
        png.encode_indexed_png([0, 5], 2, 1, [(0, 0, 0), (1, 1, 1)])


def test_rejects_size_mismatch():
    with pytest.raises(png.PngError):
        png.encode_indexed_png([0, 1, 2], 2, 2, [(0, 0, 0), (1, 1, 1), (2, 2, 2)])


def test_trns_chunk_marks_transparent_index():
    palette = [(0, 0, 0), (255, 0, 0), (0, 255, 0)]
    blob = png.encode_indexed_png([0, 1, 2, 2], 2, 2, palette, transparent_index=2)
    chunks = dict(_parse_chunks(blob))
    assert "tRNS" in chunks
    # tRNS 到 index 2：alpha = [255, 255, 0]
    assert chunks["tRNS"] == bytes([255, 255, 0])


def test_write_indexed_png_to_disk(tmp_path):
    out = tmp_path / "x.png"
    png.write_indexed_png(out, [0, 1, 1, 0], 2, 2, [(0, 0, 0), (9, 9, 9)])
    assert out.read_bytes()[:8] == b"\x89PNG\r\n\x1a\n"
