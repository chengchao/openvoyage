"""大航海時代 II 中文版自带字库 1.PAT / 2.PAT 的解码。

逆向自 MAIN.EXE（反汇编实证，2026-06-08）：

* 启动时 open("1.pat")/open("2.pat")（映像 0x161A4），句柄存 ds:0xBDAE/0xBDB0，
  按需 lseek+read 单个字模 —— 这就是 in-game 汉字的真正来源
  （此前「外部 int 15h 字库」结论有误：int15 路径是移植残留，DOSBox-X 并不提供该服务）。

* 字模 = **16×14 像素 1bpp = 28 字节**（绘制器以高度 0x0E 调用）。
  文件按 **512 字节块**存放：每块 18 个字模（18×28=504）+ 8 字节填充。
  文件内偏移 = (n-1)*28 + ((n-1)//18)*8 ，n 为 1 起字模号。

* 内码 (hi,lo) → 字模号：MAIN.EXE 0x4554（每 hi 行 188 个：
  数字 10 + 大写 26 + 小写 26 + 0x80–0xFD 126）。hi ≤ 0xAF → 1.PAT；
  hi 0xB0–0xD8 → 2.PAT（行号 hi-0xB0，基址同 0x81 行）。无效 → 0x2228。
"""
from __future__ import annotations

import os
from dataclasses import dataclass

GLYPH_BYTES = 28          # 16x14 @1bpp
GLYPH_W, GLYPH_H = 16, 14
BLOCK = 512               # 18 glyphs + 8 pad
GLYPHS_PER_BLOCK = 18
INVALID_GLYPH = 0x2228    # MAIN.EXE 0x46D7: 无效内码的替代字模号

ROW = 188                 # 每 hi 行字模数：10+26+26+126


def glyph_no(hi: int, lo: int):
    """MAIN.EXE 0x4554：内码 (hi,lo) → 1 起字模号；无效返回 None。

    返回号对 hi>=0xB0 是 2.PAT 内的编号（从 1 重新起算），其余为 1.PAT 编号。
    """
    if hi == 0x82:
        if not (0xA0 <= lo <= 0xF3):
            return None
        return ((lo + 0x60) & 0xFF) + ((hi + 0x7E) & 0xFF) * ROW + 0xEB
    if hi == 0x81:
        si = 0
    elif 0x83 <= hi <= 0xAF:
        si = (hi - (0x92 if hi >= 0x91 else 0x81)) * ROW
    elif 0xB0 <= hi <= 0xD8:
        si = (hi - 0xB0) * ROW
    else:
        return None
    if 0x81 == hi or 0xB0 <= hi <= 0xD8:      # 0x81 行与 2.PAT 行共用小基址
        bases = (1, 0xB, 0x25, 0x3F)
    else:                                      # 0x83–0xAF 行（1.PAT 汉字区）
        bases = (0x24F, 0x259, 0x273, 0x28D)
    if 0x30 <= lo <= 0x39:
        return lo - 0x30 + si + bases[0]
    if 0x41 <= lo <= 0x5A:
        return lo - 0x41 + si + bases[1]
    if 0x61 <= lo <= 0x7A:
        return lo - 0x61 + si + bases[2]
    if 0x80 <= lo <= 0xFD:
        return lo - 0x80 + si + bases[3]
    return None


def file_offset(n: int) -> int:
    """1 起字模号 → .PAT 文件内字节偏移。"""
    m = n - 1
    return m * GLYPH_BYTES + (m // GLYPHS_PER_BLOCK) * 8


def glyph_count(file_size: int) -> int:
    full, rem = divmod(file_size, BLOCK)
    return full * GLYPHS_PER_BLOCK + rem // GLYPH_BYTES


@dataclass
class Font:
    pat1: bytes
    pat2: bytes

    @classmethod
    def load(cls, koukai2_dir: str) -> "Font":
        with open(os.path.join(koukai2_dir, "1.PAT"), "rb") as f:
            p1 = f.read()
        with open(os.path.join(koukai2_dir, "2.PAT"), "rb") as f:
            p2 = f.read()
        return cls(p1, p2)

    def glyph(self, hi: int, lo: int):
        """内码 → 28 字节字模（bytes），无效返回 None。"""
        n = glyph_no(hi, lo)
        if n is None:
            return None
        buf = self.pat2 if hi >= 0xB0 else self.pat1
        off = file_offset(n)
        g = buf[off:off + GLYPH_BYTES]
        return g if len(g) == GLYPH_BYTES else None

    def glyph_rows(self, hi: int, lo: int):
        """内码 → 14 行×16 位（int 列表，bit15=最左像素），无效返回 None。"""
        g = self.glyph(hi, lo)
        if g is None:
            return None
        return [(g[y * 2] << 8) | g[y * 2 + 1] for y in range(GLYPH_H)]
