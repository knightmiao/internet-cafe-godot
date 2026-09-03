"""生成顶栏 12x12 点阵图标。

顶栏内容区仅 14px 高，图标锁死 12x12。每个图标手工点阵，
主体给语义色（钱金、清洁绿、屏幕青），统一 1px 深描边压在木纹上。
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "godot/assets/ui/topbar"
PREVIEW = ROOT / "docs/ui/preview"

SIZE = 12

INK = (58, 36, 18, 255)

# 每个图标一套配色：o 主色 / h 高光 / a 强调
PALETTE = {
    "pc": {"o": (138, 106, 74), "h": (176, 142, 104), "a": (90, 169, 201)},
    "money": {"o": (232, 194, 90), "h": (255, 232, 160), "a": (196, 148, 40)},
    "customers": {"o": (217, 154, 92), "h": (240, 190, 140), "a": (170, 112, 62)},
    "reputation": {"o": (240, 200, 80), "h": (255, 238, 170), "a": (198, 150, 36)},
    "clean": {"o": (122, 184, 138), "h": (170, 214, 182), "a": (84, 138, 98)},
    "decor": {"o": (186, 132, 150), "h": (216, 176, 188), "a": (140, 92, 110)},
    "bell": {"o": (232, 194, 90), "h": (255, 232, 160), "a": (196, 148, 40)},
    "gear": {"o": (186, 168, 142), "h": (222, 208, 188), "a": (140, 122, 100)},
}

# . 透明 / # 描边 / o 主色 / h 高光 / a 强调
ICONS = {
    # CRT 显示器：厚机身 + 青色荧光屏 + 底座
    "pc": [
        "............",
        ".##########.",
        ".#hooooooo#.",
        ".#oaaaaaao#.",
        ".#oaaaaaao#.",
        ".#oaaaaaao#.",
        ".#ooooooooo#",
        ".##########.",
        "....####....",
        "...#oooo#...",
        "..########..",
        "............",
    ],
    # ¥ 符号占满画布。12x12 里再套金币外圈，符号就只剩 8x8，糊成一团。
    "money": [
        "............",
        "#h........h#",
        "#o#......#o#",
        ".#o#....#o#.",
        "..#o#..#o#..",
        "...#oooo#...",
        ".##########.",
        "...#hhhh#...",
        ".##########.",
        "....#oo#....",
        "....#oo#....",
        "............",
    ],
    # 两个并肩顾客
    "customers": [
        "..##....##..",
        ".#hh#..#hh#.",
        ".#oo#..#oo#.",
        "..##....##..",
        ".####..####.",
        "#hooo##ooohh",
        "#oooooooooo#",
        "#oooooooooo#",
        "#oooooooooo#",
        "#oooooooooo#",
        "#oo#....#oo#",
        "............",
    ],
    # 五角星：上尖 + 左右臂 + 双腿，严格左右对称
    "reputation": [
        ".....##.....",
        "....ohho....",
        "....ohho....",
        "###oooooo###",
        "#oooooooooo#",
        ".#oooooooo#.",
        "..oooooooo..",
        "..oo####oo..",
        ".#o#....#o#.",
        ".#o#....#o#.",
        "..#......#..",
        "............",
    ],
    # 扫帚：斜柄 + 扇形刷头
    "clean": [
        ".........#h.",
        "........#h..",
        ".......#h...",
        "......#h....",
        ".....#h.....",
        "....#hho....",
        "...#hoooo...",
        "..#ooooooo..",
        ".#ooo#oo#oo.",
        ".#oo#.#o.#o.",
        "..#...#...#.",
        "............",
    ],
    # 沙发：窄靠背在上，扶手向两侧凸出，坐垫在下
    "decor": [
        "............",
        "..########..",
        "..#hhhhhh#..",
        "..#oooooo#..",
        "############",
        "#oo######oo#",
        "#oo######oo#",
        "#oooooooooo#",
        "#oooooooooo#",
        "############",
        "..#......#..",
        "..#......#..",
    ],
    # 铃铛
    "bell": [
        ".....##.....",
        "....#hh#....",
        "...#hoooo#..",
        "...#ooooo#..",
        "..#oooooooo.",
        "..#oooooooo.",
        ".#oooooooooo",
        ".#oooooooooo",
        "############",
        "............",
        "....#oo#....",
        ".....##.....",
    ],
    # 齿轮：上下各两齿、左右各一齿，中心方孔
    "gear": [
        "...##..##...",
        "...#h..h#...",
        ".##########.",
        ".#hooooooo#.",
        "##oo####oo##",
        "##oo####oo##",
        "##oo####oo##",
        "##oo####oo##",
        ".#oooooooo#.",
        ".##########.",
        "...#o..o#...",
        "...##..##...",
    ],
}


def render(name: str, rows: list[str]) -> Image.Image:
    colors = PALETTE[name]
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(rows):
        assert len(row) == SIZE, f"{name} 第 {y} 行宽 {len(row)}"
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            px[x, y] = INK if ch == "#" else colors[ch] + (255,)
    assert len(rows) == SIZE, f"{name} 共 {len(rows)} 行"
    return img


def badge(bell: Image.Image) -> Image.Image:
    """未读态：右上角叠 3x3 红点，带深色描边保证在任何底色上都可见。"""
    img = bell.copy()
    px = img.load()
    for x in range(8, 12):
        for y in range(0, 4):
            px[x, y] = (0, 0, 0, 0)
    for x, y in [(9, 0), (10, 0), (8, 1), (11, 1), (8, 2), (11, 2), (9, 3), (10, 3)]:
        px[x, y] = INK
    for x, y in [(9, 1), (10, 1), (9, 2), (10, 2)]:
        px[x, y] = (214, 74, 58, 255)
    return img


def sheet(icons: dict) -> Image.Image:
    """全图标一览，便于整体比对风格。"""
    pad = 4
    w = (SIZE + pad) * len(icons) + pad
    out = Image.new("RGBA", (w, SIZE + pad * 2), (78, 49, 27, 255))
    for i, img in enumerate(icons.values()):
        out.alpha_composite(img, (pad + i * (SIZE + pad), pad))
    return out


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    PREVIEW.mkdir(parents=True, exist_ok=True)

    built = {name: render(name, rows) for name, rows in ICONS.items()}
    built["bell_badge"] = badge(built["bell"])

    for name, img in built.items():
        img.save(ASSETS / f"icon_{name}.png")
        img.resize((SIZE * 8, SIZE * 8), Image.NEAREST).save(
            PREVIEW / f"icon_{name}@8x.png"
        )

    board = sheet(built)
    board.resize((board.width * 6, board.height * 6), Image.NEAREST).save(
        PREVIEW / "topbar_icons@6x.png"
    )
    print(f"{len(built)} icons @ {SIZE}x{SIZE}")


if __name__ == "__main__":
    main()
