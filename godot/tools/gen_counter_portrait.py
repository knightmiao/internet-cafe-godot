"""生成右栏柜台特写 portrait_counter.png（144×96 逻辑像素）。

流程：概念稿 → 像素化降采样 → 手工修五官。

降采样能保住构图、卷发分缕和布偶猫的面罩花色，但会把眼镜细框和眼睛糊成
低对比色块。所以最后一步按坐标重画眼镜、眼睛、鼻嘴和猫的蓝眼，把小尺寸
下最吃对比度的部分补回来。

用法：python3 godot/tools/gen_counter_portrait.py
"""

import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pixelize_portrait import ASSET_DIR, PREVIEW_DIR, TARGET_H, TARGET_W, pixelize  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CONCEPT = ROOT / "docs/ui/concept/concept_counter_landscape.png"
NAME = "portrait_counter"
COLORS = 32

GLASS = "#33241a"
EYE_INK = "#1c1512"
EYE_HI = "#f4ecdd"
SKIN_DARK = "#c07d51"
MOUTH = "#a86a52"
CAT_EYE = "#6fa4dc"
CAT_EYE_DARK = "#2f5f9c"
CAT_EYE_HI = "#cfe6fa"
CAT_NOSE = "#d98f92"

# 老板：脸位于 x60~75 / y26~38，双镜片外框左沿在 x60 与 x69
LENS_LEFT = 60
LENS_RIGHT = 69
LENS_TOP = 26


def rgba(color: str):
    color = color.lstrip("#")
    return int(color[0:2], 16), int(color[2:4], 16), int(color[4:6], 16), 255


class Retoucher:
    def __init__(self, image: Image.Image):
        self.image = image
        self.px = image.load()
        self.w, self.h = image.size

    def dot(self, x: int, y: int, color: str) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[x, y] = rgba(color)

    def hline(self, x0: int, x1: int, y: int, color: str) -> None:
        for x in range(x0, x1 + 1):
            self.dot(x, y, color)

    def rect(self, x0: int, y0: int, x1: int, y1: int, color: str) -> None:
        for y in range(y0, y1 + 1):
            self.hline(x0, x1, y, color)

    def lens(self, left: int, top: int, color: str) -> None:
        """镜片轮廓：只留上沿与左右侧，下沿交给眼睛下方的肤色收边。"""
        self.hline(left + 1, left + 4, top, color)
        for dy in (1, 2):
            self.dot(left, top + dy, color)
            self.dot(left + 5, top + dy, color)


def retouch_boss(r: Retoucher) -> None:
    # 圆框眼镜：轻描的框 + 鼻桥 + 镜腿，避免在小尺寸下糊成墨镜
    r.lens(LENS_LEFT, LENS_TOP, GLASS)
    r.lens(LENS_RIGHT, LENS_TOP, GLASS)
    r.hline(66, 68, LENS_TOP + 1, GLASS)
    r.hline(57, 59, LENS_TOP + 1, GLASS)
    r.hline(75, 77, LENS_TOP + 1, GLASS)

    # 眼睛：2×2 深块。1x 下这个面积已经足够醒目，再加高光会变成白眼
    for left in (LENS_LEFT, LENS_RIGHT):
        r.rect(left + 2, LENS_TOP + 1, left + 3, LENS_TOP + 2, EYE_INK)

    # 鼻与微笑，各只占一行且尽量短，避免抢五官
    r.hline(66, 67, 31, SKIN_DARK)
    r.hline(66, 68, 33, MOUTH)


def retouch_cat(r: Retoucher) -> None:
    # 蓝眼：底色 + 深瞳 + 高光
    for left in (104, 112):
        r.rect(left, 37, left + 2, 39, CAT_EYE)
        r.rect(left + 1, 38, left + 1, 39, CAT_EYE_DARK)
        r.dot(left, 37, CAT_EYE_HI)

    # 粉鼻
    r.hline(108, 110, 41, CAT_NOSE)
    r.dot(109, 42, CAT_NOSE)


def main() -> None:
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

    image = pixelize(CONCEPT, COLORS, Image.Resampling.BOX).convert("RGBA")
    r = Retoucher(image)
    retouch_boss(r)
    retouch_cat(r)

    asset = ASSET_DIR / f"{NAME}.png"
    image.save(asset)
    preview = PREVIEW_DIR / f"{NAME}@4x.png"
    image.resize((TARGET_W * 4, TARGET_H * 4), Image.Resampling.NEAREST).save(preview)
    print(f"generated {asset} ({TARGET_W}x{TARGET_H})")
    print(f"preview   {preview}")


if __name__ == "__main__":
    main()
