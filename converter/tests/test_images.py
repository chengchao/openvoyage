"""字库转换测试：1.PAT/2.PAT → 字模图集 PNG（+ manifest）。"""
import json
import os
import struct
from pathlib import Path

import pytest

from koukai2 import images


def _png_dims(path: Path) -> tuple[int, int]:
    blob = path.read_bytes()
    assert blob[:8] == b"\x89PNG\r\n\x1a\n"
    w, h = struct.unpack(">II", blob[16:24])  # IHDR data 紧跟 8+4+4
    return w, h


def test_convert_font_extracts_glyph_atlas(tmp_path):
    # 3 个字模（96B）：第 0 个左上角点亮
    pat = bytearray(3 * 32)
    pat[0] = 0x80  # glyph0 row0 bit15 = 左上像素
    rep = images.convert_font(bytes(pat), tmp_path, "font1")
    assert rep["glyphs"] == 3
    assert _png_dims(tmp_path / "font" / "font1.png") == (64 * 16, 16)  # 1 行（<64 字）
    assert b"tRNS" in (tmp_path / "font" / "font1.png").read_bytes()  # 透明底
    m = json.loads((tmp_path / "font" / "font1.json").read_text())
    assert m["glyphs"] == 3 and m["cols"] == 64 and m["glyph"] == 16


# ------------------------------------------------------------- 原版档层 --

GAMEDIR = os.environ.get("KOUKAI2_DIR", "")
needs_game = pytest.mark.skipif(
    not (GAMEDIR and Path(GAMEDIR).is_dir()),
    reason="set KOUKAI2_DIR to the original game directory",
)


@needs_game
def test_original_fonts_produce_expected_glyph_counts(tmp_path):
    r1 = images.convert_font((Path(GAMEDIR) / "1.PAT").read_bytes(), tmp_path, "font1")
    r2 = images.convert_font((Path(GAMEDIR) / "2.PAT").read_bytes(), tmp_path, "font2")
    assert r1["glyphs"] == 5409  # 常用字模
    assert r2["glyphs"] == 6800  # 次常用字模
    assert (tmp_path / "font" / "font1.png").exists()
