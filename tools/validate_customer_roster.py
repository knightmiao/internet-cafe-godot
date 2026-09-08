#!/usr/bin/env python3
"""校验 50 人顾客数据与像素素材，生成阵容预览并同步布局草图。"""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "godot/data/customers.json"
NPC_DIR = ROOT / "godot/assets/world/npc"
PORTRAIT_DIR = ROOT / "godot/assets/ui/portraits"
PREVIEW = ROOT / "docs/ui/preview/customers_roster@4x.png"
SKETCH = ROOT / "docs/ui/布局草图-像素风.html"
REQUIRED_FIELDS = {
    "id", "name", "gender", "age", "occupation", "outfit_style",
    "height_cm", "height_class", "hair_type", "hair_color",
    "internet_habit", "sprite", "sprite_sit", "portrait",
}
AGE_BANDS = [(18, 24), (25, 34), (35, 44), (45, 54), (55, 60)]


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/STHeiti Medium.ttc",
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def validate(roster: list[dict]) -> None:
    assert len(roster) == 50, f"角色数错误：{len(roster)}"
    assert Counter(p["gender"] for p in roster) == {"男": 30, "女": 20}
    assert [p["age"] for p in roster].count(18) > 0
    assert [p["age"] for p in roster].count(60) > 0
    assert len({p["id"] for p in roster}) == 50
    assert len({p["name"] for p in roster}) == 50
    assert all(REQUIRED_FIELDS <= p.keys() for p in roster)
    assert all(18 <= p["age"] <= 60 for p in roster)
    assert all(150 <= p["height_cm"] <= 188 for p in roster)
    assert all(
        sum(low <= p["age"] <= high for p in roster) == 10
        for low, high in AGE_BANDS
    )
    assert len({p["occupation"] for p in roster}) >= 20
    assert len({p["internet_habit"]["type"] for p in roster}) == 7

    for index, person in enumerate(roster, 1):
        expected_id = f"customer_{index:02d}"
        assert person["id"] == expected_id
        path = NPC_DIR / f"{expected_id}_idle.png"
        assert path.exists(), f"缺少素材：{path}"
        image = Image.open(path).convert("RGBA")
        assert image.size == (32, 72), f"{path.name} 尺寸为 {image.size}"
        alpha = image.getchannel("A")
        extrema = alpha.getextrema()
        assert extrema == (0, 255), f"{path.name} 透明度异常：{extrema}"
        assert 250 < sum(1 for value in alpha.get_flattened_data() if value > 0) < 2304
        sit_path = NPC_DIR / f"{expected_id}_sit.png"
        assert sit_path.exists(), f"缺少坐姿：{sit_path}"
        sit = Image.open(sit_path).convert("RGBA")
        assert sit.size == (32, 40), f"{sit_path.name} 尺寸为 {sit.size}"
        sit_alpha = sit.getchannel("A")
        assert sit_alpha.getextrema() == (0, 255), f"{sit_path.name} 透明度异常"
        assert 180 < sum(1 for value in sit_alpha.get_flattened_data() if value > 0) < 1280
        portrait_path = PORTRAIT_DIR / f"portrait_{expected_id}.png"
        assert portrait_path.exists(), f"缺少立绘：{portrait_path}"
        portrait = Image.open(portrait_path).convert("RGBA")
        assert portrait.size == (144, 96), f"{portrait_path.name} 尺寸为 {portrait.size}"
        portrait_alpha = portrait.getchannel("A")
        assert portrait_alpha.getextrema() == (0, 255), f"{portrait_path.name} 透明度异常"


def build_preview(roster: list[dict]) -> None:
    cols, rows = 5, 10
    cell_w, cell_h = 180, 350
    canvas = Image.new("RGB", (cols * cell_w, rows * cell_h), "#241a12")
    draw = ImageDraw.Draw(canvas)
    title_font = font(16)
    body_font = font(13)

    for index, person in enumerate(roster):
        col, row = index % cols, index // cols
        x, y = col * cell_w, row * cell_h
        draw.rectangle((x + 3, y + 3, x + cell_w - 4, y + cell_h - 4), fill="#352518", outline="#765039", width=2)
        sprite = Image.open(NPC_DIR / f"{person['id']}_idle.png").convert("RGBA")
        sprite = sprite.resize((128, 288), Image.Resampling.NEAREST)
        canvas.paste(sprite, (x + 26, y + 4), sprite)
        draw.text((x + 10, y + 292), f"{person['id'][-2:]}  {person['name']}", font=title_font, fill="#ffe9c9")
        draw.text(
            (x + 10, y + 316),
            f"{person['gender']} {person['age']}岁  {person['height_cm']}cm  {person['occupation']}",
            font=body_font,
            fill="#d4b078",
        )
        draw.text(
            (x + 10, y + 334),
            person["internet_habit"]["type"],
            font=body_font,
            fill="#75b8c4",
        )

    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(PREVIEW)


def sync_sketch(roster: list[dict]) -> None:
    """把精简人设注入布局草图，避免草图里再手抄一份数据。"""
    payload = [
        {
            "id": person["id"],
            "name": person["name"],
            "gender": person["gender"],
            "age": person["age"],
            "height_cm": person["height_cm"],
            "occupation": person["occupation"],
            "habit": person["internet_habit"]["type"],
        }
        for person in roster
    ]
    block = json.dumps(payload, ensure_ascii=False, indent=1)
    html = SKETCH.read_text(encoding="utf-8")
    pattern = re.compile(
        r'(<script id="roster-data" type="application/json">\n).*?(\n</script>)',
        re.DOTALL,
    )
    updated, count = pattern.subn(
        lambda m: m.group(1) + block + m.group(2), html, count=1
    )
    assert count == 1, "布局草图里找不到 roster-data 数据块"
    SKETCH.write_text(updated, encoding="utf-8")


def main() -> None:
    roster = json.loads(DATA.read_text(encoding="utf-8"))
    validate(roster)
    build_preview(roster)
    sync_sketch(roster)
    genders = Counter(p["gender"] for p in roster)
    print(
        f"validated {len(roster)} 人：男 {genders['男']} / 女 {genders['女']}，"
        f"年龄 18–60，职业 {len({p['occupation'] for p in roster})} 种"
    )
    print(f"preview {PREVIEW}")
    print(f"sketch  {SKETCH}")


if __name__ == "__main__":
    main()
