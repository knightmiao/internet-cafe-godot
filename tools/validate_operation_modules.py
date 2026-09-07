#!/usr/bin/env python3
"""校验右侧操作区三态规则、八模块目录与模块图标。"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "godot/data/operation_modules.json"
EXPECTED_MODULES = [
    "finance", "staff", "equipment", "procurement",
    "strategy", "dining", "construction", "cat",
]
EXPECTED_PHASES = ["closed", "open", "closing"]


def load_and_validate() -> dict:
    data = json.loads(DATA.read_text(encoding="utf-8"))
    assert [phase["id"] for phase in data["phases"]] == EXPECTED_PHASES
    assert [module["id"] for module in data["modules"]] == EXPECTED_MODULES
    assert all(len(phase["secondary"]) == 2 for phase in data["phases"])
    assert all(len(module["sections"]) == 4 for module in data["modules"])
    ids = [
        f"{module['id']}/{section['id']}"
        for module in data["modules"]
        for section in module["sections"]
    ]
    assert len(ids) == len(set(ids)) == 32
    assert all(len(module["label"]) == 2 for module in data["modules"])
    return data


def validate_icons(data: dict) -> None:
    for module in data["modules"]:
        path = ROOT / "godot/assets/ui/icons" / f"{module['icon']}.png"
        assert path.exists(), f"缺少模块图标：{path}"
        image = Image.open(path).convert("RGBA")
        assert image.size == (10, 10), f"{path.name} 尺寸错误：{image.size}"
        assert image.getchannel("A").getextrema() == (0, 255)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-only", action="store_true")
    args = parser.parse_args()
    data = load_and_validate()
    if not args.data_only:
        validate_icons(data)
    print("validated 三种营业状态、八个模块与 32 个一级入口")


if __name__ == "__main__":
    main()
