#!/usr/bin/env python3
"""校验六代机位配置，以及导出后的小图与详情图。"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "godot/data/pc_configs.json"
PREVIEW = ROOT / "docs/ui/preview/pc_generations@2x.png"
SKETCH = ROOT / "docs/ui/布局草图-像素风.html"
GENERATIONS = [9, 10, 20, 30, 40, 50]
REQUIRED_FIELDS = {
    "id", "generation", "name", "era", "gpu", "gpu_label", "monitor",
    "monitor_label", "pc_case",
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


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in [
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/STHeiti Medium.ttc",
    ]:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def build_preview(configs: list[dict]) -> None:
    cell_w, cell_h = 308, 390
    canvas = Image.new("RGB", (cell_w * 3, cell_h * 2), "#241a12")
    draw = ImageDraw.Draw(canvas)
    title_font, body_font = font(18), font(14)
    for index, config in enumerate(configs):
        x, y = index % 3 * cell_w, index // 3 * cell_h
        draw.rectangle(
            (x + 4, y + 4, x + cell_w - 5, y + cell_h - 5),
            fill="#352518", outline="#765039", width=2,
        )
        suffix = f"{config['generation']:02d}"
        portrait = Image.open(
            ROOT / f"godot/assets/ui/portraits/portrait_pc_gen_{suffix}.png"
        ).convert("RGBA").resize((288, 192), Image.Resampling.NEAREST)
        station = Image.open(
            ROOT / f"godot/assets/world/stations/station_gen_{suffix}.png"
        ).convert("RGBA").resize((128, 136), Image.Resampling.NEAREST)
        canvas.paste(portrait, (x + 10, y + 10), portrait)
        canvas.paste(station, (x + 8, y + 208), station)
        draw.text((x + 142, y + 216), config["name"], font=title_font, fill="#ffe9c9")
        draw.text((x + 142, y + 244), config["gpu"], font=body_font, fill="#75b8c4")
        draw.text((x + 142, y + 268), config["monitor"], font=body_font, fill="#d4b078")
        draw.text(
            (x + 142, y + 316),
            f"性能 {config['performance_score']}  ¥{config['hourly_rate']}/小时",
            font=body_font, fill="#8fc9a8",
        )
        draw.text((x + 142, y + 344), "场景小图 4×", font=body_font, fill="#a99a82")
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(PREVIEW)


def sync_sketch(configs: list[dict]) -> None:
    fields = [
        "generation", "name", "gpu", "monitor", "desk", "chair",
        "performance_score", "hourly_rate",
    ]
    payload = [{key: config[key] for key in fields} for config in configs]
    html = SKETCH.read_text(encoding="utf-8")
    pattern = re.compile(
        r'(<script id="pc-config-data" type="application/json">\n).*?(\n</script>)',
        re.DOTALL,
    )
    block = json.dumps(payload, ensure_ascii=False, indent=1)
    updated, count = pattern.subn(
        lambda match: match.group(1) + block + match.group(2), html, count=1
    )
    assert count == 1, "布局草图里找不到 pc-config-data 数据块"
    SKETCH.write_text(updated, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-only", action="store_true")
    args = parser.parse_args()
    configs = load_configs()
    if not args.data_only:
        validate_assets(configs)
        build_preview(configs)
        sync_sketch(configs)
    print(
        "validated "
        + " / ".join(f"{c['id']} {c['gpu']}" for c in configs)
        + ("（仅数据）" if args.data_only else "（数据与素材）")
    )
    if not args.data_only:
        print(f"preview {PREVIEW}")


if __name__ == "__main__":
    main()
