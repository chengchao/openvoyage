"""校验表驱动设施行为表 godot/data/facility_actions.json。

本表只记录原版事实（菜单项→原语），不含实现进度（status/milestone/blocked_on）——那些是
工程状态，分别由 FacilityActions 解释器（代码里有无该 action 分支）与计划文档持有。供 Godot 侧
FacilityScene 在收到 menu_selected(index, label) 时派发。两层校验：

固件层（无需原档）：表结构自洽——
  · 每条 action 都在受控词表 actions 内，且 kind 合法；
  · 每个设施的 item 序号从 0 连续无空洞；
  · facility key 与 facilities.json 一致。
原版档层（skip-if-missing）：解码真 MENU.DAT，按 facilities.json 的 menu_index 取该组，
  断言解码的第 item 项（去全角空格）的 SHA-256 与本表 label_sha256 逐一相等（原文不入库）——确保表不与解码漂移。
"""
import hashlib
import json
import os
from pathlib import Path

import pytest

from koukai2 import text_decode, text_table

DATA_DIR = Path(__file__).resolve().parents[2] / "godot" / "data"
ACTIONS_FILE = DATA_DIR / "facility_actions.json"
FACILITIES_FILE = DATA_DIR / "facilities.json"

VALID_KIND = {
    "money", "trade", "ship", "crew", "navigation",
    "service", "minigame", "info", "story",
}


def _actions_doc():
    return json.loads(ACTIONS_FILE.read_text(encoding="utf-8"))


def _facilities():
    return json.loads(FACILITIES_FILE.read_text(encoding="utf-8"))["facilities"]


def _strip(s: str) -> str:
    return s.replace("　", "").replace(" ", "")


def test_action_catalog_entries_are_well_formed():
    cat = _actions_doc()["actions"]
    assert cat, "actions 目录不应为空"
    for name, spec in cat.items():
        assert spec.get("kind") in VALID_KIND, f"{name} kind 非法：{spec.get('kind')}"
        assert spec.get("desc"), f"{name} 缺 desc"
        # 工程状态（status/milestone/blocked_on）不应混入原版事实表
        for forbidden in ("status", "milestone", "blocked_on"):
            assert forbidden not in spec, f"{name} 不应含工程状态字段「{forbidden}」"


def test_every_row_action_is_in_catalog():
    doc = _actions_doc()
    cat = doc["actions"]
    for key, rows in doc["facilities"].items():
        for row in rows:
            assert row["action"] in cat, f"{key} item {row['item']} 用了未登记原语「{row['action']}」"


def test_item_indices_are_dense_and_zero_based():
    for key, rows in _actions_doc()["facilities"].items():
        idx = [r["item"] for r in rows]
        assert idx == list(range(len(rows))), f"{key} 的 item 序号应为 0..{len(rows) - 1} 连续：{idx}"


def test_facility_keys_match_facilities_json():
    action_keys = set(_actions_doc()["facilities"].keys())
    facility_keys = {f["key"] for f in _facilities()}
    assert action_keys == facility_keys, (
        f"行为表与 facilities.json 的设施集合不一致："
        f"仅在行为表={action_keys - facility_keys}，仅在 facilities={facility_keys - action_keys}"
    )


GAMEDIR = os.environ.get("KOUKAI2_DIR", "")
needs_game = pytest.mark.skipif(
    not (GAMEDIR and Path(GAMEDIR).is_dir()),
    reason="set KOUKAI2_DIR to the original game directory",
)


@needs_game
def test_row_labels_match_decoded_menu():
    recs = text_table.parse_records((Path(GAMEDIR) / "MENU.DAT").read_bytes(), 2)
    groups = [text_decode.decode(r) for r in recs]
    menu_index = {f["key"]: f["menu_index"] for f in _facilities()}
    for key, rows in _actions_doc()["facilities"].items():
        items = [_strip(x) for x in groups[menu_index[key]].split("\n")]
        for row in rows:
            assert row["item"] < len(items), (
                f"{key} item {row['item']} 超出菜单组 #{menu_index[key]} 的项数 {len(items)}"
            )
            assert hashlib.sha256(items[row["item"]].encode()).hexdigest() == row["label_sha256"], (
                f"{key} item {row['item']} 标签漂移："
                f"解码={items[row['item']]!r} 的哈希与表不符"
            )
