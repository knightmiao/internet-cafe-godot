"""把 docs/ui/concept/ 的生图概念稿批量转成 assets/world/ 的场景素材。

管线：抠洋红 chroma key → 按空白带把拼版切成单个物件 → 预乘 alpha 面积平均
降采样 → 全局统一调色板。最后一步是画风统一的关键：逐个素材独立量化会让
同一块木头在不同家具上偏色，这里先汇总所有物件采样出一套共用调色板，再把
每个素材映射进去。

用法：
    python3 godot/tools/import_stage_concepts.py --measure   # 只看切分与比例
    python3 godot/tools/import_stage_concepts.py             # 实际导出素材
"""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

from pixelize_object import downsample, key_out, pad_to_ratio, trim

ROOT = Path(__file__).resolve().parents[2]
CONCEPT_DIR = ROOT / "docs/ui/concept"
ASSET_DIR = ROOT / "godot/assets/world"
PREVIEW = ROOT / "docs/ui/preview/stage_assets@4x.png"

# 调色板分两组。家具建筑要共享同一套木质与布面色阶才不会互相偏色；角色则要
# 保住 8 套发色和服装色的色相差异，混在一起量化会把粉发压成橙、紫衣压成灰，
# 顾客就认不出来了。这是像素游戏常见的 tileset / character 双调色板分法。
PALETTE_COLORS = {"world": 64, "npc": 96, "pc_portrait": 96}
# 每个素材参与调色板采样的像素配额，保证大小素材平权
PALETTE_QUOTA = 4000
# 五人拼版里部分角色衣摆距离较近，12px 空白已足够稳定区分；内部肢体不会在
# 整个角色高度上形成贯通空列，因此不会误切人物。
MIN_GAP = 12

# 概念稿 -> 目标素材。尺寸按 32px 子网格体系取整，顺序即拼版的阅读顺序
SHEETS: list[tuple[str, str, list[tuple[str, tuple[int, int]]]]] = [
    # 六代单座机位用于场景内逐台显示，不能再依赖整排底图，否则单台升级后
    # 无法换外观。详情图与场景图分开生图，用独立 96 色组保住灯效和材质。
    *[
        (
            f"pc_station_gen_{generation}",
            "world",
            [(f"stations/station_gen_{generation}", (64, 68))],
        )
        for generation in ["09", "10", "20", "30", "40", "50"]
    ],
    *[
        (
            f"pc_portrait_gen_{generation}",
            "pc_portrait",
            [(f"ui/portraits/portrait_pc_gen_{generation}", (144, 96))],
        )
        for generation in ["09", "10", "20", "30", "40", "50"]
    ],
    # 联排共用一张连续桌面，横向 64px 一个座位节拍。概念稿用了近 70 度的陡
    # 俯视，所以桌深只有 68px：四排并列时排间还能留出走道，椅子不会被前排
    # 桌面压掉。之前 3/4 视角的版本桌深 144，四排必然互相吃掉。
    ("station_row_4", "world", [("stations/station_row_4", (256, 68))]),
    ("station_row_2", "world", [("stations/station_row_2", (128, 68))]),
    ("counter_desk", "world", [("facilities/counter", (192, 100))]),
    ("shelf", "world", [("facilities/shelf", (128, 128))]),
    ("toilet", "world", [("facilities/toilet", (128, 192))]),
    ("entrance", "world", [("facilities/entrance", (96, 124))]),
    ("construction", "world", [
        ("facilities/locked_sign", (64, 72)),
        ("facilities/hazard_fence", (64, 44)),
        ("facilities/construction_crate", (64, 80)),
    ]),
    ("decor_set", "world", [
        ("decor/plant", (32, 72)),
        ("decor/trash_bin", (32, 42)),
        ("decor/poster", (32, 54)),
        ("decor/light_sign", (64, 64)),
    ]),
    # 角色统一 32x72，十张五人拼版按 ID 顺序导入。50 人需要保留更多发色、
    # 肤色与职业服装色，因此 NPC 组使用 96 色共享调色板。
    *[
        (
            f"customers_{start:02d}_{start + 4:02d}",
            "npc",
            [
                (f"npc/customer_{i:02d}_idle", (32, 72))
                for i in range(start, start + 5)
            ],
        )
        for start in range(1, 51, 5)
    ],
    ("boss_cat", "npc", [
        ("npc/boss_idle", (32, 72)),
        ("npc/cat_stage", (40, 48)),
    ]),
]


def _bands(occupied: np.ndarray, min_gap: int) -> list[tuple[int, int]]:
    """把一维占用序列切成若干区间，忽略短于 min_gap 的空隙。"""
    runs: list[list[int]] = []
    index = 0
    total = len(occupied)
    while index < total:
        if occupied[index]:
            end = index
            while end + 1 < total and occupied[end + 1]:
                end += 1
            runs.append([index, end])
            index = end + 1
        else:
            index += 1

    merged: list[list[int]] = []
    for run in runs:
        if merged and run[0] - merged[-1][1] - 1 < min_gap:
            merged[-1][1] = run[1]
        else:
            merged.append(run)
    # 4px 以下当噪点丢掉，避免抠图残留被当成物件
    return [(a, b) for a, b in merged if b - a >= 4]


def split_sheet(image: Image.Image, min_gap: int = MIN_GAP) -> list[Image.Image]:
    """按空白带把拼版切成单个物件，行优先返回。"""
    alpha = np.asarray(image)[..., 3] > 0
    parts: list[Image.Image] = []
    for top, bottom in _bands(alpha.any(axis=1), min_gap):
        strip = alpha[top:bottom + 1]
        for left, right in _bands(strip.any(axis=0), min_gap):
            parts.append(trim(image.crop((left, top, right + 1, bottom + 1))))
    return parts


