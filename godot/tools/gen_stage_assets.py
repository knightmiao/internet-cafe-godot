"""生成核心游戏区域首批像素素材。

1x 素材输出到 godot/assets/world/，4x 拼版输出到 docs/ui/preview/。
所有边缘均为整数像素、无抗锯齿，适合 Godot 最近邻采样。
"""

from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "godot/assets/world"
PREVIEW = ROOT / "docs/ui/preview/stage_assets@4x.png"

P = {
    "floor_a": "#cfb982", "floor_b": "#c9b178", "floor_line": "#b89f6c",
    "wood": "#765039", "wood_hi": "#b18459", "wood_lo": "#49301f",
    "wall": "#936846", "wall_hi": "#c99a68", "wall_lo": "#593a27",
    "cream": "#ffe9c9", "ink": "#2a1d12", "screen": "#263238",
    "screen_on": "#3a8fc5", "chair": "#527b84", "chair_lo": "#294f58",
    "tile": "#80a8a4", "tile_lo": "#507976", "green": "#7ea84e",
    "red": "#c0392b", "yellow": "#d4a017", "blue": "#3a8fc5",
    "gold": "#ffc257", "cyan": "#3ad1c8", "gray": "#77736a",
}


def rgba(c):
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def canvas(size, color=None):
    return Image.new("RGBA", size, rgba(color) if color else (0, 0, 0, 0))


def save(group, name, image):
    path = OUT / group
    path.mkdir(parents=True, exist_ok=True)
    image.save(path / f"{name}.png")


def floor_tile(base, accent):
    im = canvas((32, 32), base)
    d = ImageDraw.Draw(im)
    # 逻辑格仍为 32px，但视觉只呈现低对比的 8px 磨石子颗粒，不画任何格线。
    # 既不会像大地砖，也不会用高对比小棋盘抢走人物和设备的注意力。
    d.rectangle((16, 0, 31, 15), fill=rgba(accent))
    d.rectangle((0, 16, 15, 31), fill=rgba(accent))
    for gy in range(4):
        for gx in range(4):
            x, y = gx * 8, gy * 8
            d.point((x + 2 + gy % 2, y + 3), fill=rgba("#e1cea0"))
            d.point((x + 6, y + 6 - gx % 2), fill=rgba("#bca26d"))
    return im


def build_tiles():
    atlas = canvas((96, 32))
    atlas.paste(floor_tile(P["floor_a"], "#d2bd87"), (0, 0))
    atlas.paste(floor_tile(P["floor_b"], "#cdb57c"), (32, 0))
    wet = floor_tile(P["tile"], "#9fc0bb")
    d = ImageDraw.Draw(wet)
    for p in range(0, 32, 8):
        d.line((p, 0, p, 31), fill=rgba("#6f9995"))
        d.line((0, p, 31, p), fill=rgba("#6f9995"))
        d.line((p + 1, 1, p + 1, 30), fill=rgba("#9fc0bb"))
    atlas.paste(wet, (64, 0))
    save("tiles", "floor_atlas", atlas)

    wall = canvas((16, 16))
    d = ImageDraw.Draw(wall)
    # 伪 2.5D 墙：浅色顶面、砖面、底投影，不使用整圈描边。
    d.rectangle((0, 1, 15, 5), fill=rgba(P["wall_hi"]))
    d.line((0, 1, 15, 1), fill=rgba("#e0ba86"))
    d.rectangle((0, 6, 15, 12), fill=rgba(P["wall"]))
    d.line((0, 8, 15, 8), fill=rgba("#7c563b"))
    d.line((7, 6, 7, 8), fill=rgba("#6e4932"))
    d.line((3, 9, 3, 12), fill=rgba("#6e4932"))
    d.rectangle((0, 13, 15, 15), fill=rgba(P["wall_lo"]))
    save("tiles", "wall", wall)

    partition = canvas((16, 16))
    d = ImageDraw.Draw(partition)
    d.rectangle((0, 5, 15, 7), fill=rgba("#d1ae7c"))
    d.rectangle((0, 8, 15, 11), fill=rgba(P["wall"]))
    d.rectangle((0, 12, 15, 14), fill=rgba(P["wall_lo"]))
    d.point((3, 7), fill=rgba(P["cream"]))
    d.point((12, 7), fill=rgba(P["cream"]))
    save("tiles", "partition", partition)

    fence = canvas((16, 16))
    d = ImageDraw.Draw(fence)
    d.rectangle((1, 1, 3, 15), fill=rgba(P["wall_lo"]))
    d.rectangle((12, 1, 14, 15), fill=rgba(P["wall_lo"]))
    d.line((2, 4, 13, 13), fill=rgba(P["yellow"]), width=2)
    d.line((13, 4, 2, 13), fill=rgba("#e7b632"), width=2)
    save("tiles", "fence", fence)


