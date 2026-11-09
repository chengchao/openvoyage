"""一键转换管线：原版 KOUKAI2 散档 → out_dir/*.json（Godot 侧只消费这些产物）。

用法:
    uv run python -m koukai2.convert <KOUKAI2目录> <输出目录>
    推荐输出到 godot/assets-converted/（工程内 res://，已 gitignore）。之后：
      godot --headless --path godot --import                       # 导入字库 PNG
    重转会先清空 <输出目录>/images/，不留旧产物。

当前覆盖（M1）：
  - 数值/坐标表 → JSON：ZA_DAT、CHIP_NO、WINDCUR
  - 文本偏移表 → JSON（十六进制，编码未解，码表是 M5）：MESSAGE、MENU
  - 14 个 LS10/LS11 容器 → lzw_manifest.json（逐块解压并校验字节数自洽；
    像素→PNG/TileSet 是 M2，故此处只产出清单而非二进制产物）
缺失的文件会被跳过并记入 summary，不报错。
"""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

from . import (
    chip_no, images, ls11, mml, snr, snr_transpile,
    text_decode, text_table, windcur, za_dat,
)

# (源文件名, 输出名, 解析→JSON可序列化对象)
_TABLE_HANDLERS = [
    ("ZA_DAT.DAT", "za_dat.json", lambda d: za_dat.to_json_obj(za_dat.parse(d))),
    ("CHIP_NO.DAT", "chip_no.json", lambda d: chip_no.to_json_obj(chip_no.parse(d))),
    ("MESSAGE.DAT", "message.json", lambda d: text_table.to_json_obj(text_table.parse_records(d, 2))),
    ("MENU.DAT", "menu.json", lambda d: text_table.to_json_obj(text_table.parse_records(d, 2))),
    ("WINDCUR.DAT", "windcur.json", lambda d: windcur.to_json_obj(windcur.parse(d))),
]

# 全部 14 个 LZW 容器（见 docs/05、test_ls11.EXPECTED）
LZW_NAMES = [
    "KAO.LZW", "PORTMAP.LZW", "WORLDMAP.LZW", "PORTCHIP.LZW", "CHAR.LZW",
    "OPGRAPH.LZW", "DATA1.LZW", "IAE1.LZW",
    *[f"IAP{i}.LZW" for i in range(1, 7)],
]


def _write_json(path: Path, obj) -> None:
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=1), encoding="utf-8")


