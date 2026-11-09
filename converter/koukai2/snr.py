"""SNDT 剧本容器解析 + SNR 字节码普查（M1 的「数据层排雷」交付物）。

容器格式（自主逆向并对全部 7 个原档验证，见 docs/koukai2-docs/07 §7.1、08 §8.1）：
  0x00  "SNDT"
  0x04  BE16 剧本号（SNR1–6 = 0..5，SNR0 = 0x80）
  0x10  BE32 分节偏移表，0xFFFFFFFF 终止（分节数：SNR0=13、SNR1=6…实测吻合）
  之后  各分节字节码（节内还有「事件号→偏移」跳转表，反汇编/转译见 snr_transpile.py）

普查（census）只做**字节扫描**，不做完整反汇编——因为多数操作码语义/长度未知。
方法复现了已验证事实：统计载荷区字节频率（指令直方图）；对 C8/CC 读其后 BE16 操作数。
实证：SNR1 含 1174 个 C8 字节、操作数 99.4% 落在 [0,1176)（=MES 台词数）；
CC 操作数 99.2% 落在 [0,256)（=KAO 头像号上界）。语义实现是 M12 的工作。
"""
from __future__ import annotations

import struct
from dataclasses import dataclass

MAGIC = b"SNDT"
SCENARIO_ID_OFFSET = 4
SECTION_TABLE_OFFSET = 0x10
SECTION_TERMINATOR = 0xFFFFFFFF

# 操作码元数据。C8/CC/C7 已验证；其余为试探（tentative），仅做计数普查，语义待 M12。
_OPERAND_LEN = {0xC8: 2, 0xCC: 2, 0xC7: 0, 0xC0: 1, 0xAC: 3, 0xAD: 3}
_OPCODE_NAMES = {
    0xC8: "show_mes", 0xCC: "set_portrait", 0xC7: "wait_key",
    0xC0: "window_ctl", 0xAC: "cond_a", 0xAD: "cond_b",
}
_TENTATIVE = {0xC0, 0xAC, 0xAD}
# 普查报告里给出操作数范围的操作码（操作数语义已验证、读 BE16）
_OPERAND_RANGE_HI = {0xC8: "mes_line_count", 0xCC: 256}


class SnrError(ValueError):
    pass


@dataclass(frozen=True)
class SnrContainer:
    scenario_id: int
    sections: list[tuple[int, int]]  # 各分节的 [start, end) 文件内字节范围
    file_size: int

    @property
    def section_count(self) -> int:
        return len(self.sections)

    @property
    def payload_start(self) -> int:
        return self.sections[0][0] if self.sections else self.file_size


def parse_container(data: bytes) -> SnrContainer:
    if len(data) < SECTION_TABLE_OFFSET + 4:
        raise SnrError("file too small for SNDT header")
    if data[:4] != MAGIC:
        raise SnrError(f"bad magic {data[:4]!r}")
    scenario_id = struct.unpack(">H", data[SCENARIO_ID_OFFSET : SCENARIO_ID_OFFSET + 2])[0]

    offsets: list[int] = []
    p = SECTION_TABLE_OFFSET
    while True:
        if p + 4 > len(data):
            raise SnrError("unterminated section offset table")
        (v,) = struct.unpack(">I", data[p : p + 4])
        p += 4
        if v == SECTION_TERMINATOR:
            break
        if v > len(data):
            raise SnrError(f"section offset {v} past end of file")
        if offsets and v < offsets[-1]:
            raise SnrError("section offsets not ascending")
        offsets.append(v)

    sections = [
        (offsets[i], offsets[i + 1] if i + 1 < len(offsets) else len(data))
        for i in range(len(offsets))
    ]
    return SnrContainer(scenario_id, sections, len(data))


def static_walk(region: bytes) -> dict:
    """尽力而为的线性遍历：已知操作码按长度推进，未知操作码退化为 +1 字节并记录。

    仅用于「静态遍历不崩」验证——未知操作码会导致与真实指令边界失步，
    故得到的不是精确反汇编，只证明遍历对任意输入都能有界终止、不抛异常。
    """
    pos = 0
    n = len(region)
    unknown: set[int] = set()
    steps = 0
    while pos < n:
        op = region[pos]
        if op in _OPERAND_LEN:
            pos += 1 + _OPERAND_LEN[op]
        else:
            unknown.add(op)
            pos += 1
        steps += 1
    return {"steps": steps, "consumed": pos, "unknown_opcodes": sorted(unknown)}


def _opcode_stats(region: bytes, opcode: int, mes_line_count: int | None) -> dict:
    operand_len = _OPERAND_LEN.get(opcode, 0)
    count = 0
    operands: list[int] = []
    for i, b in enumerate(region):
        if b != opcode:
            continue
        count += 1
        if operand_len == 2 and i + 3 <= len(region):  # 读 BE16 操作数
            operands.append(struct.unpack(">H", region[i + 1 : i + 3])[0])

    stat: dict = {"name": _OPCODE_NAMES.get(opcode, f"op_{opcode:02X}"), "count": count}
    if opcode in _TENTATIVE:
        stat["tentative"] = True
    if opcode in _OPERAND_RANGE_HI:
        stat["operand_endian"] = "big"
        stat["operand_min"] = min(operands) if operands else None
        stat["operand_max"] = max(operands) if operands else None
        hi = mes_line_count if _OPERAND_RANGE_HI[opcode] == "mes_line_count" else _OPERAND_RANGE_HI[opcode]
        stat["in_range_hi"] = hi
        if hi is not None and operands:
            stat["in_range_count"] = sum(0 <= v < hi for v in operands)
        else:
            stat["in_range_count"] = None
    return stat


def census(data: bytes, mes_line_count: int | None = None) -> dict:
    """对 SNR 容器做字节级普查，返回 JSON 可序列化的报告。"""
    c = parse_container(data)
    region = data[c.payload_start :]

    histogram = {f"{b:02x}": 0 for b in set(region)}
    for b in region:
        histogram[f"{b:02x}"] += 1

    opcodes = {
        f"{op:02X}": _opcode_stats(region, op, mes_line_count)
        for op in sorted(_OPERAND_LEN)
    }

    report = {
        "scenario_id": c.scenario_id,
        "file_size": c.file_size,
        "section_count": c.section_count,
        "sections": [list(s) for s in c.sections],
        "payload_start": c.payload_start,
        "mes_lines": mes_line_count,
        "opcodes": opcodes,
        "histogram": histogram,
        "static_walk": static_walk(region),
    }
    if mes_line_count is not None:
        report["c8_vs_mes_lines"] = {
            "c8": opcodes["C8"]["count"],
            "mes": mes_line_count,
            "delta": opcodes["C8"]["count"] - mes_line_count,
        }
    return report
