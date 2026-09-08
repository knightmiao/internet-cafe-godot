#!/usr/bin/env python3
"""生成固定、可复现的 50 人顾客角色库。"""

from __future__ import annotations

import json
import random
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "godot/data/customers.json"
SEED = 20260907

MALE_NAMES = [
    "林宇航", "陈子轩", "周奕辰", "吴浩然", "赵铭泽", "徐嘉豪",
    "黄俊熙", "何景行", "宋承宇", "郭明远", "罗一鸣", "郑博文",
    "梁致远", "谢安平", "唐文斌", "许建国", "韩志强", "冯国栋",
    "邓世杰", "曹永康", "彭立新", "潘宏伟", "袁正华", "董卫东",
    "叶庆林", "苏长青", "魏振邦", "蒋兴国", "杜德明", "程广义",
]

FEMALE_NAMES = [
    "沈雨桐", "李欣妍", "秦若溪", "方可心", "顾晓彤", "白思琪",
    "邱婉晴", "孟书瑶", "陆佳宁", "夏静怡", "姜慧敏", "石雅琴",
    "熊丽华", "金秀兰", "范美玲", "廖淑芬", "任桂芳", "姚春梅",
    "钟月华", "陶素珍",
]

MALE_AGES = [
    18, 19, 20, 22, 23, 24,
    25, 27, 29, 31, 33, 34,
    35, 37, 39, 41, 43, 44,
    45, 47, 49, 51, 53, 54,
    55, 56, 57, 58, 59, 60,
]
FEMALE_AGES = [
    18, 20, 22, 24,
    26, 28, 31, 34,
    36, 39, 42, 44,
    46, 49, 52, 54,
    55, 57, 59, 60,
]

JOBS_BY_AGE = {
    "young": ["大学生", "电竞青训生", "奶茶店员", "实习设计师", "直播助理", "自由插画师"],
    "adult": ["程序员", "产品经理", "外卖骑手", "平面设计师", "销售顾问", "会计", "网店店主"],
    "middle": ["出租车司机", "中学教师", "社区工作者", "维修技师", "个体商户", "行政主管", "快递站长"],
    "senior": ["保安队长", "仓库管理员", "退休工人", "棋牌室老板", "物业主管", "自由职业者"],
}

OUTFITS_BY_JOB = {
    "大学生": ["校园休闲", "运动街头"], "电竞青训生": ["电竞潮服", "运动机能"],
    "奶茶店员": ["清爽制服", "日系休闲"], "实习设计师": ["文艺叠穿", "简约通勤"],
    "直播助理": ["潮流街头", "宽松休闲"], "自由插画师": ["文艺复古", "森系休闲"],
    "程序员": ["格纹衬衫", "极简休闲"], "产品经理": ["商务休闲", "都市通勤"],
    "外卖骑手": ["骑手工装", "运动防风"], "平面设计师": ["设计感通勤", "黑白极简"],
    "销售顾问": ["轻商务", "精致通勤"], "会计": ["稳重通勤", "针织衫"],
    "网店店主": ["舒适家居", "休闲卫衣"], "出租车司机": ["耐磨夹克", "朴素休闲"],
    "中学教师": ["学院通勤", "素色针织"], "社区工作者": ["红马甲便装", "亲和通勤"],
    "维修技师": ["维修工装", "牛仔耐磨"], "个体商户": ["朴实夹克", "休闲衬衫"],
    "行政主管": ["成熟商务", "稳重通勤"], "快递站长": ["物流工装", "运动夹克"],
    "保安队长": ["保安制服", "深色夹克"], "仓库管理员": ["仓储工装", "耐磨便装"],
    "退休工人": ["旧式夹克", "朴素针织"], "棋牌室老板": ["中式休闲", "宽松衬衫"],
    "物业主管": ["物业制服", "商务夹克"], "自由职业者": ["舒适休闲", "复古便装"],
}

MALE_HAIR = ["短碎发", "寸头", "侧分短发", "自然卷短发", "背头", "平头", "微卷中短发"]
FEMALE_HAIR = ["齐肩直发", "高马尾", "短波波头", "低马尾", "披肩卷发", "丸子头", "齐耳短发"]
HAIR_COLORS = ["自然黑", "深棕", "栗棕", "茶棕"]
DYED_COLORS = ["亚麻棕", "酒红", "雾蓝黑", "暖金棕"]

