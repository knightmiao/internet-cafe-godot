"""从背向坐姿五人拼版导出上机贴图。

不走整店 import，避免重导机位、家具和立姿。调色板从已入库的 idle 采样，
让同一件外套在站/坐两张图上不偏色。

用法：
    python3 godot/tools/import_customer_sit.py --measure
    python3 godot/tools/import_customer_sit.py
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from import_stage_concepts import apply_palette, build_palette, split_sheet
from pixelize_object import downsample, key_out, pad_to_ratio, trim

CONCEPT_DIR = ROOT / "docs/ui/concept"
NPC_DIR = ROOT / "godot/assets/world/npc"
DATA = ROOT / "godot/data/customers.json"
PREVIEW = ROOT / "docs/ui/preview/customers_sit@4x.png"
SIZE = (32, 40)
PALETTE_COLORS = 96
ZOOM = 4


def collect() -> list[tuple[str, Image.Image]]:
    result: list[tuple[str, Image.Image]] = []
    for start in range(1, 51, 5):
        sheet = CONCEPT_DIR / f"customers_sit_{start:02d}_{start + 4:02d}.png"
        parts = split_sheet(key_out(Image.open(sheet)))
        if len(parts) != 5:
            raise SystemExit(f"{sheet.name}: 切出 {len(parts)} 人，需要 5 人")
        for offset, part in enumerate(parts):
            index = start + offset
            padded = pad_to_ratio(trim(part), SIZE[0] / SIZE[1])
            result.append((
                f"customer_{index:02d}_sit",
                downsample(padded, *SIZE),
            ))
    return result


def idle_images() -> list[Image.Image]:
    images = []
    for index in range(1, 51):
        path = NPC_DIR / f"customer_{index:02d}_idle.png"
        images.append(Image.open(path).convert("RGBA"))
    return images


def build_preview(items: list[tuple[str, Image.Image]]) -> None:
    cell_w, cell_h = SIZE[0] * ZOOM + 12, SIZE[1] * ZOOM + 12
    cols = 10
    rows = (len(items) + cols - 1) // cols
    sheet = Image.new("RGBA", (cell_w * cols, cell_h * rows), (36, 26, 18, 255))
    for index, (_, image) in enumerate(items):
        big = image.resize((image.width * ZOOM, image.height * ZOOM), Image.Resampling.NEAREST)
        x = (index % cols) * cell_w + (cell_w - big.width) // 2
        y = (index // cols) * cell_h + (cell_h - big.height) // 2
        sheet.alpha_composite(big, (x, y))
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(PREVIEW)
    print(f"preview {PREVIEW} ({sheet.width}x{sheet.height})")


def patch_roster() -> None:
    roster = json.loads(DATA.read_text(encoding="utf-8"))
    for index, person in enumerate(roster, 1):
        person["sprite_sit"] = f"res://assets/world/npc/customer_{index:02d}_sit.png"
    DATA.write_text(json.dumps(roster, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def measure() -> None:
    for start in range(1, 51, 5):
        name = f"customers_sit_{start:02d}_{start + 4:02d}"
        parts = split_sheet(key_out(Image.open(CONCEPT_DIR / f"{name}.png")))
        print(f"\n{name}: 切出 {len(parts)} / 需要 5")
        for i, part in enumerate(parts):
            ratio = part.width / part.height
            want = SIZE[0] / SIZE[1]
            print(
                f"  customer_{start + i:02d}_sit  {part.width:>4}x{part.height:<4}"
                f" 比例 {ratio:.2f} 目标 {SIZE[0]}x{SIZE[1]} 比例 {want:.2f}"
                f" 差 {ratio - want:+.2f}"
            )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--measure", action="store_true")
    args = parser.parse_args()
    if args.measure:
        measure()
        return

    collected = collect()
    palette = build_palette(idle_images() + [image for _, image in collected], PALETTE_COLORS)
    NPC_DIR.mkdir(parents=True, exist_ok=True)
    finished: list[tuple[str, Image.Image]] = []
    for name, image in collected:
        final = apply_palette(image, palette)
        path = NPC_DIR / f"{name}.png"
        final.save(path)
        finished.append((name, final))
        print(f"{name:22} {SIZE[0]}x{SIZE[1]}")
    build_preview(finished)
    patch_roster()
    print(f"wrote {len(finished)} sit sprites and updated {DATA.name}")


if __name__ == "__main__":
    main()
