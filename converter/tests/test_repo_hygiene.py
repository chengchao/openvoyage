"""仓库卫生：原版美术不进 repo。图片只允许出现在自制占位包和第三方插件目录里。"""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IMAGE_EXT = {".png", ".bmp", ".gif", ".jpg", ".jpeg", ".pcx", ".webp"}
ALLOWED = ("godot/data/placeholder/", "godot/addons/gut/", "godot/icon.svg")


def tracked_files():
    out = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True).stdout
    return [p for p in out.decode().split("\0") if p]


def test_images_only_in_self_made_or_third_party_dirs():
    stray = [p for p in tracked_files()
             if Path(p).suffix.lower() in IMAGE_EXT and not p.startswith(ALLOWED)]
    assert stray == [], f"图片只能放在 {ALLOWED}（原版美术不入库）：{stray}"
