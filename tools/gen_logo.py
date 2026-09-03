"""生成「猫网电竞」像素 logo：14x14 猫头 + 12px 点阵字标。

顶栏净高只有 24px，其中文字区 14px，因此 logo 总高锁死 16px。
字标走系统黑体 12px 渲染再二值化，得到干净点阵；猫头程序化绘制。
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "godot/assets/ui/topbar"
PREVIEW = ROOT / "docs/ui/preview"

FONT = "/System/Library/Fonts/STHeiti Medium.ttc"
TEXT = "猫网电竞"
FONT_PX = 12
THRESHOLD = 110

HEAD = 14          # 猫头边长
GAP = 3            # 猫头与字标间距
LOGO_H = 16        # 含 1px 投影的总高

C = {
    "ink": (58, 36, 18, 255),        # 描边 / 投影
    "fur": (232, 163, 60, 255),      # 猫头填充
    "fur_hi": (255, 207, 122, 255),  # 猫头高光
    "text": (255, 214, 138, 255),    # 字标主色
    "text_hi": (255, 240, 200, 255), # 字标顶部提亮
}


# 14x14 猫头点阵。耳朵与脸共用轮廓，避免小尺寸下耳朵像独立犄角。
# . 透明 / # 描边 / o 填充 / h 高光 / E 眼 / N 鼻
CAT = [
    "..##......##..",
    ".#oo#....#oo#.",
    ".#ooo#..#ooo#.",
    ".#oooo##oooo#.",
    "#oooooooooooo#",
    "#ohoooooooooo#",
    "#ooEEooooEEoo#",
    "#ooEEooooEEoo#",
    "#oooooooooooo#",
    "#ooooo##ooooo#",
    ".#ooo#oo#ooo#.",
    ".#oooooooooo#.",
    "..#oooooooo#..",
    "...########...",
]

GLYPH = {
    "#": "ink",
    "o": "fur",
    "h": "fur_hi",
    "E": "ink",
    "N": "ink",
}


def cat_head() -> Image.Image:
    img = Image.new("RGBA", (HEAD, HEAD), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(CAT):
        assert len(row) == HEAD, f"第 {y} 行宽度 {len(row)} != {HEAD}"
        for x, ch in enumerate(row):
            if ch != ".":
                px[x, y] = C[GLYPH[ch]]
    return _drop_shadow(img)


def wordmark() -> Image.Image:
    """12px 黑体二值化成点阵，顶行提亮一档增加立体感。"""
    font = ImageFont.truetype(FONT, FONT_PX)
    w = FONT_PX * len(TEXT) + 2
    mask = Image.new("L", (w, FONT_PX + 2), 0)
    ImageDraw.Draw(mask).text((1, 1), TEXT, font=font, fill=255)
    mask = mask.point(lambda v: 255 if v > THRESHOLD else 0)

    bbox = mask.getbbox()
    mask = mask.crop(bbox)

    img = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    mp, ip = mask.load(), img.load()
    for y in range(mask.height):
        for x in range(mask.width):
            if mp[x, y]:
                # 笔画顶端提亮，模拟受光
                lit = y == 0 or not mp[x, y - 1]
                ip[x, y] = C["text_hi"] if lit else C["text"]
    return _drop_shadow(img)


def _drop_shadow(src: Image.Image) -> Image.Image:
    """右下 1px 投影：小字压在木纹上也能立住。"""
    out = Image.new("RGBA", (src.width + 1, src.height + 1), (0, 0, 0, 0))
    sp, op = src.load(), out.load()
    for y in range(src.height):
        for x in range(src.width):
            if sp[x, y][3]:
                op[x + 1, y + 1] = C["ink"]
    out.alpha_composite(src)
    return out


def build() -> Image.Image:
    head, word = cat_head(), wordmark()
    logo = Image.new("RGBA", (head.width + GAP + word.width, LOGO_H), (0, 0, 0, 0))
    logo.alpha_composite(head, (0, (LOGO_H - head.height) // 2))
    logo.alpha_composite(word, (head.width + GAP, (LOGO_H - word.height) // 2))
    return logo


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    PREVIEW.mkdir(parents=True, exist_ok=True)
    logo = build()
    logo.save(ASSETS / "logo.png")
    for z in (4, 8):
        logo.resize((logo.width * z, logo.height * z), Image.NEAREST).save(
            PREVIEW / f"logo@{z}x.png"
        )
    print(f"logo {logo.width}x{logo.height}")


if __name__ == "__main__":
    main()
