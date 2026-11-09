"""convert.py 一键转换管线测试：原版散档 → out_dir/*.json。

固件层用自制最小输入跑通管线；原版档层（skip-if-missing）在真目录上端到端跑一遍。
"""
import hashlib
import json
import os
import struct
from pathlib import Path

import pytest

from koukai2 import convert, ls11, snr


def _write(p: Path, data: bytes):
    p.write_bytes(data)


def _build_text_table(records: list[bytes], width: int = 2) -> bytes:
    table_size = len(records) * width
    offsets, body, off = [], bytearray(), table_size
    for rec in records:
        offsets.append(off)
        chunk = rec + b"\x00"
        body += chunk
        off += len(chunk)
    return b"".join(o.to_bytes(width, "big") for o in offsets) + bytes(body)


def _make_src(tmp: Path) -> Path:
    src = tmp / "KOUKAI2"
    src.mkdir()
    # ZA_DAT：全缺席，只在 port0 slot0 放 (10,20)
    za = bytearray(b"\xff" * 2424)
    za[0], za[1] = 10, 20
    _write(src / "ZA_DAT.DAT", bytes(za))
    _write(src / "CHIP_NO.DAT", bytes([0, 6, 3]))
    _write(src / "MESSAGE.DAT", _build_text_table([b"AB", b""], 2))
    _write(src / "WINDCUR.DAT", bytes(windcur_blob()))
    # 原版美术容器照常列入 lzw_manifest，但不再转成 PNG（游戏用自制美术）
    _write(src / "MAIN.EXE", bytes(16))
    _write(src / "KAO.LZW", ls11.encode([bytes(1920), bytes(864)]))
    _write(src / "PORTCHIP.LZW", ls11.encode([bytes(30720), bytes([0, 29, 34, 40])]))
    _write(src / "PORTMAP.LZW", ls11.encode([bytes(9216), bytes(9216)]))  # 2 港
    _write(src / "1.PAT", bytes(32 * 3))  # 3 个字模
    # 一个最小 SNDT 容器 + 配套 MES（台词数=10）：分节含合规头块(0004 FFFF)+事件表(事件0→偏移8)+字节码
    _snr_section = b"\x00\x04\xff\xff" + b"\x00\x00\x00\x08" + b"\xff\xff\xff\xff" + b"\xc8\x00\x05\xc7"
    _write(src / "SNR0.DAT", _build_snr(0x80, [_snr_section]))
    _write(src / "SNR0.MES", _build_text_table([b""] * 10, 4))
    # D2.MML：一个干净前缀（2 曲）
    _write(src / "D2.MML", struct.pack("<HHHHH", 10, 14, 0, 12, 0) + b"\x00" * 64)
    return src


def _build_snr(scenario_id: int, sections: list[bytes]) -> bytes:
    header = snr.MAGIC + scenario_id.to_bytes(2, "big")
    header += b"\x00" * (snr.SECTION_TABLE_OFFSET - len(header))
    off = snr.SECTION_TABLE_OFFSET + (len(sections) + 1) * 4
    offsets = []
    for s in sections:
        offsets.append(off)
        off += len(s)
    table = b"".join(o.to_bytes(4, "big") for o in offsets) + b"\xff\xff\xff\xff"
    return header + table + b"".join(sections)


def windcur_blob() -> bytes:
    return bytes(1350)


