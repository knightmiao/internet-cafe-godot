"""生成右侧操作区的九宫格皮肤素材（2005 年老电脑外壳质感）。

所有素材都是小尺寸可平铺图，靠 Godot StyleBoxTexture 的 texture_margin 撑开，
中心区为纯色以保证平铺无缝，避免像素素材被非整数缩放。

产出（1x 到 godot/assets/ui/panel/，4x 拼版预览到 docs/ui/preview/）：
    panel_case      机身外壳，四角带螺丝
    screen_frame    CRT 特写屏机框
    amber_frame     琥珀单色概览屏，内凹
    key_*           上下文大键帽四态
    modkey_*        全局模块小键三态

用法：python3 godot/tools/gen_panel_theme.py
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "godot/assets/ui/panel"
PREVIEW = ROOT / "docs/ui/preview/panel_theme@4x.png"

# 塑料机身
CASE_FACE = "#d8cfb4"
CASE_HI = "#efe8d2"
CASE_LO = "#9a9078"
EDGE = "#4a4438"
SCREW = "#5f5749"
SCREW_HI = "#c4bca4"

# CRT 机框
CRT_FRAME = "#3d3a33"
CRT_INNER = "#1a1712"

# 琥珀屏
AMBER_BG = "#241c10"
AMBER_DEEP = "#160f08"
AMBER_GLOW = "#4a3418"

# 键帽。面色分亮/中/暗三段，配上高光、阴影与更深的描边共六层，
# 只靠「描边 + 1px 高光 + 2px 阴影」在 1x 下会显得像框线图。
KEY_EDGE = "#3a352b"
KEY_HI = "#efe8d2"
KEY_FACE_TOP = "#ddd4ba"
KEY_FACE = "#cfc5a8"
KEY_FACE_BOT = "#bfb598"
KEY_LO = "#8e8471"

KEY_HOVER_HI = "#fdf8e6"
KEY_HOVER_TOP = "#ece3c8"
KEY_HOVER_FACE = "#ded4b6"
KEY_HOVER_BOT = "#cec4a6"

KEY_PRESS_TOP = "#a89f87"
KEY_PRESS_FACE = "#b8ae92"
KEY_PRESS_BOT = "#c6bca2"

KEY_OFF = "#9d9a90"
KEY_OFF_HI = "#a9a69c"
KEY_OFF_BOT = "#918e85"
KEY_OFF_EDGE = "#63605a"


def rgba(color: str):
    color = color.lstrip("#")
    return int(color[0:2], 16), int(color[2:4], 16), int(color[4:6], 16), 255


class Tile:
    def __init__(self, size: int, fill: str):
        self.image = Image.new("RGBA", (size, size), rgba(fill))
        self.px = self.image.load()
        self.size = size

    def dot(self, x: int, y: int, color: str) -> None:
        if 0 <= x < self.size and 0 <= y < self.size:
            self.px[x, y] = rgba(color)

    def hline(self, x0: int, x1: int, y: int, color: str) -> None:
        for x in range(x0, x1 + 1):
            self.dot(x, y, color)

    def vline(self, x: int, y0: int, y1: int, color: str) -> None:
        for y in range(y0, y1 + 1):
            self.dot(x, y, color)

    def frame(self, inset: int, color: str) -> None:
        lo, hi = inset, self.size - 1 - inset
        self.hline(lo, hi, lo, color)
        self.hline(lo, hi, hi, color)
        self.vline(lo, lo, hi, color)
        self.vline(hi, lo, hi, color)


def bevel(
    size: int,
    face: str,
    edge: str,
    top: str | None,
    bottom: str | None,
    bottom_thick: int = 2,
    side_hi: str | None = None,
    side_lo: str | None = None,
) -> Tile:
    """凸起面：外描边 + 顶高光 + 底阴影。中心保持纯 face 色以便平铺。"""
    tile = Tile(size, face)
    last = size - 1

    if top:
        tile.hline(1, last - 1, 1, top)
    for i in range(bottom_thick):
        if bottom:
            tile.hline(1, last - 1, last - 1 - i, bottom)
    if side_hi:
        tile.vline(1, 2, last - 1 - bottom_thick, side_hi)
    if side_lo:
        tile.vline(last - 1, 2, last - 1 - bottom_thick, side_lo)

    tile.frame(0, edge)
    return tile


def panel_case() -> Tile:
    """机身外壳，margin 4。四角画螺丝，只会出现在面板四角。"""
    tile = bevel(16, CASE_FACE, EDGE, CASE_HI, CASE_LO, 2, CASE_HI, CASE_LO)
    # 下排螺丝落在 row 12：再往下就压进底部阴影带，深色叠深色会看不见。
    for cx, cy in ((2, 2), (13, 2), (2, 12), (13, 12)):
        tile.dot(cx, cy, SCREW)
        tile.dot(cx + 1, cy, SCREW)
        tile.dot(cx, cy + 1, SCREW)
        tile.dot(cx + 1, cy + 1, SCREW)
        tile.dot(cx, cy, SCREW_HI)
    return tile


def screen_frame() -> Tile:
    """CRT 机框，margin 3：外描边 + 机框 + 内圈黑。中心纯黑，由插画覆盖。"""
    tile = Tile(10, CRT_INNER)
    tile.frame(1, CRT_FRAME)
    tile.frame(2, CRT_INNER)
    tile.frame(0, EDGE)
    # 机框上沿提亮、下沿压暗，做出外壳厚度
    tile.hline(2, 7, 1, "#4e4a41")
    tile.hline(2, 7, 8, "#2b2924")
    return tile


def amber_frame() -> Tile:
    """琥珀屏，margin 3：内凹，顶部与左侧更深，底部一点余晖。"""
    tile = Tile(10, AMBER_BG)
    tile.frame(1, AMBER_DEEP)
    tile.hline(1, 8, 1, AMBER_DEEP)
    tile.vline(1, 1, 8, AMBER_DEEP)
    tile.hline(2, 7, 8, AMBER_GLOW)
    tile.frame(0, EDGE)
    return tile


def layered_key(
    size: int,
    top_rows: list[str],
    center: str,
    bottom_rows: list[str],
    edge: str,
    side_hi: str | None = None,
    side_lo: str | None = None,
) -> Tile:
    """分层键帽：顶部与底部各若干行显式配色，中心区留纯色以便平铺。

    top_rows / bottom_rows 的长度即该侧的 texture_margin，九宫格拉伸时这些行
    原样保留，只有中心那几行被复制，因此层次不会被拉花。
    """
    tile = Tile(size, center)
    last = size - 1
    for y, color in enumerate(top_rows):
        tile.hline(0, last, y, color)
    for i, color in enumerate(bottom_rows):
        tile.hline(0, last, last - len(bottom_rows) + 1 + i, color)
    # 侧边亮暗只画在中段，避免和顶/底的横向层次打架
    mid_top, mid_bottom = len(top_rows), last - len(bottom_rows)
    if side_hi:
        tile.vline(1, mid_top, mid_bottom, side_hi)
    if side_lo:
        tile.vline(last - 1, mid_top, mid_bottom, side_lo)
    tile.frame(0, edge)
    return tile


def keycaps() -> dict[str, Tile]:
    """上下文大键帽，12² / margin 4：描边→高光→亮面→中面→暗面→阴影→描边共六层。"""
    normal = layered_key(
        12,
        [KEY_EDGE, KEY_HI, KEY_FACE_TOP, KEY_FACE_TOP],
        KEY_FACE,
        [KEY_FACE_BOT, KEY_LO, KEY_LO, KEY_EDGE],
        KEY_EDGE,
        KEY_FACE_TOP,
        KEY_FACE_BOT,
    )
    hover = layered_key(
        12,
        [KEY_EDGE, KEY_HOVER_HI, KEY_HOVER_TOP, KEY_HOVER_TOP],
        KEY_HOVER_FACE,
        [KEY_HOVER_BOT, KEY_LO, KEY_LO, KEY_EDGE],
        KEY_EDGE,
        KEY_HOVER_TOP,
        KEY_HOVER_BOT,
    )
    # 按下：顶部换成内阴影、底部只留一线反光，整体读作凹陷
    pressed = layered_key(
        12,
        [KEY_EDGE, KEY_LO, KEY_PRESS_TOP, KEY_PRESS_TOP],
        KEY_PRESS_FACE,
        [KEY_PRESS_BOT, KEY_PRESS_BOT, KEY_FACE_TOP, KEY_EDGE],
        KEY_EDGE,
        KEY_PRESS_TOP,
        KEY_PRESS_BOT,
    )
    # 禁用：冷灰面 + 抹平立体层次，只留极弱的上下明暗
    disabled = layered_key(
        12,
        [KEY_OFF_EDGE, KEY_OFF_HI, KEY_OFF, KEY_OFF],
        KEY_OFF,
        [KEY_OFF, KEY_OFF_BOT, KEY_OFF_BOT, KEY_OFF_EDGE],
        KEY_OFF_EDGE,
    )
    return {
        "key_normal": normal,
        "key_hover": hover,
        "key_pressed": pressed,
        "key_disabled": disabled,
    }


def modkeys() -> dict[str, Tile]:
    """模块与走带小键，8² / margin 2：同款更薄，只留高光与阴影各一行。"""
    normal = layered_key(
        8, [KEY_EDGE, KEY_HI], KEY_FACE, [KEY_LO, KEY_EDGE], KEY_EDGE, KEY_FACE_TOP, KEY_FACE_BOT
    )
    hover = layered_key(
        8,
        [KEY_EDGE, KEY_HOVER_HI],
        KEY_HOVER_FACE,
        [KEY_LO, KEY_EDGE],
        KEY_EDGE,
        KEY_HOVER_TOP,
        KEY_HOVER_BOT,
    )
    pressed = layered_key(
        8,
        [KEY_EDGE, KEY_LO],
        KEY_PRESS_FACE,
        [KEY_FACE_TOP, KEY_EDGE],
        KEY_EDGE,
        KEY_PRESS_TOP,
        KEY_PRESS_BOT,
    )
    disabled = layered_key(
        8, [KEY_OFF_EDGE, KEY_OFF_HI], KEY_OFF, [KEY_OFF_BOT, KEY_OFF_EDGE], KEY_OFF_EDGE
    )
    return {
        "modkey_normal": normal,
        "modkey_hover": hover,
        "modkey_pressed": pressed,
        "modkey_disabled": disabled,
    }


def build() -> dict[str, Tile]:
    tiles = {
        "panel_case": panel_case(),
        "screen_frame": screen_frame(),
        "amber_frame": amber_frame(),
    }
    tiles.update(keycaps())
    tiles.update(modkeys())
    return tiles


def save_preview(tiles: dict[str, Tile]) -> None:
    """把所有素材放大 4 倍横向拼版，便于一眼比对各态差异。"""
    scale, gap = 4, 6
    cell = max(t.size for t in tiles.values()) * scale
    width = gap + len(tiles) * (cell + gap)
    height = cell + gap * 2
    sheet = Image.new("RGBA", (width, height), rgba("#1b1510"))
    x = gap
    for tile in tiles.values():
        big = tile.image.resize(
            (tile.size * scale, tile.size * scale), Image.Resampling.NEAREST
        )
        sheet.paste(big, (x, gap + (cell - big.height) // 2))
        x += cell + gap
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(PREVIEW)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tiles = build()
    for name, tile in tiles.items():
        path = OUT_DIR / f"{name}.png"
        tile.image.save(path)
        print(f"generated {path.relative_to(ROOT)} ({tile.size}x{tile.size})")
    save_preview(tiles)
    print(f"preview   {PREVIEW.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