HABITS = [
    {"type": "竞技游戏", "preferred_period": "晚间", "session_hours": 4.0, "spending_focus": "高配机位"},
    {"type": "休闲游戏", "preferred_period": "午后", "session_hours": 2.5, "spending_focus": "饮料零食"},
    {"type": "追剧观影", "preferred_period": "晚间", "session_hours": 3.0, "spending_focus": "安静座位"},
    {"type": "直播互动", "preferred_period": "夜间", "session_hours": 4.5, "spending_focus": "高速网络"},
    {"type": "社交开黑", "preferred_period": "周末", "session_hours": 3.5, "spending_focus": "连坐机位"},
    {"type": "办公学习", "preferred_period": "白天", "session_hours": 2.0, "spending_focus": "安静与咖啡"},
    {"type": "夜间包时", "preferred_period": "深夜", "session_hours": 7.0, "spending_focus": "包夜套餐"},
]


def age_group(age: int) -> str:
    if age <= 24:
        return "young"
    if age <= 34:
        return "adult"
    if age <= 49:
        return "middle"
    return "senior"


def height_class(height: int, gender: str) -> str:
    low, high = (166, 178) if gender == "男" else (156, 168)
    if height < low:
        return "偏矮"
    if height > high:
        return "高挑"
    return "中等"


def build_person(index: int, name: str, gender: str, age: int, rng: random.Random) -> dict:
    group = age_group(age)
    job = rng.choice(JOBS_BY_AGE[group])
    height = rng.randint(158, 188) if gender == "男" else rng.randint(150, 178)
    hair_type = rng.choice(MALE_HAIR if gender == "男" else FEMALE_HAIR)
    if age >= 55:
        hair_color = rng.choice(["花白", "灰黑", "银灰"])
    elif age <= 34 and index % 5 == 0:
        hair_color = rng.choice(DYED_COLORS)
    else:
        hair_color = rng.choice(HAIR_COLORS)
    habit = dict(HABITS[(index - 1) % len(HABITS)])
    habit["session_hours"] = round(max(1.0, habit["session_hours"] + rng.choice([-0.5, 0, 0.5])), 1)
    return {
        "id": f"customer_{index:02d}",
        "name": name,
        "gender": gender,
        "age": age,
        "occupation": job,
        "outfit_style": rng.choice(OUTFITS_BY_JOB[job]),
        "height_cm": height,
        "height_class": height_class(height, gender),
        "hair_type": hair_type,
        "hair_color": hair_color,
        "internet_habit": habit,
    }


def build_roster() -> list[dict]:
    rng = random.Random(SEED)
    males = [build_person(i + 1, n, "男", a, rng) for i, (n, a) in enumerate(zip(MALE_NAMES, MALE_AGES))]
    females = [
        build_person(i + 31, n, "女", a, rng)
        for i, (n, a) in enumerate(zip(FEMALE_NAMES, FEMALE_AGES))
    ]

    # 每张五人拼版固定 3 男 2 女，方便生图批次同时满足总性别比例。
    roster = []
    for batch in range(10):
        roster.extend(males[batch * 3:batch * 3 + 3])
        roster.extend(females[batch * 2:batch * 2 + 2])
    for index, person in enumerate(roster, 1):
        person["id"] = f"customer_{index:02d}"
        person["sprite"] = f"res://assets/world/npc/customer_{index:02d}_idle.png"
        person["portrait"] = f"res://assets/ui/portraits/portrait_customer_{index:02d}.png"
    return roster


def validate(roster: list[dict]) -> None:
    assert len(roster) == 50
    assert Counter(p["gender"] for p in roster) == {"男": 30, "女": 20}
    assert min(p["age"] for p in roster) == 18
    assert max(p["age"] for p in roster) == 60
    assert len({p["id"] for p in roster}) == 50
    assert len({p["name"] for p in roster}) == 50
    assert all(18 <= p["age"] <= 60 for p in roster)
    assert all(150 <= p["height_cm"] <= 188 for p in roster)
    assert len({p["occupation"] for p in roster}) >= 20
    assert len({p["internet_habit"]["type"] for p in roster}) == len(HABITS)


def main() -> None:
    roster = build_roster()
    validate(roster)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(roster, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    genders = Counter(p["gender"] for p in roster)
    ages = [p["age"] for p in roster]
    print(
        f"wrote {OUTPUT}: {len(roster)} 人，男 {genders['男']} / 女 {genders['女']}，"
        f"年龄 {min(ages)}–{max(ages)}，职业 {len({p['occupation'] for p in roster})} 种"
    )


if __name__ == "__main__":
    main()