def convert(src_dir, out_dir) -> dict:
    """转换 src_dir 中所有已识别的文件到 out_dir，返回 summary。"""
    src_dir, out_dir = Path(src_dir), Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    summary: dict = {"tables": {}, "lzw": {}, "skipped": []}

    for fname, out_name, parse_fn in _TABLE_HANDLERS:
        path = src_dir / fname
        if not path.exists():
            summary["skipped"].append(fname)
            continue
        obj = parse_fn(path.read_bytes())
        _write_json(out_dir / out_name, obj)
        summary["tables"][fname] = {"out": out_name, "records": len(obj)}

    manifest: dict = {}
    for name in LZW_NAMES:
        path = src_dir / name
        if not path.exists():
            summary["skipped"].append(name)
            continue
        data = path.read_bytes()
        magic, _, entries = ls11.parse_header(data)
        chunks = ls11.decode(data)
        for entry, chunk in zip(entries, chunks):
            if len(chunk) != entry.raw_size:  # 解压字节数必须与头部声明一致
                raise ls11.LS11Error(f"{name}: chunk size {len(chunk)} != declared {entry.raw_size}")
        manifest[name] = {
            "magic": magic.decode("ascii"),
            "chunks": len(chunks),
            "sizes": [len(c) for c in chunks],
        }
    if manifest:
        _write_json(out_dir / "lzw_manifest.json", manifest)
    summary["lzw"] = manifest

    # 字库 → PNG（out/images/font/）。原版头像/图块/精灵/店主画不再转换：游戏用自制美术。
    img_summary: dict = {}
    images_dir = out_dir / "images"
    if images_dir.exists():
        shutil.rmtree(images_dir)  # 清旧产物（含旧版转换留下的原版美术）
    # 点阵字库 1.PAT/2.PAT → 字模图集（M5 文本渲染用）
    for pat, fname in [("1.PAT", "font1"), ("2.PAT", "font2")]:
        if (src_dir / pat).exists():
            rep = images.convert_font((src_dir / pat).read_bytes(), images_dir, fname)
            img_summary[fname + "_glyphs"] = rep["glyphs"]
    summary["images"] = img_summary

    # SNR 字节码普查报告（SNR0–6.DAT，配合 SNRn.MES 的台词数交叉校验）
    census: dict = {}
    for n in range(7):
        dat_path = src_dir / f"SNR{n}.DAT"
        if not dat_path.exists():
            summary["skipped"].append(f"SNR{n}.DAT")
            continue
        mes_path = src_dir / f"SNR{n}.MES"
        mes_lines = None
        if mes_path.exists():
            mes_lines = int.from_bytes(mes_path.read_bytes()[:4], "big") // 4
        dat = dat_path.read_bytes()
        census[f"SNR{n}.DAT"] = snr.census(dat, mes_line_count=mes_lines)
    if census:
        _write_json(out_dir / "snr_census.json", census)
    summary["snr"] = {name: {"c8": rep["opcodes"]["C8"]["count"], "mes": rep["mes_lines"]}
                      for name, rep in census.items()}

    # 文本解码（M5）：自定义双字节码 → Unicode，写到 out/text/*.json（Godot 侧消费）。
    # 用 code_table.json（OCR 自带字库 1.PAT/2.PAT 字模建表）。保留 $n/$s/$r/$d 变量占位。
    # 原始 hex 产物 message.json/menu.json 保持不变（M1 契约）；此处为额外的可读文本层。
    text_summary: dict = {}
    text_dir = out_dir / "text"
    _TEXT_FILES = ["MESSAGE.DAT", "MENU.DAT", "ITEM.MES", *(f"SNR{n}.MES" for n in range(7))]
    for fname in _TEXT_FILES:
        path = src_dir / fname
        if not path.exists():
            summary["skipped"].append(fname)
            continue
        lines = text_decode.decode_file(path.read_bytes(), fname)
        out_name = fname.lower().replace(".dat", "").replace(".mes", "") + ".json"
        text_dir.mkdir(parents=True, exist_ok=True)
        _write_json(text_dir / out_name, lines)
        text_summary[fname] = len(lines)
    summary["text"] = text_summary

    # SNR 事件系统（M5+）：剧本字节码 → events/snrN.json（带标签的命令表脚本）+
    # triggers/index.json（(剧本,章,港,设施)→事件标签）。Godot 侧事件运行器消费这两套。
    # 台词沿用上面的列表式 text/snrN.json（say 的 id 'snrN/k' 即行下标），故 write_text=False。
    # 需 SNRn.DAT 与 SNRn.MES 同时存在；任一缺失则该剧本被 transpile 跳过、不报错。
    if any((src_dir / f"SNR{n}.DAT").exists() and (src_dir / f"SNR{n}.MES").exists()
           for n in range(7)):
        cov = snr_transpile.transpile(str(src_dir), str(out_dir), write_text=False)
        summary["events"] = {fn: c["pct_decoded"] for fn, c in cov.items()}

    # D2.MML 头部偏移表（仅已验证的干净前缀，partial 诊断）
    mml_path = src_dir / "D2.MML"
    if mml_path.exists():
        report = mml.parse_header(mml_path.read_bytes())
        _write_json(out_dir / "mml_header.json", report)
        summary["mml"] = {"clean_tracks": report["track_count_clean"], "partial": report["partial"]}
    else:
        summary["skipped"].append("D2.MML")
        summary["mml"] = {}
    return summary


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 2:
        print("usage: python -m koukai2.convert <KOUKAI2_dir> <out_dir>", file=sys.stderr)
        return 2
    src, out = argv
    if not Path(src).is_dir():
        print(f"error: source directory not found: {src}", file=sys.stderr)
        return 2
    summary = convert(src, out)
    n_tables, n_lzw, n_snr = len(summary["tables"]), len(summary["lzw"]), len(summary["snr"])
    n_skipped = len(summary["skipped"])
    print(f"converted {n_tables} table(s) + {n_lzw} LZW container(s) + {n_snr} SNR census"
          f" -> {out}  (skipped {n_skipped})")
    for fname, info in summary["tables"].items():
        print(f"  {fname:14s} -> {info['out']:16s} ({info['records']} records)")
    for name, info in summary["lzw"].items():
        print(f"  {name:14s} -> lzw_manifest.json ({info['magic']}, {info['chunks']} chunks)")
    for kind, n in summary["images"].items():
        print(f"  {'images':14s} -> images/{kind} ({n})")
    for name, info in summary["snr"].items():
        print(f"  {name:14s} -> snr_census.json   (C8={info['c8']}, MES={info['mes']})")
    for fname, n in summary.get("text", {}).items():
        print(f"  {fname:14s} -> text/            ({n} decoded records)")
    if summary["mml"]:
        m = summary["mml"]
        print(f"  {'D2.MML':14s} -> mml_header.json   ({m['clean_tracks']} clean tracks, partial={m['partial']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
