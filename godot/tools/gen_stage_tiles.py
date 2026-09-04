"""生成场景里不适合走生图管线的素材：地板/墙体 tile 与反馈小图标。

家具设施都由 import_stage_concepts.py 从概念稿像素化而来，但两类东西必须
留在代码里：

1. 地板与墙体要无缝平铺。生图给不出可对接的边缘，靠代码控制每个像素才能
   保证 tile 之间不出现接缝或错位的纹理。
2. 状态点、选中框、气泡是功能性反馈，需要在任何背景上都能一眼看清，颜色要
   精确可控，不能被概念稿的光影带跑。

配色从 import_stage_concepts.py 导出的家具素材里采样得来，保证地板和家具是
同一套色系；地板刻意压低明度与饱和度，让深棕家具和青蓝机位能立在上面。
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "godot/assets/world"
PREVIEW = ROOT / "docs/ui/preview/stage_tiles@4x.png"

# 地图基准格 64px，物件吸附 32px 子网格（旧体系的 2 倍）
TILE = 64
WALL = 32

P = {
    # 地板：中性偏暗、低饱和。A/B 两格底色刻意完全相同，只有颗粒分布不同，
    # 否则平铺后明度差会拼出一张 64px 的大棋盘，正是要避免的"地砖太大"。
    "floor_a": "#8a6f4d", "floor_a_hi": "#907550", "floor_a_lo": "#84694a",
    "floor_b": "#8a6f4d", "floor_b_hi": "#907550", "floor_b_lo": "#84694a",
    # 卫生间湿区，取自 toilet 素材的青绿后压暗，免得地面比墙还跳
    "tile_wet": "#4d7d59", "tile_wet_hi": "#588a63", "tile_wet_lo": "#325343",
    # 高配待装修区：裸水泥
    "raw": "#6b6358", "raw_hi": "#776e61", "raw_lo": "#5c554c",
    # 墙体，取自家具木质色阶
    "wall_top": "#955517", "wall_face": "#4e280b", "wall_lo": "#371d09",
    "wall_edge": "#1c1208",
    # 功能色
    "idle": "#7ea84e", "busy": "#3a8fc5", "dirty": "#d4a017",
    "broken": "#c0392b", "off": "#77736a",
    "ink": "#141a16", "cream": "#f5d790", "gold": "#ffc257", "cyan": "#3ad1c8",
}


def rgba(color: str, alpha: int = 255) -> tuple[int, int, int, int]:
    color = color.lstrip("#")
    return tuple(int(color[i:i + 2], 16) for i in (0, 2, 4)) + (alpha,)


def canvas(size: tuple[int, int], color: str | None = None) -> Image.Image:
    return Image.new("RGBA", size, rgba(color) if color else (0, 0, 0, 0))


def save(group: str, name: str, image: Image.Image) -> Image.Image:
    path = OUT / group
    path.mkdir(parents=True, exist_ok=True)
    image.save(path / f"{name}.png")
    return image


def _noise(x: int, y: int, seed: int) -> int:
    """整数坐标 hash，用来撒稳定的伪随机颗粒。"""
    value = (x * 374761393 + y * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    value = ((value ^ (value >> 13)) * 1274126177) & 0xFFFFFFFF
    return value ^ (value >> 16)


def speckle_floor(base: str, hi: str, lo: str, seed: int) -> Image.Image:
    """磨石地面：稀疏、低对比的单像素颗粒，不画任何格线。

    颗粒按坐标 hash 撒点而不是按固定网格摆，避免出现可见的点阵韵律；密度
    压到约 6%，色差只有两三个色阶，远看是均匀水磨石，近看才有细颗粒。
    """
    image = canvas((TILE, TILE), base)
    draw = ImageDraw.Draw(image)
    for y in range(TILE):
        for x in range(TILE):
            roll = _noise(x, y, seed) % 100
            if roll < 3:
                draw.point((x, y), fill=rgba(hi))
            elif roll < 6:
                draw.point((x, y), fill=rgba(lo))
    return image


def wet_tiles() -> Image.Image:
    """卫生间 16px 小瓷砖，缝隙压在 16 的整数位上，平铺后接缝连续。"""
    image = canvas((TILE, TILE), P["tile_wet"])
    draw = ImageDraw.Draw(image)
    for offset in range(0, TILE, 16):
        draw.line((offset, 0, offset, TILE - 1), fill=rgba(P["tile_wet_lo"]))
        draw.line((0, offset, TILE - 1, offset), fill=rgba(P["tile_wet_lo"]))
        draw.line((offset + 1, 1, offset + 1, TILE - 1), fill=rgba(P["tile_wet_hi"]))
        draw.line((1, offset + 1, TILE - 1, offset + 1), fill=rgba(P["tile_wet_hi"]))
    return image


def build_floor_atlas() -> Image.Image:
    """四格 atlas：普通地板 A/B 交错、卫生间湿区、高配区裸水泥。"""
    atlas = canvas((TILE * 4, TILE))
    atlas.paste(speckle_floor(P["floor_a"], P["floor_a_hi"], P["floor_a_lo"], 1), (0, 0))
    atlas.paste(speckle_floor(P["floor_b"], P["floor_b_hi"], P["floor_b_lo"], 4), (TILE, 0))
    atlas.paste(wet_tiles(), (TILE * 2, 0))
    atlas.paste(speckle_floor(P["raw"], P["raw_hi"], P["raw_lo"], 7), (TILE * 3, 0))
    return save("tiles", "floor_atlas", atlas)


def wall_horizontal() -> Image.Image:
    """横墙：上沿受光顶面 + 正面 + 落地投影，左右边缘不封口所以横向无缝。"""
    image = canvas((WALL, WALL))
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, WALL - 1, 9), fill=rgba(P["wall_top"]))
    draw.rectangle((0, 10, WALL - 1, 25), fill=rgba(P["wall_face"]))
    draw.rectangle((0, 26, WALL - 1, WALL - 1), fill=rgba(P["wall_lo"]))
    draw.line((0, 9, WALL - 1, 9), fill=rgba(P["wall_edge"]))
    # 每格只留一道竖纹，再密就成木栅栏了
    draw.line((15, 13, 15, 24), fill=rgba(P["wall_lo"]))
    return save("tiles", "wall", image)


def wall_vertical() -> Image.Image:
    """竖墙：左受光右背光，上下边缘不封口所以纵向无缝。"""
    image = canvas((WALL, WALL), P["wall_face"])
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, 8, WALL - 1), fill=rgba(P["wall_top"]))
    draw.line((9, 0, 9, WALL - 1), fill=rgba(P["wall_edge"]))
    draw.rectangle((26, 0, WALL - 1, WALL - 1), fill=rgba(P["wall_lo"]))
    for y in (7, 23):
        draw.line((12, y, 24, y), fill=rgba(P["wall_lo"]))
    return save("tiles", "wall_v", image)


def state_dots() -> list[Image.Image]:
    """机位状态点：12x12，实心圆加暗描边，任何背景上都能读出来。"""
    made = []
    for name, color in (
        ("idle", P["idle"]), ("busy", P["busy"]), ("dirty", P["dirty"]),
        ("broken", P["broken"]), ("off", P["off"]),
    ):
        image = canvas((12, 12))
        draw = ImageDraw.Draw(image)
        draw.ellipse((0, 0, 11, 11), fill=rgba(P["ink"]))
        draw.ellipse((1, 1, 10, 10), fill=rgba(color))
        # 左上高光，让点看起来是个小灯而不是色块
        draw.point((4, 3), fill=rgba(P["cream"]))
        draw.point((3, 4), fill=rgba(P["cream"]))
        made.append(save("feedback", f"state_{name}", image))
    return made


def selection_box() -> Image.Image:
    """选中框：64x64 四角金色角标，中间留空不挡物件。"""
    image = canvas((64, 64))
    draw = ImageDraw.Draw(image)
    arm = 14
    for cx, cy, dx, dy in ((0, 0, 1, 1), (63, 0, -1, 1), (0, 63, 1, -1), (63, 63, -1, -1)):
        for thickness in range(2):
            draw.line(
                (cx + dx * thickness, cy + dy * thickness,
                 cx + dx * arm, cy + dy * thickness),
                fill=rgba(P["gold"]),
            )
            draw.line(
                (cx + dx * thickness, cy + dy * thickness,
                 cx + dx * thickness, cy + dy * arm),
                fill=rgba(P["gold"]),
            )
    return save("feedback", "selection", image)


def bubbles() -> list[Image.Image]:
    """顾客需求气泡：32x32 圆角框 + 尾巴 + 符号。

    符号一律用 3px 以上的实心块画。单像素线条在 0.5 倍相机下会直接消失，
    远看只剩一个空白气泡，什么需求都读不出来。
    """
    accents = {
        "wait": P["busy"], "checkout": P["idle"],
        "order": P["dirty"], "angry": P["broken"],
    }
    made = []
    for name, accent in accents.items():
        image = canvas((32, 32))
        draw = ImageDraw.Draw(image)
        draw.rounded_rectangle((2, 2, 29, 23), radius=5, fill=rgba(P["ink"]))
        draw.rounded_rectangle((3, 3, 28, 22), radius=4, fill=rgba(P["cream"]))
        # 指向角色头顶的尾巴
        draw.polygon([(11, 22), (19, 22), (13, 30)], fill=rgba(P["ink"]))
        draw.polygon([(12, 22), (17, 22), (13, 28)], fill=rgba(P["cream"]))

        color = rgba(accent)
        if name == "wait":
            # 排队等待：省略号
            for x in (8, 14, 20):
                draw.rectangle((x, 11, x + 3, 14), fill=color)
        elif name == "checkout":
            # 结账：铜钱，圆环加方孔
            draw.ellipse((9, 6, 22, 19), fill=color)
            draw.ellipse((12, 9, 19, 16), fill=rgba(P["cream"]))
            draw.rectangle((14, 11, 17, 14), fill=color)
        elif name == "order":
            # 点单：一只饮料杯
            draw.polygon([(11, 7), (21, 7), (19, 19), (13, 19)], fill=color)
            draw.rectangle((9, 5, 23, 8), fill=color)
        else:
            # 不满：感叹号
            draw.rectangle((14, 5, 18, 15), fill=color)
            draw.rectangle((14, 17, 18, 20), fill=color)
        made.append(save("feedback", f"bubble_{name}", image))
    return made


def decor_slot() -> Image.Image:
    """空装修槽指示：32x32 青色虚线框，只在装修预览态显示。"""
    image = canvas((32, 32))
    draw = ImageDraw.Draw(image)
    for offset in range(0, 32, 6):
        draw.line((offset, 0, min(offset + 3, 31), 0), fill=rgba(P["cyan"]))
        draw.line((offset, 31, min(offset + 3, 31), 31), fill=rgba(P["cyan"]))
        draw.line((0, offset, 0, min(offset + 3, 31)), fill=rgba(P["cyan"]))
        draw.line((31, offset, 31, min(offset + 3, 31)), fill=rgba(P["cyan"]))
    return save("decor", "slot", image)


def build_preview(images: list[Image.Image], zoom: int = 4) -> None:
    cell = max(max(i.width, i.height) for i in images) * zoom + 16
    cols = 6
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGBA", (cell * cols, cell * rows), (36, 26, 18, 255))
    for index, image in enumerate(images):
        big = image.resize((image.width * zoom, image.height * zoom), Image.Resampling.NEAREST)
        x = (index % cols) * cell + (cell - big.width) // 2
        y = (index // cols) * cell + (cell - big.height) // 2
        sheet.alpha_composite(big, (x, y))
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(PREVIEW)
    print(f"preview {PREVIEW} ({sheet.width}x{sheet.height})")


def main() -> None:
    made = [build_floor_atlas(), wall_horizontal(), wall_vertical()]
    made += state_dots()
    made.append(selection_box())
    made += bubbles()
    made.append(decor_slot())
    print(f"生成 {len(made)} 个 tile 与反馈素材，地板 {TILE}px，墙体 {WALL}px")
    build_preview(made)


if __name__ == "__main__":
    main()
