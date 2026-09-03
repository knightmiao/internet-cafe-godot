"""把生图概念稿像素化成右栏特写素材。

生图直出的图带抗锯齿和渐变，直接进游戏会糊。这里先裁掉外框、居中裁成
3:2，再用区域平均缩到目标尺寸，最后量化到有限调色板，得到边缘干净、
色数可控的像素素材。

用法：
    python3 godot/tools/pixelize_portrait.py <源图> <输出名> [--colors N]
"""

import argparse
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ASSET_DIR = ROOT / "godot/assets/ui/portraits"
PREVIEW_DIR = ROOT / "docs/ui/preview"

TARGET_W, TARGET_H = 144, 96
# 生图外圈常带一条装饰暗边，先剥掉
BORDER_TRIM = 7


def crop_to_ratio(image: Image.Image, ratio: float) -> Image.Image:
    width, height = image.size
    if width / height > ratio:
        new_w = int(round(height * ratio))
        left = (width - new_w) // 2
        return image.crop((left, 0, left + new_w, height))
    new_h = int(round(width / ratio))
    top = (height - new_h) // 2
    return image.crop((0, top, width, top + new_h))


def pixelize(src: Path, colors: int, resample) -> Image.Image:
    image = Image.open(src).convert("RGB")
    width, height = image.size
    image = image.crop((
        BORDER_TRIM, BORDER_TRIM, width - BORDER_TRIM, height - BORDER_TRIM,
    ))
    image = crop_to_ratio(image, TARGET_W / TARGET_H)
    image = image.resize((TARGET_W, TARGET_H), resample)
    # dither 关闭，避免像素风出现噪点抖动
    quantized = image.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    return quantized.convert("RGBA")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("name")
    parser.add_argument("--colors", type=int, default=32)
    parser.add_argument("--candidates", action="store_true",
                        help="额外导出不同采样与色数的候选，便于挑选")
    args = parser.parse_args()

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

    if args.candidates:
        for tag, resample, colors in (
            ("box32", Image.Resampling.BOX, 32),
            ("box24", Image.Resampling.BOX, 24),
            ("lanczos28", Image.Resampling.LANCZOS, 28),
        ):
            image = pixelize(args.source, colors, resample)
            out = PREVIEW_DIR / f"{args.name}_{tag}@4x.png"
            image.resize((TARGET_W * 4, TARGET_H * 4), Image.Resampling.NEAREST).save(out)
            print(f"candidate {out}")
        return

    image = pixelize(args.source, args.colors, Image.Resampling.BOX)
    asset = ASSET_DIR / f"{args.name}.png"
    image.save(asset)
    preview = PREVIEW_DIR / f"{args.name}@4x.png"
    image.resize((TARGET_W * 4, TARGET_H * 4), Image.Resampling.NEAREST).save(preview)
    print(f"generated {asset} ({TARGET_W}x{TARGET_H}, {args.colors} colors)")
    print(f"preview   {preview}")


if __name__ == "__main__":
    main()
