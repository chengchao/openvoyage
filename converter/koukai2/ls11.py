"""KOEI LS10/LS11 容器解码/编码。

格式（自主逆向所得，规格见 docs/koukai2-docs/03-LS10-LS11压缩格式.md）：
  0x000  16B   魔数 "LS10"/"LS11" + 0 填充
  0x010  256B  字节字典（按频率排序）
  0x110  12B×n 条目表：(压缩大小, 原始大小, 绝对偏移) 各为大端 u32，4 字节 0 终止
  之后   各条目的压缩位流

位流（每字节自高位到低位）由变长非负整数 code 组成：
  读 k 个连续 1 直到 0；base = 2^(k+1)-2；再读 k+1 位 w；code = base + w
  code < 0x100  → 输出 dictionary[code]
  code >= 0x100 → distance = code-0x100, length = 下一个code+3，回溯逐字节复制
"""
from __future__ import annotations

import struct
from dataclasses import dataclass

MAGICS = (b"LS10", b"LS11")
HEADER_SIZE = 16
DICT_SIZE = 256
TABLE_OFFSET = HEADER_SIZE + DICT_SIZE  # 0x110


@dataclass(frozen=True)
class Entry:
    compressed_size: int
    raw_size: int
    offset: int


class LS11Error(ValueError):
    pass


def parse_header(data: bytes) -> tuple[bytes, bytes, list[Entry]]:
    """返回 (magic, dictionary, entries)。"""
    if len(data) < TABLE_OFFSET + 4:
        raise LS11Error("file too small")
    magic = data[:4]
    if magic not in MAGICS:
        raise LS11Error(f"bad magic {magic!r}")
    dictionary = data[HEADER_SIZE:TABLE_OFFSET]
    entries = []
    p = TABLE_OFFSET
    while True:
        if p + 4 > len(data):
            raise LS11Error("unterminated entry table")
        (csize,) = struct.unpack(">I", data[p : p + 4])
        if csize == 0:
            break
        if p + 12 > len(data):
            raise LS11Error("truncated entry")
        rsize, off = struct.unpack(">II", data[p + 4 : p + 12])
        entries.append(Entry(csize, rsize, off))
        p += 12
    return magic, dictionary, entries


class _BitReader:
    def __init__(self, src: bytes):
        self._src = src
        self._pos = 0
        self._buf = 0
        self._nbits = 0

    def bit(self) -> int:
        if self._nbits == 0:
            if self._pos >= len(self._src):
                raise LS11Error("bitstream exhausted")
            self._buf = self._src[self._pos]
            self._pos += 1
            self._nbits = 8
        self._nbits -= 1
        return (self._buf >> self._nbits) & 1

    def code(self) -> int:
        k = 0
        while self.bit() == 1:
            k += 1
        value = (1 << (k + 1)) - 2
        w = 0
        for _ in range(k + 1):
            w = (w << 1) | self.bit()
        return value + w


def decode_chunk(stream: bytes, raw_size: int, dictionary: bytes) -> bytes:
    out = bytearray()
    r = _BitReader(stream)
    while len(out) < raw_size:
        c = r.code()
        if c < 0x100:
            out.append(dictionary[c])
        else:
            distance = c - 0x100
            length = r.code() + 3
            if distance == 0:
                raise LS11Error("zero-distance back-reference")
            start = len(out) - distance
            if start < 0:
                raise LS11Error("back-reference before start of output")
            for i in range(length):
                out.append(out[start + i])
    if len(out) != raw_size:
        raise LS11Error("chunk overran declared raw size")
    return bytes(out)


def decode(data: bytes) -> list[bytes]:
    """解开容器，返回各条目的原始字节。"""
    _, dictionary, entries = parse_header(data)
    chunks = []
    for e in entries:
        stream = data[e.offset : e.offset + e.compressed_size]
        if len(stream) != e.compressed_size:
            raise LS11Error("entry exceeds file size")
        chunks.append(decode_chunk(stream, e.raw_size, dictionary))
    return chunks


# ---------------------------------------------------------------- encoder --
# 仅用于测试固件与占位资产生成：字面量 + 朴素贪心匹配，不追求压缩率。

class _BitWriter:
    def __init__(self):
        self._bits: list[int] = []

    def bit(self, b: int):
        self._bits.append(b & 1)

    def code(self, value: int):
        k = 0
        while value >= (1 << (k + 2)) - 2:
            k += 1
        base = (1 << (k + 1)) - 2
        w = value - base
        for _ in range(k):
            self.bit(1)
        self.bit(0)
        for i in range(k, -1, -1):
            self.bit((w >> i) & 1)

    def to_bytes(self) -> bytes:
        out = bytearray()
        for i in range(0, len(self._bits), 8):
            byte = 0
            for j, b in enumerate(self._bits[i : i + 8]):
                byte |= b << (7 - j)
            out.append(byte)
        return bytes(out)


def encode(chunks: list[bytes], magic: bytes = b"LS11") -> bytes:
    """把若干原始块打包为合法容器（identity 字典，仅字面量编码）。"""
    if magic not in MAGICS:
        raise LS11Error(f"bad magic {magic!r}")
    dictionary = bytes(range(256))
    streams = []
    for chunk in chunks:
        if not chunk:
            # 空块的压缩流为 0 字节，其 compressed_size 字段会与条目表的
            # 0 终止符冲突，使 parse_header 提前结束、静默丢弃该块及其后所有块。
            # 原版格式本身无法无歧义地表达空块，故直接拒绝而非产出损坏容器。
            raise LS11Error("cannot encode an empty chunk (collides with table terminator)")
        w = _BitWriter()
        for b in chunk:
            w.code(b)
        streams.append(w.to_bytes())
    table_size = 12 * len(chunks) + 4
    data_start = TABLE_OFFSET + table_size
    out = bytearray()
    out += magic + b"\x00" * (HEADER_SIZE - 4)
    out += dictionary
    off = data_start
    for chunk, stream in zip(chunks, streams):
        out += struct.pack(">III", len(stream), len(chunk), off)
        off += len(stream)
    out += b"\x00" * 4
    for stream in streams:
        out += stream
    return bytes(out)
