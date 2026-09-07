#!/usr/bin/env python3
"""校验装修目录、双尺寸素材与主题 Tile，并生成总览。"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "godot/data/decor_catalog.json"
PREVIEW = ROOT / "docs/ui/preview/decor_catalog@2x.png"
SKETCH = ROOT / "docs/ui/布局草图-像素风.html"
COUNTS = {"theme": 6, "function": 6, "comfort": 5, "ambience": 4, "service": 3}
REQUIRED = {
    "id", "name", "category", "tags", "price", "unlock_level", "description",
    "scene_size", "scene_asset", "portrait", "theme_floor", "theme_wall",
    "theme_wall_v", "bonuses",
}
BONUSES = {"decor", "clean", "comfort", "reputation", "traffic"}


def res_path(value: str) -> Path:
    assert value.startswith("res://")
    return ROOT / "godot" / value.removeprefix("res://")


def load_catalog() -> list[dict]:
    catalog = json.loads(DATA.read_text(encoding="utf-8"))
    assert len(catalog) == 24
    assert len({item["id"] for item in catalog}) == 24
    assert Counter(item["category"] for item in catalog) == COUNTS
    for item in catalog:
        assert REQUIRED <= item.keys(), f"{item['id']} 字段不完整"
        assert item["tags"] and item["price"] >= 0 and item["unlock_level"] > 0
        assert set(item["bonuses"]) == BONUSES
        assert all(isinstance(value, int) for value in item["bonuses"].values())
    return catalog


def validate_rgba(path: Path, size: tuple[int, int], transparent: bool) -> Image.Image:
    assert path.exists(), f"缺少素材：{path}"
    image = Image.open(path).convert("RGBA")
    assert image.size == size, f"{path.name}: {image.size} != {size}"
    alpha = image.getchannel("A").getextrema()
    if transparent:
        assert alpha == (0, 255), f"{path.name} 应包含透明背景，实际 {alpha}"
    else:
        assert alpha == (255, 255), f"{path.name} 应完全不透明，实际 {alpha}"
    return image


def validate_assets(catalog: list[dict]) -> None:
    for item in catalog:
        validate_rgba(res_path(item["portrait"]), (144, 96), True)
        if item["category"] == "theme":
            validate_rgba(res_path(item["theme_floor"]), (64, 64), False)
            validate_rgba(res_path(item["theme_wall"]), (32, 32), False)
            validate_rgba(res_path(item["theme_wall_v"]), (32, 32), False)
        else:
            validate_rgba(
                res_path(item["scene_asset"]), tuple(item["scene_size"]), True
            )


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in (
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/STHeiti Medium.ttc",
    ):
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def build_preview(catalog: list[dict]) -> None:
    cell_w, cell_h, cols = 304, 250, 6
    image = Image.new("RGB", (cell_w * cols, cell_h * 4), "#1b1511")
    draw = ImageDraw.Draw(image)
    title_font, small_font = font(17), font(13)
    colors = {
        "theme": "#7b4e9d", "function": "#356d7b", "comfort": "#53703b",
        "ambience": "#9b5a32", "service": "#9a7734",
    }
    for index, item in enumerate(catalog):
        x = index % cols * cell_w
        y = index // cols * cell_h
        draw.rectangle(
            (x + 4, y + 4, x + cell_w - 5, y + cell_h - 5),
            fill="#31241b", outline=colors[item["category"]], width=3,
        )
        portrait = Image.open(res_path(item["portrait"])).convert("RGBA")
        portrait = portrait.resize((288, 192), Image.Resampling.NEAREST)
        image.paste(portrait, (x + 8, y + 8), portrait)
        if item["scene_asset"]:
            scene = Image.open(res_path(item["scene_asset"])).convert("RGBA")
            scale = min(2, max(1, 72 // max(scene.width, scene.height)))
            scene = scene.resize(
                (scene.width * scale, scene.height * scale), Image.Resampling.NEAREST
            )
            image.paste(scene, (x + 12, y + 194 - scene.height), scene)
        draw.text((x + 12, y + 207), item["name"], font=title_font, fill="#ffe4bb")
        bonus = item["bonuses"]
        draw.text(
            (x + 142, y + 210),
            f"¥{item['price']}  装{bonus['decor']} 舒{bonus['comfort']} 誉{bonus['reputation']}",
            font=small_font, fill="#8dc5b6",
        )
        draw.text(
            (x + 142, y + 231), f"Lv.{item['unlock_level']}  {'/'.join(item['tags'])}",
            font=small_font, fill="#af9f88",
        )
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    image.save(PREVIEW)


def sync_sketch(catalog: list[dict]) -> None:
    payload = [
        {
            key: item[key]
            for key in (
                "id", "name", "category", "tags", "price", "unlock_level",
                "description", "scene_size", "bonuses",
            )
        }
        for item in catalog
    ]
    html = SKETCH.read_text(encoding="utf-8")
    pattern = re.compile(
        r'(<script id="decor-catalog-data" type="application/json">\n).*?(\n</script>)',
        re.DOTALL,
    )
    updated, count = pattern.subn(
        lambda match: match.group(1)
        + json.dumps(payload, ensure_ascii=False, indent=1)
        + match.group(2),
        html,
        count=1,
    )
    assert count == 1, "布局草图里找不到 decor-catalog-data 数据块"
    SKETCH.write_text(updated, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sync-sketch", action="store_true")
    args = parser.parse_args()
    catalog = load_catalog()
    validate_assets(catalog)
    build_preview(catalog)
    if args.sync_sketch:
        sync_sketch(catalog)
    print("validated 24 项装修、18 套双尺寸物件与 6×3 张主题 Tile")
    print(f"preview {PREVIEW}")


if __name__ == "__main__":
    main()
