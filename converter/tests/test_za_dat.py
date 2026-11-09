"""ZA_DAT.DAT（设施入口坐标表）解析测试。

格式（已验证，见 docs/koukai2-docs/08-剧本对话与港口建筑.md §8.3、05 §5.2）：
  2424 B = 101 港 × 24 B；每港 12 个 (x,y) 字节对（设施门口在 96×96 地图上的坐标）。
  FF FF = 该港无此设施；其余坐标全部 < 96。

两层验证：自制固件逐字段比对 + 原版档全量校验（skip-if-missing，需 KOUKAI2_DIR）。
"""
import os
from pathlib import Path

import pytest

from koukai2 import za_dat


# ---------------------------------------------------------------- 固件层 --

def _build(ports: list[list[tuple[int, int] | None]]) -> bytes:
    """把「每港 12 槽」结构编码回 2424 字节（None → FF FF），用于固件测试。"""
    assert len(ports) == za_dat.NUM_PORTS
    buf = bytearray()
    for port in ports:
        assert len(port) == za_dat.SLOTS_PER_PORT
        for slot in port:
            if slot is None:
                buf += b"\xff\xff"
            else:
                buf += bytes(slot)
    return bytes(buf)


def _blank_ports() -> list[list[tuple[int, int] | None]]:
    return [[None] * za_dat.SLOTS_PER_PORT for _ in range(za_dat.NUM_PORTS)]


def test_rejects_wrong_size():
    with pytest.raises(za_dat.ZADatError):
        za_dat.parse(b"\x00" * 100)


def test_port_and_slot_counts():
    ports = za_dat.parse(_build(_blank_ports()))
    assert len(ports) == za_dat.NUM_PORTS
    assert all(len(p) == za_dat.SLOTS_PER_PORT for p in ports)


def test_absent_marker_is_none():
    data = _build(_blank_ports())
    assert za_dat.parse(data)[0][0] is None


def test_present_coordinates_parsed():
    ports = _blank_ports()
    ports[0][0] = (10, 20)
    ports[100][11] = (95, 0)
    parsed = za_dat.parse(_build(ports))
    assert parsed[0][0] == za_dat.Facility(10, 20)
    assert parsed[100][11] == za_dat.Facility(95, 0)


def test_out_of_range_coordinate_rejected():
    """非 FF FF 的坐标必须 < 96（已验证不变量）；越界视为损坏输入。"""
    ports = _blank_ports()
    ports[0][0] = (96, 0)  # x == 96 越界
    with pytest.raises(za_dat.ZADatError):
        za_dat.parse(_build(ports))


def test_partial_ff_is_not_absent_and_rejected():
    """半个 FF（x=FF,y=合法）不是缺席标记，FF=255 越界 → 报错，避免静默误判。"""
    data = bytearray(_build(_blank_ports()))
    data[0] = 0xFF
    data[1] = 0x05  # y 合法但 x=0xFF
    with pytest.raises(za_dat.ZADatError):
        za_dat.parse(bytes(data))


def test_to_json_obj_roundtrips_shape():
    ports = _blank_ports()
    ports[3][2] = (1, 2)
    obj = za_dat.to_json_obj(za_dat.parse(_build(ports)))
    assert len(obj) == za_dat.NUM_PORTS
    assert obj[3][2] == {"x": 1, "y": 2}
    assert obj[0][0] is None


# ------------------------------------------------------------- 原版档层 --

GAMEDIR = os.environ.get("KOUKAI2_DIR", "")
needs_game = pytest.mark.skipif(
    not (GAMEDIR and Path(GAMEDIR).is_dir()),
    reason="set KOUKAI2_DIR to the original game directory",
)


@needs_game
def test_original_za_dat_invariants():
    data = (Path(GAMEDIR) / "ZA_DAT.DAT").read_bytes()
    assert len(data) == za_dat.FILE_SIZE  # 2424
    ports = za_dat.parse(data)
    assert len(ports) == za_dat.NUM_PORTS
    # 所有登记的设施坐标都落在 96×96 地图内
    for port in ports:
        for fac in port:
            if fac is not None:
                assert 0 <= fac.x < 96 and 0 <= fac.y < 96
    # 现实数据里既有缺席（FF FF）也有在场的设施
    flat = [fac for port in ports for fac in port]
    assert any(f is None for f in flat)
    assert any(f is not None for f in flat)
