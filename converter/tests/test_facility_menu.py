"""交叉校验人工表 godot/data/facilities.json 的 menu_index ↔ MENU.DAT 真实菜单。

每个设施的 menu_index 指向 MENU.DAT（→ text/menu.json）中的某一组；本测试解码 MENU.DAT，
断言该组解码后的标签含该设施应有的特征词（据 docs/08 §8.3 实机菜单）。这把「哪个菜单组属于
哪个设施」钉死，供 Godot 侧 FacilityScene 据 menu_index 取真实菜单。

固件层：校验人工表结构自洽（每个 menu_index 在 [0,61) 且各异）。
原版档层（skip-if-missing）：解码真 MENU.DAT，断言各组特征标签。
"""
import hashlib
import json
import os
from pathlib import Path

import pytest

from koukai2 import text_decode, text_table

HAND_FILE = Path(__file__).resolve().parents[2] / "godot" / "data" / "facilities.json"


def _hand():
    return json.loads(HAND_FILE.read_text(encoding="utf-8"))["facilities"]


def test_menu_index_present_unique_and_in_range():
    fac = _hand()
    idx = [f["menu_index"] for f in fac]
    assert all(isinstance(i, int) for i in idx), "每个设施都应有整数 menu_index"
    assert all(0 <= i < 61 for i in idx), "menu_index 应落在 MENU.DAT 的 [0,61) 内"
    assert len(set(idx)) == len(idx), "不同设施不应共用同一菜单组"


GAMEDIR = os.environ.get("KOUKAI2_DIR", "")
needs_game = pytest.mark.skipif(
    not (GAMEDIR and Path(GAMEDIR).is_dir()),
    reason="set KOUKAI2_DIR to the original game directory",
)

# 每个设施 key → 其菜单组应含的特征项（SHA-256 前 16 位；原文不入库）。据 docs/08 §8.3 实机菜单。
_EXPECTED = {
    "market":         ["3720ce1a1dcfff34", "eb37a03e1f2a1832", "c927da3e98b8a834", "cb2c295e7a4b2053"],
    "shipyard":       ["f9abb6adb0521d33", "a0b0db2e55b8efc7", "04d8b58553e0b8f3", "2772d4e316ec8850"],
    "harbor":         ["86bfae74159bf9a3", "8d83c4ab5baddd55", "7743b4a035d4e43b"],
    "inn":            ["6edef1feba2178a3"],
    "palace":         ["9b2afdc9c74b808d", "a82108121bafe3ba"],
    "bank":           ["759472586f5c20b5", "8525c4925e7ace01", "f8c8473642040cf8", "ea64c6c8d00a0efd"],
    "item_shop":      ["3720ce1a1dcfff34", "eb37a03e1f2a1832"],
    "guild":          ["c48e2e4ee8a6f20d", "409b70ea8e1b8a1d"],
    "church":         ["1d3473614976f1dd", "45235cf6eeb0cc9e"],
    "fortune_teller": ["118a06bba63ee1c2", "00c232c0266b7ab0", "e30dd94de31e35bf", "9fd01daf9d710169"],
    # tavern / armory 为高置信推断（待实机终验），特征词较宽松
    "tavern":         ["fbc7afb3cab15e2f"],
    "armory":         ["63f77a635db07273"],
}


@needs_game
def test_menu_index_groups_decode_to_expected_labels():
    recs = text_table.parse_records((Path(GAMEDIR) / "MENU.DAT").read_bytes(), 2)
    groups = [text_decode.decode(r).replace("　", "").replace(" ", "") for r in recs]
    assert len(groups) == 61
    by_key = {f["key"]: f for f in _hand()}
    for key, needles in _EXPECTED.items():
        items = groups[by_key[key]["menu_index"]].split("\n")
        hashes = {hashlib.sha256(i.encode()).hexdigest()[:16] for i in items}
        for n in needles:
            assert n in hashes, f"{key} 菜单组 #{by_key[key]['menu_index']} 缺特征项 {n}：{items!r}"
