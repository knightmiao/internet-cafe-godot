"""把 app_icon 概念稿像素化，铺暖木底，打出 Godot / macOS 用的图标。

管线：概念稿洋红底 → 抠底降采样 128×128 → 铺木纹方底 → 邻近放大出各尺寸与 icns。
"""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

from pixelize_object import pixelize

ROOT = Path(__file__).resolve().parents[2]
CONCEPT = ROOT / "docs/ui/concept/app_icon.png"
ASSET_DIR = ROOT / "godot/assets/ui"
PREVIEW_DIR = ROOT / "docs/ui/preview"
PIXEL = 128
COLORS = 48
MASTER = 1024

WOOD = (92, 58, 32, 255)
WOOD_DARK = (58, 36, 22, 255)
WOOD_MID = (117, 74, 41, 255)
WOOD_HI = (177, 132, 89, 255)
INK = (42, 29, 18, 255)
AMBER = (184, 134, 11, 255)


def wood_tile(size: int) -> Image.Image:
    """暖棕木纹方底，铺满画布，圆角留给系统裁。"""
    img = Image.new("RGBA", (size, size), WOOD)
    px = img.load()
    for y in range(size):
        wave = (y * 3 + (y // 7) * 5) % 11
        for x in range(size):
            n = (x + wave + (y // 3)) % 13
            if n < 2:
                px[x, y] = WOOD_DARK
            elif n in (5, 6):
                px[x, y] = WOOD_MID
            elif y < 3 or (x + y) % 17 == 0:
                px[x, y] = WOOD_HI if y < 2 else WOOD_MID
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, size - 1, size - 1), outline=INK)
    draw.rectangle((1, 1, size - 2, size - 2), outline=WOOD_HI)
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        (size // 6, size // 5, size - size // 6, size - size // 8),
        fill=(58, 143, 197, 36),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(radius=max(2, size // 18)))
    return Image.alpha_composite(img, glow)


def compose(sprite: Image.Image) -> Image.Image:
    tile = wood_tile(PIXEL)
    pad = 6
    inner = PIXEL - pad * 2
    fitted = sprite.copy()
    fitted.thumbnail((inner, inner), Image.Resampling.NEAREST)
    x = (PIXEL - fitted.width) // 2
    y = PIXEL - pad - fitted.height
    tile.alpha_composite(fitted, (x, y))
    return tile


def write_iconset(master: Image.Image, dest: Path) -> Path:
    work = Path(tempfile.mkdtemp(prefix="cafe-iconset-"))
    iconset = work / "AppIcon.iconset"
    iconset.mkdir()
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for name, edge in sizes.items():
        master.resize((edge, edge), Image.Resampling.NEAREST).save(iconset / name)
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(dest)], check=True)
    shutil.rmtree(work)
    return dest


def main() -> None:
    if not CONCEPT.exists():
        raise SystemExit(f"缺少概念稿：{CONCEPT}")
    sprite = pixelize(CONCEPT, PIXEL, PIXEL, COLORS)
    icon = compose(sprite)
    master = icon.resize((MASTER, MASTER), Image.Resampling.NEAREST)

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    sprite.save(ASSET_DIR / "app_icon_sprite.png")
    master.save(ASSET_DIR / "app_icon.png")
    write_iconset(master, ASSET_DIR / "app_icon.icns")
    icon.resize((PIXEL * 4, PIXEL * 4), Image.Resampling.NEAREST).save(
        PREVIEW_DIR / "app_icon@4x.png"
    )
    print(f"app icon {MASTER}x{MASTER} -> {ASSET_DIR / 'app_icon.png'}")


if __name__ == "__main__":
    main()