def desk(kind):
    im = canvas((32, 16))
    d = ImageDraw.Draw(im)
    # 桌面是有厚度的横向体块：顶面5px、前脸5px、落地阴影2px。
    d.rectangle((0, 2, 31, 7), fill=rgba(P["wood_hi"]))
    d.line((0, 2, 31, 2), fill=rgba("#d0a06c"))
    d.line((0, 6, 31, 6), fill=rgba("#8d6241"))
    d.rectangle((0, 8, 31, 12), fill=rgba(P["wood"]))
    d.rectangle((0, 13, 31, 14), fill=rgba(P["wood_lo"]))
    d.rectangle((2, 15, 31, 15), fill=rgba("#5b432f"))
    # 零散划痕打破整齐框线感
    d.line((10, 4, 15, 4), fill=rgba("#9d7049"))
    d.point((25, 10), fill=rgba(P["wood_hi"]))
    if kind in ("left", "right"):
        x = 1 if kind == "left" else 29
        d.rectangle((x, 7, x + 2, 15), fill=rgba(P["wood_lo"]))
    # 联排隔板只立一根细柱，相邻桌面自然连成一体
    d.rectangle((30, 0, 31, 9), fill=rgba("#4d3928"))
    d.point((30, 0), fill=rgba(P["cream"]))
    return im


def build_stations():
    for kind in ("left", "mid", "right"):
        save("stations", f"desk_{kind}", desk(kind))

    im = canvas((24, 28))
    d = ImageDraw.Draw(im)
    # 地面投影让设备落在场景里，而不是浮在框内
    d.ellipse((3, 21, 22, 27), fill=rgba("#887552"))
    # 米灰色 CRT，有亮侧面与厚底座
    d.rectangle((3, 1, 20, 11), fill=rgba("#4b4338"))
    d.rectangle((4, 0, 19, 9), fill=rgba("#b8aa8e"))
    d.rectangle((6, 2, 17, 7), fill=rgba(P["screen_on"]))
    d.line((6, 2, 16, 2), fill=rgba("#67b2ca"))
    d.point((17, 8), fill=rgba(P["green"]))
    d.rectangle((10, 10, 13, 13), fill=rgba("#7a7262"))
    d.rectangle((7, 13, 16, 14), fill=rgba("#a79a80"))
    # 主机与键盘不共用统一描边
    d.rectangle((1, 9, 4, 19), fill=rgba("#45443e"))
    d.line((2, 11, 3, 11), fill=rgba("#8a8d83"))
    d.point((3, 17), fill=rgba(P["green"]))
    d.rectangle((7, 16, 18, 18), fill=rgba("#b9a67c"))
    d.line((9, 16, 16, 16), fill=rgba(P["cream"]))
    # 蓝绿色软椅：靠背、坐垫、轮脚分层
    d.rectangle((6, 20, 17, 24), fill=rgba(P["chair_lo"]))
    d.rectangle((7, 19, 16, 22), fill=rgba("#6c979a"))
    d.rectangle((5, 23, 18, 26), fill=rgba(P["chair"]))
    d.line((7, 26, 16, 26), fill=rgba(P["chair_lo"]))
    d.point((5, 27), fill=rgba(P["ink"]))
    d.point((18, 27), fill=rgba(P["ink"]))
    save("stations", "pc_station", im)


def sign_text(d, xy, text, fill):
    # Pillow 默认字体仅用于很小的拉丁标识；中文仍由 Godot Label 绘制。
    d.text(xy, text, fill=rgba(fill))


