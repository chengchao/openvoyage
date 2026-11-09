#!/usr/bin/env python3
"""把 godot/data/{facilities,facility_actions}.json 渲染进 docs/wiki.html。

wiki 是数据的「呈现层」，不是又一份手抄表——本脚本把真相源（人工维护的两份 JSON）渲染成
HTML 片段，注入 wiki.html 中以标记界定的区段，使其可重复运行、与数据同步。

用法：python3 tools/gen_wiki.py        # 就地更新 docs/wiki.html
      python3 tools/gen_wiki.py --check  # 只校验是否已是最新（CI 用，过期则非零退出）
"""
from __future__ import annotations

import argparse
import html
import json
import sys
from pathlib import Path

esc = html.escape

ROOT = Path(__file__).resolve().parents[1]
FACILITIES = ROOT / "godot" / "data" / "facilities.json"
ACTIONS = ROOT / "godot" / "data" / "facility_actions.json"
PROSE = ROOT / "docs" / "wiki_data" / "facilities_prose.json"
DIALOGUE_MAP = ROOT / "docs" / "wiki_data" / "facility_dialogue.json"
WIKI = ROOT / "docs" / "wiki.html"

# 本地转换产物（gitignore）：店主台词文本来源；缺失（CI/clone）时跳过 sidecar 生成。
MESSAGE_JSON = ROOT / "godot" / "assets-converted" / "text" / "message.json"
# gitignore 的 sidecar：唯一含原版台词文本的产物，wiki 本地加载，永不入库。
DIALOGUE_SIDECAR = ROOT / "docs" / "wiki_data" / "_dialogue.local.js"

START = "<!-- GEN:facilities:start -->"
END = "<!-- GEN:facilities:end -->"

def render_rows() -> str:
    """合并三源渲染单一设施表行：原版事实(facilities.json) + 菜单项(facility_actions.json)
    + 玩家向文案(facilities_prose.json)。按 facilities.json 的 slot 顺序。"""
    facilities = json.loads(FACILITIES.read_text(encoding="utf-8"))["facilities"]
    actions = json.loads(ACTIONS.read_text(encoding="utf-8"))["facilities"]
    prose = json.loads(PROSE.read_text(encoding="utf-8"))["prose"]
    lines = []
    for f in facilities:  # slot 顺序
        key, name = f["key"], f["name"]
        rows = actions.get(key, [])
        p = prose.get(key, {})
        chips = "".join(f'<span class="act">{esc(r["action"])}</span>' for r in rows)  # 原版菜单文字不入库
        seal = (
            f'<span class="seal-badge {esc(p.get("seal_class", ""))}">{esc(p["seal"])}</span>'
            if p.get("seal")
            else ""
        )
        lines.append(
            f'            <tr>'
            f'<td class="fname">{esc(name)}</td>'
            f'<td>{esc(p.get("sign", ""))}</td>'
            f'<td><div class="acts">{chips}</div></td>'
            f'<td>{esc(p.get("blurb", ""))}</td>'
            f'<td>{seal}</td>'
            f'</tr>'
        )
    return "\n".join(lines)


def build_dialogue_sidecar() -> str | None:
    """从委托映射(facility_dialogue.json，仅编号) + 本地 message.json(台词文本) + facilities.json(名/序)
    构建 sidecar JS（window.FACILITY_DIALOGUE = [...]，含原版台词）。本地资产缺失则返回 None（不生成）。
    sidecar 是唯一含台词文本的产物，gitignore，永不入库——仓库内只有编号映射。"""
    if not (MESSAGE_JSON.exists() and DIALOGUE_MAP.exists()):
        return None
    messages = json.loads(MESSAGE_JSON.read_text(encoding="utf-8"))
    dmap = json.loads(DIALOGUE_MAP.read_text(encoding="utf-8"))["dialogue"]
    facilities = json.loads(FACILITIES.read_text(encoding="utf-8"))["facilities"]
    out = []
    for f in facilities:  # slot 顺序
        key = f["key"]
        spec = dmap.get(key)
        if not spec:
            continue
        lines = [
            messages[i]
            for i in spec.get("messages", [])
            if 0 <= i < len(messages)
        ]
        out.append({
            "key": key,
            "name": f["name"],
            "confidence": spec.get("confidence", "tentative"),
            "lines": lines,
        })
    payload = json.dumps(out, ensure_ascii=False, indent=1)
    return (
        "// 自动生成（tools/gen_wiki.py）· 含原版 MESSAGE.DAT 解码台词 · gitignore，勿入库。\n"
        f"window.FACILITY_DIALOGUE = {payload};\n"
    )


def build(current: str) -> str:
    i, j = current.find(START), current.find(END)
    if i == -1 or j == -1:
        sys.exit("wiki.html 缺少 GEN:facilities 标记区段")
    head = current[: i + len(START)]
    tail = current[j:]
    return f"{head}\n{render_rows()}\n            {tail}"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只校验是否最新，不写回")
    args = ap.parse_args()

    current = WIKI.read_text(encoding="utf-8")
    updated = build(current)
    if args.check:
        if current != updated:
            sys.exit("docs/wiki.html 设施菜单区段已过期，请运行 `python3 tools/gen_wiki.py`")
        print("wiki.html 设施菜单区段已是最新。")
        return
    if current != updated:
        WIKI.write_text(updated, encoding="utf-8")
        print(f"已更新 {WIKI.relative_to(ROOT)} 的设施菜单区段。")
    else:
        print("无变化。")

    # 店主台词 sidecar（仅本地，含台词文本，gitignore）。
    sidecar = build_dialogue_sidecar()
    if sidecar is None:
        print("跳过店主台词 sidecar：本地缺 message.json 或 facility_dialogue.json。")
    else:
        DIALOGUE_SIDECAR.write_text(sidecar, encoding="utf-8")
        print(f"已写本地店主台词 {DIALOGUE_SIDECAR.relative_to(ROOT)}（gitignore，勿入库）。")


if __name__ == "__main__":
    main()
