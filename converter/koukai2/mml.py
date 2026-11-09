"""D2.MML —— 乐曲数据头部偏移表解析（小端 u16）。

格式（见 docs/koukai2-docs/06 §6.2）：文件头是小端 u16 偏移表，按「若干声道偏移 + 0 终止」
为一组（一组=一曲），各偏移指向编译后的 MML 字节码流（数据区从第一个偏移处开始）。

⚠ 破解状态（实测 27866B 原档）：干净的「升序、在数据区内的声道偏移 + 0」模型只在**前 16 曲**
成立（15 曲 4 声道 + 1 曲 3 声道，约止于第 160 字节），其后头部出现 > 文件长度的值，疑为
编译 MML 数据混入或第二段编码，结构尚未吃透。本解析器**只提取已验证的干净前缀并标记
partial=True**，绝不臆造其余部分；完整解码（含 MML 字节码语义）留待 M14 由播放需求拉动。
"""
from __future__ import annotations

import struct


class MmlError(ValueError):
    pass


def parse_header(data: bytes) -> dict:
    """解析 D2.MML 头部偏移表的干净前缀，返回 JSON 可序列化的报告。"""
    if len(data) < 2:
        raise MmlError("file too small for MML offset table")
    data_start = struct.unpack("<H", data[:2])[0]
    if data_start == 0 or data_start % 2 != 0 or data_start > len(data):
        raise MmlError(f"implausible data-start offset {data_start}")

    n_u16 = data_start // 2  # 表区占据 [0, data_start)
    vals = [struct.unpack("<H", data[i * 2 : i * 2 + 2])[0] for i in range(n_u16)]

    tracks: list[list[int]] = []
    i = 0
    partial = False
    while i < n_u16:
        group: list[int] = []
        while i < n_u16 and vals[i] != 0:
            group.append(vals[i])
            i += 1
        terminated = i < n_u16 and vals[i] == 0
        valid = (
            bool(group)
            and all(data_start <= o < len(data) for o in group)  # 在数据区内
            and group == sorted(group)                            # 组内升序
            and len(set(group)) == len(group)                     # 无重复
        )
        if terminated and valid:
            tracks.append(group)
            i += 1  # 吃掉 0 终止符
        else:
            partial = True  # 干净前缀到此为止，其后结构未明
            break

    return {
        "data_start": data_start,
        "track_count_clean": len(tracks),
        "channels_per_track": [len(t) for t in tracks],
        "tracks": tracks,
        "partial": partial,
        "stopped_at_u16": i,
        "note": "only the verified clean prefix is parsed; remainder of the header is not yet cracked (see M14)"
        if partial
        else None,
    }
