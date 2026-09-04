"""把生图概念稿像素化成场景物件素材。

与 pixelize_portrait.py 的差别在于场景物件是带透明通道的独立 sprite：
概念稿用洋红(#FF00FF) chroma key 打底，这里先抠底再降采样。降采样必须走
预乘 alpha，否则透明区的黑色会顺着 box 平均渗进物件边缘，得到一圈脏边。
量化时也先把透明区填成物件主色，避免黑色白占一个调色板槽位。

用法：
    python3 godot/tools/pixelize_object.py <源图> <组名/素材名> --size 48x56 [--colors 24]

例：
    python3 godot/tools/pixelize_object.py concept_pc.png stations/pc_station --size 48x56
"""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ASSET_DIR = ROOT / "godot/assets/world"
PREVIEW_DIR = ROOT / "docs/ui/preview"

# 洋红判定用色相而非绝对亮度：洋红的特征是红蓝双高、绿极低。
# 生图会把物件的落地阴影画在洋红底上，混出 (150,0,140) 这类暗洋红，
# 按亮度设阈值抠不掉，残留会污染调色板并给物件描上一圈紫边。
# 实测概念稿里背景像素的 spill 全在 200 以上，物件（含粉发、紫夹克）全在
# 40 以下，中间几乎没有过渡值，所以 100 是一刀两断的安全位置。
SPILL_THRESHOLD = 100
# 抠底后再往外啃掉几像素，去掉边缘抗锯齿混进来的洋红
SPILL_ERODE = 2
# 降采样后 alpha 的二值化阈值，像素风不保留半透明
ALPHA_CUT = 0.5


def _dilate(mask: np.ndarray, radius: int) -> np.ndarray:
    grown = mask.copy()
    for _ in range(radius):
        grown = (
            grown
            | np.roll(grown, 1, 0) | np.roll(grown, -1, 0)
            | np.roll(grown, 1, 1) | np.roll(grown, -1, 1)
        )
    return grown


def key_out(image: Image.Image) -> Image.Image:
    """抠掉洋红底，连同落地阴影混出的暗洋红和边缘色边一起去掉。"""
    arr = np.asarray(image.convert("RGBA")).astype(np.int16)
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    spill = np.minimum(r, b) - g
    background = spill > SPILL_THRESHOLD
    if SPILL_ERODE:
        background = _dilate(background, SPILL_ERODE)
    arr[..., 3] = np.where(background, 0, arr[..., 3])
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def trim(image: Image.Image) -> Image.Image:
    box = image.getbbox()
    return image.crop(box) if box else image


def pad_to_ratio(image: Image.Image, ratio: float) -> Image.Image:
    """按目标宽高比补透明边，保证物件不被拉伸。"""
    width, height = image.size
    if width / height > ratio:
        new_w, new_h = width, int(round(width / ratio))
    else:
        new_w, new_h = int(round(height * ratio)), height
    canvas = Image.new("RGBA", (new_w, new_h), (0, 0, 0, 0))
    canvas.paste(image, ((new_w - width) // 2, (new_h - height) // 2))
    return canvas


def downsample(image: Image.Image, target_w: int, target_h: int) -> Image.Image:
    """预乘 alpha 的面积平均降采样。"""
    arr = np.asarray(image).astype(np.float64)
    alpha = arr[..., 3] / 255.0
    premultiplied = arr[..., :3] * alpha[..., None]

    small_rgb = Image.fromarray(
        np.clip(premultiplied, 0, 255).astype(np.uint8), "RGB"
    ).resize((target_w, target_h), Image.Resampling.BOX)
    small_alpha = Image.fromarray(
        arr[..., 3].astype(np.uint8), "L"
    ).resize((target_w, target_h), Image.Resampling.BOX)

    pre = np.asarray(small_rgb).astype(np.float64)
    al = np.asarray(small_alpha).astype(np.float64) / 255.0
    rgb = np.where(al[..., None] > 0, pre / np.maximum(al[..., None], 1e-6), 0.0)
    out_alpha = np.where(al >= ALPHA_CUT, 255, 0)
    return Image.fromarray(
        np.concatenate([np.clip(rgb, 0, 255), out_alpha[..., None]], axis=2).astype(np.uint8),
        "RGBA",
    )


def quantize(image: Image.Image, colors: int) -> Image.Image:
    """只按不透明像素挑调色板，再把 alpha 原样贴回。"""
    arr = np.asarray(image).astype(np.uint8).copy()
    opaque = arr[..., 3] > 0
    if not opaque.any():
        return image
    fill = np.median(arr[opaque][:, :3], axis=0).astype(np.uint8)
    arr[~opaque, :3] = fill

    flat = Image.fromarray(arr[..., :3], "RGB")
    reduced = flat.quantize(
        colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE
    ).convert("RGB")
    return Image.fromarray(
        np.dstack([np.asarray(reduced), arr[..., 3]]).astype(np.uint8), "RGBA"
    )


def pixelize(src: Path, target_w: int, target_h: int, colors: int) -> Image.Image:
    image = trim(key_out(Image.open(src)))
    image = pad_to_ratio(image, target_w / target_h)
    return quantize(downsample(image, target_w, target_h), colors)


def parse_size(text: str) -> tuple[int, int]:
    width, _, height = text.lower().partition("x")
    return int(width), int(height)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("name", help="组名/素材名，如 stations/pc_station")
    parser.add_argument("--size", required=True, help="目标尺寸，如 48x56")
    parser.add_argument("--colors", type=int, default=24)
    parser.add_argument("--zoom", type=int, default=8, help="预览放大倍数")
    parser.add_argument("--dry-run", action="store_true", help="只出预览，不写 assets")
    args = parser.parse_args()

    target_w, target_h = parse_size(args.size)
    image = pixelize(args.source, target_w, target_h, args.colors)

    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    flat_name = args.name.replace("/", "_")
    preview = PREVIEW_DIR / f"{flat_name}@{args.zoom}x.png"
    image.resize(
        (target_w * args.zoom, target_h * args.zoom), Image.Resampling.NEAREST
    ).save(preview)
    print(f"preview {preview}")

    if not args.dry_run:
        asset = ASSET_DIR / f"{args.name}.png"
        asset.parent.mkdir(parents=True, exist_ok=True)
        image.save(asset)
        print(f"asset   {asset} ({target_w}x{target_h}, <={args.colors} colors)")


if __name__ == "__main__":
    main()
