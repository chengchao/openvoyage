"""字库转换：点阵字库 1.PAT/2.PAT → 字模图集 PNG（+ JSON manifest），供 Godot 文本渲染。

原版的头像/图块/走路精灵/店主画等美术不再转换（游戏改用自制美术，见 CLAUDE.md）。
"""
from __future__ import annotations

import json
from pathlib import Path

from . import png

GLYPH = 16             # 字模 16×16


def _write_json(path: Path, obj) -> None:
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=1), encoding="utf-8")


GLYPH_BYTES = 32       # 16 行 × 2 字节，1bpp，MSB 在左
FONT_COLS = 64         # 字模图集每行字数


def convert_font(pat_bytes: bytes, out_dir, name: str) -> dict:
    """点阵字库 1.PAT/2.PAT → 字模图集 PNG（白墨透明底）+ manifest。

    每字模 16×16 1bpp（32B，MSB 在左）；按 Big5 区位顺序线性排列（见 docs/07 §7.5）。
    文本码值即字模索引：游戏据 (idx%cols, idx//cols) 取图集中第 idx 个字模渲染。"""
    out_dir = Path(out_dir)
    fdir = out_dir / "font"
    fdir.mkdir(parents=True, exist_ok=True)
    count = len(pat_bytes) // GLYPH_BYTES
    rows = (count + FONT_COLS - 1) // FONT_COLS
    w, h = FONT_COLS * GLYPH, rows * GLYPH
    px = [0] * (w * h)  # 0 = 透明底
    for gi in range(count):
        off = gi * GLYPH_BYTES
        gx, gy = (gi % FONT_COLS) * GLYPH, (gi // FONT_COLS) * GLYPH
        for r in range(GLYPH):
            bits = (pat_bytes[off + r * 2] << 8) | pat_bytes[off + r * 2 + 1]
            for c in range(GLYPH):
                if (bits >> (15 - c)) & 1:
                    px[(gy + r) * w + (gx + c)] = 1
    png.write_indexed_png(fdir / (name + ".png"), px, w, h,
                          [(0, 0, 0), (255, 255, 255)], transparent_index=0)
    _write_json(fdir / (name + ".json"), {"glyphs": count, "cols": FONT_COLS, "glyph": GLYPH})
    return {"glyphs": count}