def test_convert_writes_expected_json(tmp_path):
    src = _make_src(tmp_path)
    out = tmp_path / "out"
    summary = convert.convert(src, out)

    za = json.loads((out / "za_dat.json").read_text())
    assert len(za) == 101 and za[0][0] == {"x": 10, "y": 20}

    assert json.loads((out / "chip_no.json").read_text()) == [0, 6, 3]
    assert json.loads((out / "message.json").read_text()) == ["4142", ""]  # 原始 hex 层（M1）
    assert len(json.loads((out / "windcur.json").read_text())) == 1350

    # 文本解码层（M5）：MESSAGE 'AB' 为半角 ASCII 原样解码；SNR0.MES 10 条空串
    assert json.loads((out / "text" / "message.json").read_text()) == ["AB", ""]
    assert json.loads((out / "text" / "snr0.json").read_text()) == [""] * 10
    assert summary["text"]["MESSAGE.DAT"] == 2 and summary["text"]["SNR0.MES"] == 10

    manifest = json.loads((out / "lzw_manifest.json").read_text())
    assert manifest["KAO.LZW"]["magic"] == "LS11"
    assert manifest["KAO.LZW"]["chunks"] == 2
    assert manifest["KAO.LZW"]["sizes"] == [1920, 864]

    # 图像产物只剩字库；原版美术（头像/图块/港图/精灵/店主画）一律不产出
    assert summary["images"] == {"font1_glyphs": 3}
    assert sorted(p.name for p in (out / "images").iterdir()) == ["font"]

    census = json.loads((out / "snr_census.json").read_text())
    assert census["SNR0.DAT"]["scenario_id"] == 0x80
    assert census["SNR0.DAT"]["opcodes"]["C8"]["count"] == 1
    assert census["SNR0.DAT"]["mes_lines"] == 10

    # 事件系统产物（M5+）：events/snr0.json 命令表 + triggers/index.json。
    # write_text=False，故不覆盖列表式 text/snr0.json。
    events = json.loads((out / "events" / "snr0.json").read_text())
    assert events["scenario"] == 0
    ch0 = events["chapters"][0]
    assert ch0["entries"][0]["trigger_id"] == "0000"
    entry_label = ch0["entries"][0]["label"]
    ops = [c.get("op") for c in ch0["script"] if "op" in c]
    assert "say" in ops and "wait" in ops
    say = next(c for c in ch0["script"] if c.get("op") == "say")
    assert say["text"] == "snr0/5"   # C8 00 05 → 第 5 条台词
    triggers = json.loads((out / "triggers" / "index.json").read_text())
    assert any(t["event"] == f"snr0/c0/{entry_label}" for t in triggers)
    assert summary["events"]["SNR0"] > 0   # 有解码覆盖率
    # text/snr0.json 仍是列表式（say 的 id 'snr0/k' 即行下标）
    assert json.loads((out / "text" / "snr0.json").read_text()) == [""] * 10

    mml_rep = json.loads((out / "mml_header.json").read_text())
    assert mml_rep["track_count_clean"] == 2 and mml_rep["partial"] is False

    assert "ZA_DAT.DAT" in summary["tables"]
    assert "KAO.LZW" in summary["lzw"]
    assert "SNR0.DAT" in summary["snr"]
    assert summary["mml"]["clean_tracks"] == 2


def test_convert_cleans_stale_images(tmp_path):
    src = _make_src(tmp_path)
    out = tmp_path / "out"
    stale = out / "images" / "char" / "stale.png"
    stale.parent.mkdir(parents=True)
    stale.write_bytes(b"old")
    convert.convert(src, out)
    assert not stale.exists(), "旧产物应在重转时被清除"
    assert (out / "images" / "font" / "font1.png").exists(), "真产物仍在"


def test_convert_skips_missing_files(tmp_path):
    src = tmp_path / "KOUKAI2"
    src.mkdir()
    _write(src / "CHIP_NO.DAT", bytes([1, 2, 3]))
    out = tmp_path / "out"
    summary = convert.convert(src, out)
    assert (out / "chip_no.json").exists()
    assert not (out / "za_dat.json").exists()
    assert not (out / "lzw_manifest.json").exists()  # 无 LZW → 不产出清单
    assert "ZA_DAT.DAT" in summary["skipped"]


GAMEDIR = os.environ.get("KOUKAI2_DIR", "")
needs_game = pytest.mark.skipif(
    not (GAMEDIR and Path(GAMEDIR).is_dir()),
    reason="set KOUKAI2_DIR to the original game directory",
)


