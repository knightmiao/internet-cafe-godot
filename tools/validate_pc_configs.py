#!/usr/bin/env python3
"""校验六代机位配置，以及导出后的小图与详情图。"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "godot/data/pc_configs.json"
GENERATIONS = [9, 10, 20, 30, 40, 50]
REQUIRED_FIELDS = {
    "id", "generation", "name", "era", "gpu", "monitor", "pc_case",
    "keyboard_mouse", "desk", "chair", "palette", "performance_score",
    "power_watts", "hourly_rate", "unlock_level", "station_sprite", "portrait",
}


def load_configs() -> list[dict]:
    configs = json.loads(DATA.read_text(encoding="utf-8"))
    assert len(configs) == 6, f"配置数错误：{len(configs)}"
    assert [c["generation"] for c in configs] == GENERATIONS
    assert len({c["id"] for c in configs}) == 6
    assert all(REQUIRED_FIELDS <= c.keys() for c in configs)
    assert [c["unlock_level"] for c in configs] == list(range(1, 7))
    assert all(configs[i]["performance_score"] < configs[i + 1]["performance_score"] for i in range(5))
    assert all(configs[i]["hourly_rate"] < configs[i + 1]["hourly_rate"] for i in range(5))
    return configs


def validate_image(path: Path, size: tuple[int, int]) -> None:
    assert path.exists(), f"缺少素材：{path}"
    image = Image.open(path).convert("RGBA")
    assert image.size == size, f"{path.name} 尺寸为 {image.size}，应为 {size}"
    assert image.getchannel("A").getextrema() == (0, 255), f"{path.name} 透明度异常"


def validate_assets(configs: list[dict]) -> None:
    for config in configs:
        suffix = f"{config['generation']:02d}"
        validate_image(
            ROOT / f"godot/assets/world/stations/station_gen_{suffix}.png",
            (64, 68),
        )
        validate_image(
            ROOT / f"godot/assets/ui/portraits/portrait_pc_gen_{suffix}.png",
            (144, 96),
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-only", action="store_true")
    args = parser.parse_args()
    configs = load_configs()
    if not args.data_only:
        validate_assets(configs)
    print(
        "validated "
        + " / ".join(f"{c['id']} {c['gpu']}" for c in configs)
        + ("（仅数据）" if args.data_only else "（数据与素材）")
    )


if __name__ == "__main__":
    main()