def collect() -> list[tuple[str, str, tuple[int, int], Image.Image]]:
    """切分所有拼版并降采样，返回未量化的素材列表。"""
    result = []
    for sheet_name, group, targets in SHEETS:
        source = CONCEPT_DIR / f"{sheet_name}.png"
        keyed = key_out(Image.open(source))
        parts = [trim(keyed)] if len(targets) == 1 else split_sheet(keyed)
        if len(parts) != len(targets):
            raise SystemExit(
                f"{sheet_name}: 切出 {len(parts)} 个物件，清单要求 {len(targets)} 个。"
                f"可调整 MIN_GAP 或检查概念稿间隔"
            )
        for (name, size), part in zip(targets, parts):
            padded = pad_to_ratio(part, size[0] / size[1])
            result.append((name, group, size, downsample(padded, *size)))
    return result


def build_palette(images: list[Image.Image], colors: int) -> Image.Image:
    """汇总所有物件的不透明像素，采样出一套共用调色板。

    每个素材等量参与：直接堆全部像素的话，联排(36864 px)会盖过绿植(2304 px)，
    调色板被木棕吃满，绿色和商品色就掉了。这里按固定配额均匀重采样，素材内部
    仍保留像素频率，素材之间则平权。
    """
    samples = []
    for image in images:
        arr = np.asarray(image)
        pixels = arr[arr[..., 3] > 0][:, :3]
        if len(pixels) == 0:
            continue
        picks = np.linspace(0, len(pixels) - 1, PALETTE_QUOTA).astype(int)
        samples.append(pixels[picks])
    stacked = np.concatenate(samples, axis=0)
    side = int(np.ceil(np.sqrt(len(stacked))))
    canvas = np.zeros((side * side, 3), dtype=np.uint8)
    canvas[:len(stacked)] = stacked
    flat = Image.fromarray(canvas.reshape(side, side, 3), "RGB")
    return flat.quantize(
        colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE
    )


def apply_palette(image: Image.Image, palette: Image.Image) -> Image.Image:
    arr = np.asarray(image).copy()
    opaque = arr[..., 3] > 0
    if not opaque.any():
        return image
    fill = np.median(arr[opaque][:, :3], axis=0).astype(np.uint8)
    arr[~opaque, :3] = fill
    mapped = Image.fromarray(arr[..., :3], "RGB").quantize(
        palette=palette, dither=Image.Dither.NONE
    ).convert("RGB")
    return Image.fromarray(
        np.dstack([np.asarray(mapped), arr[..., 3]]).astype(np.uint8), "RGBA"
    )


def build_preview(items: list[tuple[str, Image.Image]], zoom: int = 4) -> None:
    cell_w = max(image.width for _, image in items) * zoom + 16
    cell_h = max(image.height for _, image in items) * zoom + 16
    cols = 5
    rows = (len(items) + cols - 1) // cols
    sheet = Image.new("RGBA", (cell_w * cols, cell_h * rows), (36, 26, 18, 255))
    for index, (_, image) in enumerate(items):
        big = image.resize((image.width * zoom, image.height * zoom), Image.Resampling.NEAREST)
        x = (index % cols) * cell_w + (cell_w - big.width) // 2
        y = (index // cols) * cell_h + (cell_h - big.height) // 2
        sheet.alpha_composite(big, (x, y))
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(PREVIEW)
    print(f"preview {PREVIEW} ({sheet.width}x{sheet.height})")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--measure", action="store_true",
                        help="只打印切分结果与原始宽高比，不写素材")
    args = parser.parse_args()

    if args.measure:
        for sheet_name, _group, targets in SHEETS:
            keyed = key_out(Image.open(CONCEPT_DIR / f"{sheet_name}.png"))
            parts = [trim(keyed)] if len(targets) == 1 else split_sheet(keyed)
            print(f"\n{sheet_name}: 切出 {len(parts)} / 需要 {len(targets)}")
            for i, part in enumerate(parts):
                target = targets[i][1] if i < len(targets) else None
                name = targets[i][0] if i < len(targets) else "?"
                ratio = part.width / part.height
                note = ""
                if target:
                    want = target[0] / target[1]
                    note = f" 目标 {target[0]}x{target[1]} 比例 {want:.2f} 差 {ratio - want:+.2f}"
                print(f"  {name:28} {part.width:>4}x{part.height:<4} 比例 {ratio:.2f}{note}")
        return

    collected = collect()
    palettes = {
        group: build_palette(
            [image for _, g, _, image in collected if g == group], colors
        )
        for group, colors in PALETTE_COLORS.items()
    }

    items = []
    for name, group, size, image in collected:
        final = apply_palette(image, palettes[group])
        # 世界素材默认写进 assets/world；右栏详情以 ui/ 开头，写进 assets 根目录。
        path = (
            ROOT / "godot/assets" / f"{name}.png"
            if name.startswith("ui/")
            else ASSET_DIR / f"{name}.png"
        )
        path.parent.mkdir(parents=True, exist_ok=True)
        final.save(path)
        items.append((name, final))
        print(f"{name:30} {size[0]:>3}x{size[1]:<3} [{group}]")
    summary = "，".join(f"{g} {c} 色" for g, c in PALETTE_COLORS.items())
    print(f"\n共 {len(items)} 个素材，调色板：{summary}")
    build_preview(items)


if __name__ == "__main__":
    main()
