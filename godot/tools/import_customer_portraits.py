"""从顾客五人拼版切出右栏半身立绘。

不走整店 import，避免重导机位和家具。拼版仍用洋红抠底，按人切开后只留
上半身，补成 3:2 再降到 144×96，和柜台 / 机位特写同一块 CRT。

用法：
    python3 godot/tools/import_customer_portraits.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from import_stage_concepts import apply_palette, build_palette, split_sheet
from pixelize_object import downsample, key_out, pad_to_ratio, trim

CONCEPT_DIR = ROOT / "docs/ui/concept"
PORTRAIT_DIR = ROOT / "godot/assets/ui/portraits"
DATA = ROOT / "godot/data/customers.json"
PREVIEW = ROOT / "docs/ui/preview/customer_portraits@2x.png"
SIZE = (144, 96)
# 只留头和胸，腿会把 3:2 画布压成一条细人。
BUST_KEEP = 0.56
PALETTE_COLORS = 96
ZOOM = 2


def crop_bust(image: Image.Image) -> Image.Image:
    width, height = image.size
    bust_h = max(8, int(height * BUST_KEEP))
    return trim(image.crop((0, 0, width, bust_h)))


def collect() -> list[tuple[str, Image.Image]]:
    result: list[tuple[str, Image.Image]] = []
    for start in range(1, 51, 5):
        sheet = CONCEPT_DIR / f"customers_{start:02d}_{start + 4:02d}.png"
        parts = split_sheet(key_out(Image.open(sheet)))
        if len(parts) != 5:
            raise SystemExit(f"{sheet.name}: 切出 {len(parts)} 人，需要 5 人")
        for offset, part in enumerate(parts):
            index = start + offset
            bust = crop_bust(part)
            padded = pad_to_ratio(bust, SIZE[0] / SIZE[1])
            result.append((
                f"portrait_customer_{index:02d}",
                downsample(padded, *SIZE),
            ))
    return result


def build_preview(items: list[tuple[str, Image.Image]]) -> None:
    cell_w, cell_h = SIZE[0] * ZOOM + 8, SIZE[1] * ZOOM + 8
    cols = 5
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
        person["portrait"] = f"res://assets/ui/portraits/portrait_customer_{index:02d}.png"
    DATA.write_text(json.dumps(roster, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    collected = collect()
    palette = build_palette([image for _, image in collected], PALETTE_COLORS)
    PORTRAIT_DIR.mkdir(parents=True, exist_ok=True)
    finished: list[tuple[str, Image.Image]] = []
    for name, image in collected:
        final = apply_palette(image, palette)
        path = PORTRAIT_DIR / f"{name}.png"
        final.save(path)
        finished.append((name, final))
        print(f"{name:28} {SIZE[0]}x{SIZE[1]}")
    build_preview(finished)
    patch_roster()
    print(f"wrote {len(finished)} portraits and updated {DATA.name}")


if __name__ == "__main__":
    main()