@needs_game
def test_convert_original_end_to_end(tmp_path):
    out = tmp_path / "out"
    summary = convert.convert(GAMEDIR, out)
    # 表格输出
    assert len(json.loads((out / "za_dat.json").read_text())) == 101
    assert len(json.loads((out / "message.json").read_text())) == 1022
    assert len(json.loads((out / "menu.json").read_text())) == 61
    # 文本解码层（M5）：全部 MES/MENU/ITEM → text/*.json，已知明文命中
    snr1_text = json.loads((out / "text" / "snr1.json").read_text())
    assert len(snr1_text) == 1176 and hashlib.sha256(snr1_text[0][:snr1_text[0].index("〕") + 1].encode()).hexdigest() == "ac41bcb354761e69b3f55dcde8388124038b47ee4a4c1a2c79c728e9524a98b9"
    assert len(json.loads((out / "text" / "message.json").read_text())) == 1022
    menu_text = json.loads((out / "text" / "menu.json").read_text())
    assert len(menu_text) == 61 and "工作介紹" in "\n".join(menu_text)
    assert any("武器" in it for it in json.loads((out / "text" / "item.json").read_text()))
    assert summary["text"]["SNR1.MES"] == 1176
    assert len(json.loads((out / "chip_no.json").read_text())) == 100
    assert len(json.loads((out / "windcur.json").read_text())) == 1350
    # 全部 14 个 LZW 容器逐块解压且字节数自洽
    manifest = json.loads((out / "lzw_manifest.json").read_text())
    assert len(manifest) == 14
    total_chunks = sum(m["chunks"] for m in manifest.values())
    assert total_chunks > 500  # 计划所述 ~560 块
    # SNR 普查覆盖全部 7 个剧本，C8 计数与 MES 台词数大致吻合
    census = json.loads((out / "snr_census.json").read_text())
    assert len(census) == 7
    assert census["SNR1.DAT"]["opcodes"]["C8"]["count"] == 1174
    assert census["SNR1.DAT"]["mes_lines"] == 1176
    # 事件系统（M5+）：SNR1 João 第 0 章「公爵府」入口（设施 house，港 0=里斯本）
    # 及其首句台词序列。triggers 引用全部可解析。
    snr1_ev = json.loads((out / "events" / "snr1.json").read_text())
    assert snr1_ev["home_port"] == 0
    ch0 = snr1_ev["chapters"][0]
    house = next(e for e in ch0["entries"] if e["facility"] == "house" and e["port"] == 0)
    # 从 house 入口标签起，首句台词应是管家挡门那句（说话人前缀按哈希比对，原文不入库）
    labels = {c["label"]: i for i, c in enumerate(ch0["script"]) if "label" in c}
    first_say = next(c for c in ch0["script"][labels[house["label"]]:] if c.get("op") == "say")
    first_line = snr1_text[int(first_say["text"].split("/")[1])]
    assert hashlib.sha256(first_line[:first_line.index("〕") + 1].encode()).hexdigest() == "ac41bcb354761e69b3f55dcde8388124038b47ee4a4c1a2c79c728e9524a98b9"
    # 主线解码覆盖率（演出尾部以 raw 保留）
    assert summary["events"]["SNR1"] >= 60.0
    triggers = json.loads((out / "triggers" / "index.json").read_text())
    by_ch = {}
    for t in triggers:
        by_ch.setdefault((t["scenario"], t["chapter"]), set())
    for n in range(7):
        ev = json.loads((out / "events" / f"snr{n}.json").read_text())
        for ch in ev["chapters"]:
            by_ch[(n, ch["index"])] = {c["label"] for c in ch["script"] if "label" in c}
    for t in triggers:
        _, ck, lab = t["event"].split("/")
        assert lab in by_ch[(t["scenario"], int(ck[1:]))]
    # D2.MML 干净前缀（16 曲）
    mml_rep = json.loads((out / "mml_header.json").read_text())
    assert mml_rep["track_count_clean"] == 16 and mml_rep["partial"] is True
    # 原版美术不再转换：images/ 只有字库
    assert sorted(p.name for p in (out / "images").iterdir()) == ["font"]
    # 点阵字库：1.PAT=5409、2.PAT=6800 字模图集
    assert summary["images"]["font1_glyphs"] == 5409
    assert summary["images"]["font2_glyphs"] == 6800
    assert (out / "images" / "font" / "font1.png").exists()