def build_facilities():
    entrance = canvas((48, 48))
    d = ImageDraw.Draw(entrance)
    # 透明背景的双扇玻璃门；门框各自有亮面和投影。
    d.rectangle((1, 3, 46, 6), fill=rgba(P["wall_hi"]))
    d.rectangle((2, 7, 5, 47), fill=rgba(P["wall_lo"]))
    d.rectangle((42, 7, 45, 47), fill=rgba(P["wall_lo"]))
    d.rectangle((6, 8, 22, 43), fill=rgba("#78aeb1"))
    d.rectangle((26, 8, 41, 43), fill=rgba("#78aeb1"))
    d.rectangle((8, 10, 11, 40), fill=rgba("#acd0cf"))
    d.rectangle((28, 10, 31, 40), fill=rgba("#acd0cf"))
    d.rectangle((23, 7, 25, 47), fill=rgba("#5f4934"))
    d.point((20, 26), fill=rgba(P["gold"])); d.point((28, 26), fill=rgba(P["gold"]))
    d.rectangle((16, 0, 31, 5), fill=rgba("#4f3422"))
    d.line((18, 2, 29, 2), fill=rgba(P["gold"]))
    save("facilities", "entrance", entrance)

    counter = canvas((96, 40))
    d = ImageDraw.Draw(counter)
    d.rectangle((3, 34, 94, 39), fill=rgba("#5a432f"))  # 投影
    d.rectangle((0, 4, 95, 11), fill=rgba("#c28d58"))  # 台面
    d.line((2, 4, 93, 4), fill=rgba("#e0b47b"))
    d.rectangle((3, 12, 92, 35), fill=rgba(P["wood"]))
    d.rectangle((6, 15, 44, 32), fill=rgba("#68442f"))
    d.rectangle((48, 15, 89, 32), fill=rgba("#80563a"))
    d.line((47, 13, 47, 34), fill=rgba(P["wood_lo"]))
    # 收银机、扫码枪、零钱盘
    d.rectangle((8, 0, 34, 14), fill=rgba("#4a453d"))
    d.rectangle((11, 2, 31, 8), fill=rgba("#244b55"))
    d.rectangle((13, 3, 28, 6), fill=rgba(P["screen_on"]))
    d.rectangle((16, 10, 38, 13), fill=rgba("#b4a487"))
    d.rectangle((60, 6, 70, 10), fill=rgba("#d4a017"))
    d.rectangle((74, 7, 88, 11), fill=rgba(P["cream"]))
    d.point((82, 9), fill=rgba(P["red"]))
    save("facilities", "counter", counter)

    shelf = canvas((64, 40))
    d = ImageDraw.Draw(shelf)
    d.rectangle((2, 37, 63, 39), fill=rgba("#5a432f"))
    d.rectangle((0, 4, 63, 37), fill=rgba(P["wood_lo"]))
    d.rectangle((3, 6, 60, 34), fill=rgba("#68442f"))
    d.rectangle((0, 0, 63, 6), fill=rgba("#b87943"))
    d.line((3, 1, 60, 1), fill=rgba("#e3ac68"))
    for y in (14, 25):
        d.rectangle((3, y, 60, y + 2), fill=rgba(P["wood_hi"]))
    colors = (P["red"], P["green"], P["yellow"], P["blue"])
    for row, y in enumerate((7, 17, 28)):
        for x in range(7, 58, 12):
            d.rectangle((x, y, x + 6, y + 6), fill=rgba(colors[(x // 12 + row) % 4]))
    save("facilities", "shelf", shelf)

    toilet = canvas((64, 80))
    d = ImageDraw.Draw(toilet)
    # 只画设施，湿区地砖交给 FloorLayer；不再用一整块青色矩形表示房间。
    d.ellipse((5, 5, 29, 16), fill=rgba("#6a8f8c"))  # 洗手台投影
    d.rectangle((4, 2, 28, 12), fill=rgba(P["cream"]))
    d.ellipse((8, 4, 24, 10), fill=rgba("#a6cfca"))
    d.rectangle((15, 0, 17, 4), fill=rgba("#6c7771"))
    d.rectangle((41, 2, 57, 20), fill=rgba(P["cream"]))
    d.ellipse((43, 5, 55, 16), fill=rgba("#a6cfca"))
    d.rectangle((44, 18, 54, 24), fill=rgba("#d9e4da"))
    # 半开的卫生间门与 WC 小牌
    d.rectangle((34, 38, 61, 72), fill=rgba("#4f3a2a"))
    d.polygon(((36, 39), (56, 44), (56, 69), (36, 71)), fill=rgba("#659a99"))
    d.line((38, 41, 53, 45), fill=rgba("#9cc2bc"))
    d.rectangle((10, 42, 28, 55), fill=rgba("#315f62"))
    sign_text(d, (13, 43), "WC", P["cream"])
    d.rectangle((8, 57, 27, 60), fill=rgba("#78938d"))
    d.rectangle((10, 61, 12, 74), fill=rgba("#6a7771"))
    d.rectangle((23, 61, 25, 74), fill=rgba("#6a7771"))
    save("facilities", "toilet", toilet)

    lock = canvas((64, 32))
    d = ImageDraw.Draw(lock)
    # 施工木牌而非 UI 卡片：不封闭四边，保留透明背景。
    d.polygon(((4, 5), (58, 2), (61, 23), (7, 27)), fill=rgba("#a57a4d"))
    d.line((7, 8, 57, 5), fill=rgba("#d4ab73"), width=2)
    d.line((9, 24, 58, 20), fill=rgba(P["wood_lo"]), width=2)
    d.rectangle((13, 25, 17, 31), fill=rgba(P["wall_lo"]))
    d.rectangle((50, 22, 54, 31), fill=rgba(P["wall_lo"]))
    d.rectangle((27, 10, 38, 21), fill=rgba("#5d402b"))
    d.rectangle((29, 5, 36, 13), outline=rgba("#5d402b"), width=2)
    save("facilities", "locked_sign", lock)

    crate = canvas((32, 24))
    d = ImageDraw.Draw(crate)
    d.polygon(((2, 6), (27, 3), (31, 18), (6, 22)), fill=rgba("#8f633e"))
    d.line((4, 8, 28, 5), fill=rgba("#c08b54"), width=2)
    d.line((7, 20, 30, 16), fill=rgba(P["wood_lo"]), width=2)
    d.line((5, 7, 29, 18), fill=rgba(P["wood_lo"]))
    d.line((28, 5, 7, 21), fill=rgba(P["wood_lo"]))
    save("facilities", "construction_crate", crate)


NPC_PALETTES = [
    ("#e5b98d", "#3f2a18", "#3a8fc5", "#243b53"),
    ("#d99a6c", "#1f1712", "#7a4a5c", "#3c2f5a"),
    ("#f0c7a2", "#70482c", "#6d8a3a", "#344a2e"),
    ("#c9865c", "#2a1d12", "#d4a017", "#5b3926"),
    ("#e8b28d", "#5c3a20", "#568b91", "#3b4654"),
    ("#b8734f", "#17120f", "#8b5e3c", "#263238"),
    ("#efc4a6", "#3b2620", "#c06958", "#4a355b"),
    ("#d89f78", "#70482c", "#4e7e76", "#3f3a2b"),
]


def npc_frame(palette, direction, phase):
    skin, hair, shirt, pants = palette
    im = canvas((16, 24))
    d = ImageDraw.Draw(im)
    # 椭圆投影、三段轮廓和不对称发型，让角色像 sprite 而不是拼接方块。
    d.ellipse((3, 20, 13, 23), fill=rgba("#8e7a58"))
    d.rectangle((5, 2, 10, 8), fill=rgba(skin))
    d.point((4, 4), fill=rgba(skin)); d.point((11, 4), fill=rgba(skin))
    d.rectangle((4, 1, 11, 3), fill=rgba(hair))
    d.point((4, 4), fill=rgba(hair))
    if phase % 2 == 0:
        d.point((10, 0), fill=rgba(hair))
    if direction == 0:  # 朝下
        d.point((6, 6), fill=rgba(P["ink"])); d.point((9, 6), fill=rgba(P["ink"]))
    elif direction == 1:
        d.point((5, 6), fill=rgba(P["ink"]))
    elif direction == 2:
        d.point((10, 6), fill=rgba(P["ink"]))
    # 肩膀比腰宽，衣服有高光和暗侧面
    d.rectangle((3, 10, 12, 14), fill=rgba(shirt))
    d.rectangle((4, 9, 11, 17), fill=rgba(shirt))
    d.line((4, 10, 4, 16), fill=rgba("#ffffff"))
    d.point((4, 10), fill=rgba(shirt))  # 高光仅留短线，避免发白
    d.rectangle((2, 11, 3, 16), fill=rgba(skin))
    d.rectangle((12, 11, 13, 16), fill=rgba(skin))
    d.point((2, 17), fill=rgba("#c98262"))
    d.point((13, 17), fill=rgba("#c98262"))
    # 走路相位
    left, right = (4, 9) if phase % 2 == 0 else (5, 8)
    d.rectangle((left, 18, left + 2, 22), fill=rgba(pants))
    d.rectangle((right, 18, right + 2, 22), fill=rgba(pants))
    d.point((left, 23), fill=rgba(P["ink"])); d.point((right + 2, 23), fill=rgba(P["ink"]))
    return im


def build_npcs():
    for i, palette in enumerate(NPC_PALETTES, 1):
        sheet = canvas((64, 96))
        for direction in range(4):
            for frame in range(4):
                sheet.alpha_composite(npc_frame(palette, direction, frame), (frame * 16, direction * 24))
        save("npc", f"customer_{i:02d}_walk", sheet)
        save("npc", f"customer_{i:02d}_idle", npc_frame(palette, 0, 0))

    boss = npc_frame(("#e4b188", "#3a2418", "#397d86", "#514233"), 0, 0)
    d = ImageDraw.Draw(boss)
    # 圆框眼镜、米色围裙和卷发碎点
    d.rectangle((4, 5, 7, 7), outline=rgba("#2a1d12"))
    d.rectangle((8, 5, 11, 7), outline=rgba("#2a1d12"))
    d.line((7, 6, 8, 6), fill=rgba("#2a1d12"))
    d.rectangle((6, 11, 9, 17), fill=rgba("#d8cfb4"))
    d.point((5, 0), fill=rgba("#3a2418")); d.point((8, 0), fill=rgba("#3a2418"))
    save("npc", "boss_idle", boss)

    cat = canvas((16, 12))
    d = ImageDraw.Draw(cat)
    d.ellipse((2, 4, 13, 11), fill=rgba("#eee6d6"))
    d.polygon(((3, 5), (4, 0), (7, 4)), fill=rgba("#725645"))
    d.polygon(((9, 4), (12, 0), (13, 6)), fill=rgba("#725645"))
    d.rectangle((5, 3, 10, 8), fill=rgba("#f3eee3"))
    d.point((6, 5), fill=rgba("#4e94c0")); d.point((9, 5), fill=rgba("#4e94c0"))
    d.point((8, 7), fill=rgba("#9c6959"))
    d.line((13, 7, 15, 4), fill=rgba("#725645"))
    save("npc", "cat_stage", cat)


def build_feedback():
    colors = {
        "off": P["gray"], "idle": P["green"], "busy": P["blue"],
        "dirty": P["yellow"], "broken": P["red"],
    }
    for name, color in colors.items():
        im = canvas((6, 6))
        d = ImageDraw.Draw(im)
        d.rectangle((0, 0, 5, 5), fill=rgba(P["ink"]))
        d.rectangle((1, 1, 4, 4), fill=rgba(color))
        save("feedback", f"state_{name}", im)

    sel = canvas((32, 32))
    d = ImageDraw.Draw(sel)
    for x, y, sx, sy in ((0, 0, 1, 1), (31, 0, -1, 1), (0, 31, 1, -1), (31, 31, -1, -1)):
        d.line((x, y, x + sx * 7, y), fill=rgba(P["gold"]), width=2)
        d.line((x, y, x, y + sy * 7), fill=rgba(P["gold"]), width=2)
    save("feedback", "selection", sel)

    for name, mark, color in (("wait", "!", P["yellow"]), ("checkout", "$", P["green"]),
                              ("order", "+", P["blue"]), ("angry", "!", P["red"])):
        im = canvas((16, 16))
        d = ImageDraw.Draw(im)
        d.polygon(((1, 1), (14, 1), (14, 11), (8, 11), (5, 15), (5, 11), (1, 11)),
                  fill=rgba(P["cream"]), outline=rgba(P["ink"]))
        sign_text(d, (5, 1), mark, color)
        save("feedback", f"bubble_{name}", im)


def build_decor():
    plant = canvas((16, 24))
    d = ImageDraw.Draw(plant)
    d.rectangle((4, 17, 11, 23), fill=rgba("#8b5e3c"))
    d.rectangle((6, 7, 9, 18), fill=rgba("#4f7b3a"))
    d.ellipse((1, 3, 8, 12), fill=rgba(P["green"]))
    d.ellipse((8, 1, 15, 11), fill=rgba("#6d9a45"))
    save("decor", "plant", plant)

    trash = canvas((16, 20))
    d = ImageDraw.Draw(trash)
    d.rectangle((3, 5, 12, 19), fill=rgba("#6d716b"), outline=rgba(P["ink"]))
    d.rectangle((2, 3, 13, 6), fill=rgba("#8b8e86"))
    save("decor", "trash_bin", trash)

    poster = canvas((16, 24))
    d = ImageDraw.Draw(poster)
    d.rectangle((0, 0, 15, 23), fill=rgba(P["wall_lo"]))
    d.rectangle((2, 2, 13, 20), fill=rgba("#7a4a5c"))
    d.polygon(((8, 4), (11, 10), (8, 17), (5, 10)), fill=rgba(P["gold"]))
    save("decor", "poster", poster)

    sign = canvas((32, 16))
    d = ImageDraw.Draw(sign)
    d.rectangle((0, 0, 31, 15), fill=rgba(P["ink"]), outline=rgba(P["gold"]))
    d.rectangle((3, 3, 28, 12), outline=rgba(P["cyan"]))
    save("decor", "light_sign", sign)

    ac = canvas((32, 16))
    d = ImageDraw.Draw(ac)
    d.rectangle((0, 1, 31, 14), fill=rgba(P["cream"]), outline=rgba(P["gray"]))
    d.line((5, 10, 26, 10), fill=rgba(P["tile_lo"]), width=2)
    save("decor", "aircon", ac)

    slot = canvas((16, 16))
    d = ImageDraw.Draw(slot)
    for p in range(0, 16, 4):
        d.line((p, 0, min(p + 2, 15), 0), fill=rgba(P["cyan"]))
        d.line((p, 15, min(p + 2, 15), 15), fill=rgba(P["cyan"]))
        d.line((0, p, 0, min(p + 2, 15)), fill=rgba(P["cyan"]))
        d.line((15, p, 15, min(p + 2, 15)), fill=rgba(P["cyan"]))
    save("decor", "slot", slot)


def build_preview():
    files = sorted(OUT.rglob("*.png"))
    thumb = 96
    cols = 8
    rows = (len(files) + cols - 1) // cols
    sheet = canvas((cols * thumb, rows * thumb), "#21160f")
    for i, path in enumerate(files):
        im = Image.open(path).convert("RGBA")
        scale = min(4, max(1, min(80 // im.width, 80 // im.height)))
        big = im.resize((im.width * scale, im.height * scale), Image.Resampling.NEAREST)
        x = (i % cols) * thumb + (thumb - big.width) // 2
        y = (i // cols) * thumb + (thumb - big.height) // 2
        sheet.alpha_composite(big, (x, y))
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(PREVIEW)


def main():
    build_tiles()
    build_stations()
    build_facilities()
    build_npcs()
    build_feedback()
    build_decor()
    build_preview()
    print(f"generated {len(list(OUT.rglob('*.png')))} assets -> {OUT.relative_to(ROOT)}")
    print(f"preview   {PREVIEW.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
