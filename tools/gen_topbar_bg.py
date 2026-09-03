"""生成顶栏底图：24x24 可水平平铺单元 + 端头收口 + 拼接预览。

开罗风的暖木质感：明快饱和、顶部斜面高光、底部金色收边。
精细化体现在纵向多级明暗过渡与横向长丝木纹，而不是堆噪点。
1:1 素材输出到 godot/assets/ui/topbar/，放大预览只进 docs/ui/preview/。
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "godot/assets/ui/topbar"
PREVIEW = ROOT / "docs/ui/preview"

TILE = 24
BAR_W = 640

# 限色板：顶部装饰木色 + 中段文字衬底 + 金收边
# 文字区(y6~17)刻意压暗压平，浅色字压上去才清楚；装饰只留在上下边缘
C = {
    "lip": (226, 192, 140),      # 顶部最亮唇线
    "wood_0": (178, 130, 78),    # 斜面高光
    "wood_1": (150, 100, 56),
    "wood_2": (120, 78, 42),     # 过渡到文字区
    "field_0": (86, 55, 30),     # 文字衬底 上
    "field_1": (78, 49, 27),     # 文字衬底 主
    "field_2": (70, 44, 24),     # 文字衬底 下
    # 木纹丝与衬底只差几个色阶，远看有质感，不抢文字
    "grain_d": (72, 45, 25),
    "grain_l": (95, 62, 34),
    "groove": (52, 33, 17),      # 木料与金条之间的凹槽
    "gold_hi": (232, 190, 92),
    "gold": (188, 140, 32),
    "gold_lo": (118, 84, 16),
    "edge_bot": (38, 25, 14),
}

# 自上而下：亮唇 → 斜面 → 急速过渡 → 平整文字衬底 → 凹槽 → 金线 → 暗底
ROWS = [
    "lip",       # 0
    "wood_0",    # 1
    "wood_1",    # 2
    "wood_2",    # 3
    "field_0",   # 4
    "field_0",   # 5
    "field_1",   # 6  ┐
    "field_1",   # 7  │
    "field_1",   # 8  │
    "field_1",   # 9  │ 文字区，保持平整
    "field_1",   # 10 │
    "field_1",   # 11 │
    "field_1",   # 12 │
    "field_1",   # 13 │
    "field_1",   # 14 │
    "field_1",   # 15 ┘
    "field_2",   # 16
    "field_2",   # 17
    "groove",    # 18
    "gold_hi",   # 19
    "gold",      # 20
    "gold_lo",   # 21
    "edge_bot",  # 22
    "edge_bot",  # 23
]

# 横向长丝木纹：(y, 起点x, 长度)。跨越 24 边界会自动回绕，平铺无缝。
# 只留在上下边缘带，文字区不放，避免笔画被纹理切断。
GRAIN_DARK = [
    (2, 14, 9),
    (17, 5, 11),
]
GRAIN_LIGHT = [
    (1, 3, 8),
    (16, 17, 9),
]
KNOT = []


def base_tile() -> Image.Image:
    img = Image.new("RGBA", (TILE, TILE))
    px = img.load()
    for y, key in enumerate(ROWS):
        for x in range(TILE):
            px[x, y] = C[key] + (255,)

    for y, start, length in GRAIN_DARK:
        for i in range(length):
            px[(start + i) % TILE, y] = C["grain_d"] + (255,)
    for y, start, length in GRAIN_LIGHT:
        for i in range(length):
            px[(start + i) % TILE, y] = C["grain_l"] + (255,)
    for x, y in KNOT:
        px[x % TILE, y] = C["wood_6"] + (255,)
    return img


def rivet(img: Image.Image, cx: int) -> None:
    """铆钉：左上高光 + 右下暗角，做出 2x2 的小凸起。"""
    px = img.load()
    px[cx, 3] = C["gold_hi"] + (255,)
    px[cx + 1, 3] = C["gold"] + (255,)
    px[cx, 4] = C["gold"] + (255,)
    px[cx + 1, 4] = C["gold_lo"] + (255,)


def cap(side: str) -> Image.Image:
    """端头收口：外侧逐级压暗 + 1px 描边，避免顶栏两端像被切断。"""
    img = base_tile()
    px = img.load()
    for depth, shade in enumerate(("groove", "field_2")):
        x = 1 + depth if side == "left" else TILE - 2 - depth
        for y in range(1, 18):
            px[x, y] = C[shade] + (255,)
    edge_x = 0 if side == "left" else TILE - 1
    for y in range(TILE):
        px[edge_x, y] = C["edge_bot"] + (255,)
    rivet(img, 4 if side == "left" else TILE - 7)
    return img


def build_bar() -> Image.Image:
    tile = base_tile()
    bar = Image.new("RGBA", (BAR_W, TILE))
    for x in range(0, BAR_W, TILE):
        bar.paste(tile, (x, 0))
    bar.paste(cap("left"), (0, 0))
    bar.paste(cap("right"), (BAR_W - TILE, 0))
    return bar


def save(img: Image.Image, name: str, zooms=()) -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    PREVIEW.mkdir(parents=True, exist_ok=True)
    img.save(ASSETS / f"{name}.png")
    for z in zooms:
        big = img.resize((img.width * z, img.height * z), Image.NEAREST)
        big.save(PREVIEW / f"{name}@{z}x.png")


def main() -> None:
    save(base_tile(), "topbar_tile", zooms=(8,))
    save(cap("left"), "topbar_cap_left", zooms=(8,))
    save(cap("right"), "topbar_cap_right", zooms=(8,))
    bar = build_bar()
    save(bar, "topbar_bg", zooms=(2, 4))
    print(f"tile {TILE}x{TILE} / bar {bar.width}x{bar.height} / colors {len(C)}")


if __name__ == "__main__":
    main()
