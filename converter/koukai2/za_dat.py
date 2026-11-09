"""ZA_DAT.DAT —— 港口设施入口坐标表解析（ZA = 日文「座標」）。

格式（自主逆向并验证，规格见 docs/koukai2-docs/08-剧本对话与港口建筑.md §8.3）：
  原始未压缩文件，2424 B = 101 港 × 24 B。
  每港 12 个槽位，每槽 2 字节 (x, y) = 设施门口在 96×96 港口图块地图上的坐标。
  FF FF = 该港没有这个设施；其余坐标全部 < 96（已对原版全量验证）。
  12 个槽位按固定顺序对应固定设施（港务局/交易所/造船所/酒馆/旅馆/银行…），
  但槽位↔设施的精确映射由玩法里程碑（M4）拉动，此处只做结构化坐标解析。
"""
from __future__ import annotations

from dataclasses import dataclass

NUM_PORTS = 101
SLOTS_PER_PORT = 12
RECORD_SIZE = SLOTS_PER_PORT * 2  # 每港 24 字节
FILE_SIZE = NUM_PORTS * RECORD_SIZE  # 2424
MAP_SIZE = 96  # 港口地图 96×96，合法坐标 < 96
ABSENT = (0xFF, 0xFF)  # FF FF = 设施不存在


@dataclass(frozen=True)
class Facility:
    x: int
    y: int


# 每港 12 个槽位，每槽是 Facility 或 None（缺席）
Port = list[Facility | None]


class ZADatError(ValueError):
    pass


def parse(data: bytes) -> list[Port]:
    """把 ZA_DAT.DAT 字节解析为 101 港 × 12 槽的坐标结构。"""
    if len(data) != FILE_SIZE:
        raise ZADatError(
            f"expected {FILE_SIZE} bytes ({NUM_PORTS}×{RECORD_SIZE}), got {len(data)}"
        )
    ports: list[Port] = []
    pos = 0
    for port_i in range(NUM_PORTS):
        port: Port = []
        for slot_i in range(SLOTS_PER_PORT):
            x, y = data[pos], data[pos + 1]
            pos += 2
            if (x, y) == ABSENT:
                port.append(None)
                continue
            if x >= MAP_SIZE or y >= MAP_SIZE:
                raise ZADatError(
                    f"port {port_i} slot {slot_i}: coordinate ({x},{y}) "
                    f"out of 0..{MAP_SIZE - 1} and not the FF FF absent marker"
                )
            port.append(Facility(x, y))
        ports.append(port)
    return ports


def to_json_obj(ports: list[Port]) -> list[list[dict | None]]:
    """转为 JSON 可序列化结构：缺席槽为 null，在场槽为 {"x":..,"y":..}。"""
    return [
        [None if fac is None else {"x": fac.x, "y": fac.y} for fac in port]
        for port in ports
    ]
