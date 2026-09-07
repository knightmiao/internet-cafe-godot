#!/usr/bin/env python3
"""生成首批 24 项装修目录。"""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "godot/data/decor_catalog.json"


def entry(
    id: str, name: str, category: str, tags: list[str], price: int,
    unlock: int, size: tuple[int, int] | None, description: str,
    decor: int, clean: int, comfort: int, reputation: int, traffic: int,
) -> dict:
    is_theme = category == "theme"
    return {
        "id": id,
        "name": name,
        "category": category,
        "tags": tags,
        "price": price,
        "unlock_level": unlock,
        "description": description,
        "scene_size": list(size) if size else None,
        "scene_asset": "" if is_theme else f"res://assets/world/decor/{id}.png",
        "portrait": f"res://assets/ui/portraits/decor_{id}.png",
        "theme_floor": f"res://assets/world/themes/{id}_floor.png" if is_theme else "",
        "theme_wall": f"res://assets/world/themes/{id}_wall.png" if is_theme else "",
        "theme_wall_v": f"res://assets/world/themes/{id}_wall_v.png" if is_theme else "",
        "bonuses": {
            "decor": decor,
            "clean": clean,
            "comfort": comfort,
            "reputation": reputation,
            "traffic": traffic,
        },
    }


CATALOG = [
    entry("theme_old", "老旧县城", "theme", ["theme"], 0, 1, None,
          "磨石地面、深棕护墙板与暖黄旧灯，是开局自带的朴素环境。", 0, 0, 0, 0, 0),
    entry("theme_wood", "木质温馨", "theme", ["theme"], 360, 2, None,
          "浅木地面、奶油墙面和暖色灯光，适合休闲与长时间上网。", 12, 0, 8, 3, 2),
    entry("theme_redblack", "红黑电竞", "theme", ["theme"], 520, 3, None,
          "炭黑地面、红色灯带与电竞墙板，强化开黑氛围。", 18, 0, 4, 8, 5),
    entry("theme_minimal", "深色极简", "theme", ["theme"], 680, 4, None,
          "深灰吸音材质与冷蓝引导灯，安静克制且易于维护。", 22, 3, 8, 10, 4),
    entry("theme_white", "白色科技", "theme", ["theme"], 860, 5, None,
          "浅灰地板、白色墙面和青绿灯光，明亮整洁。", 28, 8, 10, 14, 6),
    entry("theme_neon", "未来霓虹", "theme", ["theme"], 1200, 6, None,
          "石墨地面配电光青紫灯带，面向旗舰高配区。", 36, 2, 12, 22, 10),

    entry("wall_ac", "壁挂空调", "function", ["ac", "wall"], 180, 1, (64, 40),
          "基础温控设备，改善闷热环境。", 4, 1, 6, 1, 1),
    entry("floor_ac", "立柜空调", "function", ["ac", "utility"], 360, 3, (48, 80),
          "覆盖范围更大的柜式空调。", 8, 2, 12, 3, 2),
    entry("fresh_air", "新风机", "function", ["air", "wall"], 420, 3, (64, 40),
          "持续换气，降低异味和拥挤带来的不适。", 8, 8, 9, 3, 2),
    entry("gaming_light", "电竞灯具", "function", ["light", "wall"], 240, 2, (64, 32),
          "带柔和灯带的吸顶灯，提升区域氛围。", 8, 0, 3, 6, 2),
    entry("acoustic_panel", "隔音板", "function", ["sound", "wall"], 260, 2, (64, 48),
          "降低键盘和开黑噪声对相邻区域的影响。", 7, 0, 8, 3, 1),
    entry("vending_machine", "自动售货机", "function", ["vending", "floor"], 500, 3, (64, 112),
          "自动出售饮料零食，补充服务收入。", 12, 0, 5, 5, 5),

    entry("waiting_bench", "等候长椅", "comfort", ["seat", "floor"], 140, 1, (96, 48),
          "让排队顾客不必一直站着。", 5, 0, 8, 2, 1),
    entry("lounge_sofa", "休息沙发", "comfort", ["seat", "floor"], 320, 2, (96, 64),
          "柔软的双人沙发，适合等候和短暂休息。", 10, 0, 14, 5, 2),
    entry("plant_large", "大型绿植", "comfort", ["plant", "floor"], 120, 1, (48, 96),
          "高大的室内绿植，柔化设备密集感。", 6, 2, 5, 3, 1),
    entry("charging_locker", "手机充电柜", "comfort", ["charge", "utility"], 380, 3, (64, 96),
          "带独立小格的安全充电柜。", 8, 0, 9, 5, 3),
    entry("water_dispenser", "饮水机", "comfort", ["water", "utility"], 160, 1, (48, 80),
          "提供冷热饮水，增加长时间上网舒适度。", 5, 2, 7, 2, 1),

    entry("poster_set", "电竞海报组", "ambience", ["poster", "wall"], 90, 1, (64, 48),
          "一组三联电竞主题海报。", 5, 0, 1, 4, 1),
    entry("neon_cat", "猫咪霓虹灯", "ambience", ["sign", "wall"], 280, 2, (64, 64),
          "猫网电竞的招牌猫咪霓虹灯。", 10, 0, 2, 9, 3),
    entry("trophy_case", "奖杯柜", "ambience", ["trophy", "floor"], 460, 4, (64, 96),
          "陈列赛事奖杯与纪念品，提升专业形象。", 14, 0, 3, 12, 4),
    entry("team_flag", "战队旗", "ambience", ["flag", "wall"], 180, 2, (64, 56),
          "开黑房专用战队旗帜。", 7, 0, 2, 6, 2),

    entry("counter_premium", "高级柜台", "service", ["counter", "service"], 720, 4, (192, 100),
          "带灯牌、双屏收银和收纳空间的高级前台。", 20, 3, 5, 14, 6),
    entry("shelf_premium", "精品货架", "service", ["shelf", "service"], 560, 3, (128, 128),
          "照明更好、陈列更整齐的饮料零食货架。", 16, 4, 4, 9, 5),
    entry("restroom_premium", "升级卫生间", "service", ["restroom", "service"], 900, 5, (128, 192),
          "干湿分离、通风明亮的升级卫生间。", 24, 18, 10, 16, 4),
]


def validate(catalog: list[dict]) -> None:
    assert len(catalog) == 24
    assert len({item["id"] for item in catalog}) == 24
    assert {item["category"] for item in catalog} == {
        "theme", "function", "comfort", "ambience", "service",
    }
    assert sum(item["category"] == "theme" for item in catalog) == 6
    assert sum(item["scene_size"] is not None for item in catalog) == 18
    assert all(item["price"] >= 0 for item in catalog)
    assert all(item["tags"] for item in catalog)


def main() -> None:
    validate(CATALOG)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(
        json.dumps(CATALOG, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {OUTPUT}: {len(CATALOG)} 项，6 套主题 + 18 项实体装修")


if __name__ == "__main__":
    main()
