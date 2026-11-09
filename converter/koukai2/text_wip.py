"""WIP text decoder for 大航海時代 II custom DBCS (see docs/07 §7.5).

STATUS: container + control codes + punctuation row DECODED and verified.
Hanzi glyph mapping is NOT yet correct (needs the subset-font remap table or
glyph OCR). Do not rely on hanzi output until validated against known plaintext.

Encoding: 2-byte (hi, lo); hi in 0x81..0xD7; lo drawn from four printable
bands -> 188 valid values. Controls: 0x00 end, 0x0A newline, 0x24 xx variable.
Punctuation (lead 0x81): glyph index == rank(lo). Verified: 0x8131=，0x8134=。
0x8138=？ 0x8139=！
"""
from __future__ import annotations

# The 188 valid trailing-byte values, in order, define rank(lo).
_LO = (list(range(0x30, 0x3A)) + list(range(0x41, 0x5B))
       + list(range(0x61, 0x7B)) + list(range(0x80, 0xFE)))
RANK = {b: i for i, b in enumerate(_LO)}
WIDTH = len(_LO)  # 188

PUNCT = {1: "，", 4: "。", 8: "？", 9: "！"}  # rank(lo) -> char, verified


def parse(msg: bytes):
    """Tokenize one MES message into a list of tokens:
    ('nl',) | ('var', n) | ('punct', char) | ('glyph', hi, lo, index)
    Glyph index uses the provisional (hi-0x81)*188+rank(lo) skeleton; it is
    correct for the punctuation row only."""
    out = []
    i = 0
    while i < len(msg):
        b = msg[i]
        if b == 0x00:
            break
        if b == 0x0A:
            out.append(("nl",)); i += 1; continue
        if b == 0x24:
            out.append(("var", msg[i + 1])); i += 2; continue
        if 0x81 <= b <= 0xFE and i + 1 < len(msg) and msg[i + 1] in RANK:
            lo = msg[i + 1]
            idx = (b - 0x81) * WIDTH + RANK[lo]
            if b == 0x81 and RANK[lo] in PUNCT:
                out.append(("punct", PUNCT[RANK[lo]]))
            else:
                out.append(("glyph", b, lo, idx))
            i += 2
        else:
            i += 1
    return out


def to_font_code(hi: int, lo: int):
    """Transform a MES 2-byte internal code into the external Chinese-system
    font code, reverse-engineered from MAIN.EXE 0x43A1. Returns None for
    non-hanzi. The result indexes the int-15h AX=5000h font ROM (倚天/中文系統,
    provided by DOSBox-X) -- NOT 1.PAT/2.PAT. Mapping font-code -> Unicode
    needs that external font's table (out of scope of the game files)."""
    if not (0x80 < hi < 0xF0):
        return None
    h = ((hi - (0x70 if hi < 0xA0 else 0xB0)) << 1) & 0xFF
    l = lo - 1 if lo >= 0x80 else lo
    if l < 0x9E:
        h -= 1
    else:
        l -= 0x5E
    return (h << 8) + ((l - 0x1F) & 0xFF)
