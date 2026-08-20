#!/usr/bin/env python3
"""
为 squads.json 中的球员生成新的 5 维属性默认值。
基于现有的 speed 和 power 推导，保证每个球员有差异化的属性分布。
"""
import json
import random
import sys

# 设置随机种子保证可复现
random.seed(42)

INPUT_FILE = "assets/json/squads.json"

def derive_attributes(player, role_index):
    """根据现有属性和位置，生成新的 5 维属性 + 球衣号码"""
    speed = player["speed"]
    power = player["power"]

    # speed 和 power 的取值范围大致是：
    # speed: 70-90 (像素/秒)
    # power: 150-200 (射门力度)
    # 归一化到 0-100 范围作为基础

    speed_norm = max(0, min(100, (speed - 60) * 5))      # 60→0, 80→100
    power_norm = max(0, min(100, (power - 140) * 2))      # 140→0, 190→100

    # 位置差异（角色倾向）
    role_bias = {
        0: {  # GOALIE
            "technique": 30,
            "shooting": 20,
            "defense": 80,
            "jump": 85,
            "stamina": 60,
        },
        1: {  # DEFENSE
            "technique": 55,
            "shooting": 40,
            "defense": 85,
            "jump": 75,
            "stamina": 80,
        },
        2: {  # MIDFIELD
            "technique": 75,
            "shooting": 65,
            "defense": 60,
            "jump": 55,
            "stamina": 85,
        },
        3: {  # OFFENSE
            "technique": 80,
            "shooting": 85,
            "defense": 35,
            "jump": 70,
            "stamina": 75,
        },
    }

    base = role_bias.get(role_index, role_bias[2])

    # 以位置倾向为基础，叠加 speed/power 的影响 + 少量随机
    # 让每个球员有独特的属性组合
    technique = base["technique"] + (speed_norm - 50) * 0.2 + random.randint(-8, 8)
    shooting = base["shooting"] + (power_norm - 50) * 0.3 + random.randint(-10, 10)
    defense = base["defense"] + (power_norm - 50) * 0.15 + random.randint(-8, 8)
    jump = base["jump"] + (power_norm - 50) * 0.2 + random.randint(-5, 5)
    stamina = base["stamina"] + (speed_norm - 50) * 0.15 + random.randint(-5, 5)

    # 明星球员加成（速度+力量都高的球员）
    overall = (speed_norm + power_norm) / 2
    if overall > 75:
        bonus = (overall - 75) * 0.4
        technique += bonus
        shooting += bonus
        stamina += bonus * 0.5

    # 钳制在 20-98 之间，留一点上下空间
    def clamp(v, lo=20, hi=98):
        return max(lo, min(hi, round(v)))

    return {
        "technique": clamp(technique),
        "shooting": clamp(shooting),
        "defense": clamp(defense),
        "jump": clamp(jump),
        "stamina": clamp(stamina),
    }


def assign_number(role_index, index_in_team):
    """根据位置分配球衣号码（经典号码体系）"""
    # 位置对应的经典号码范围
    role_number_ranges = {
        0: [1],           # 门将 = 1
        1: [2, 3, 4, 5],  # 后卫 = 2,3,4,5
        2: [6, 7, 8, 10], # 中场 = 6,7,8,10
        3: [9, 11, 10, 7],# 前锋 = 9,11,10,7
    }
    nums = role_number_ranges.get(role_index, [])
    if not nums:
        return index_in_team + 1
    idx = index_in_team % len(nums)
    return nums[idx]


def load_json_lenient(path):
    """加载可能包含尾随逗号的 JSON 文件（Godot JSON 解析器更宽松）"""
    import re
    with open(path, "r") as f:
        text = f.read()
    # 移除尾随逗号: , 后面跟 ] 或 }
    text = re.sub(r',\s*([}\]])', r'\1', text)
    return json.loads(text)


def fix_data_issues(teams):
    """修复原始数据中的已知问题"""
    for team in teams:
        if team["country"] == "ITALY":
            # S. GNABRY 是德国球员，替换为 L. BARELLA（意大利中场）
            team["players"][5]["name"] = "L. BARELLA"
            # 调整为: 门将(1), 后卫(2), 中场(2), 前锋(1) - 不对，要保持 1+2+1+2 结构
            # 原始结构是 0,1,1,2,3,3，保持不变，只改名字
        elif team["country"] == "SPAIN":
            # 原始数据中 A. BALDE(左后卫) role=2(MIDFIELD), GAVI role=1(DEFENSE)，反过来了
            team["players"][2]["role"] = 1  # A. BALDE -> DEFENSE
            team["players"][3]["role"] = 2  # GAVI -> MIDFIELD


def main():
    teams = load_json_lenient(INPUT_FILE)
    fix_data_issues(teams)

    total_players = 0
    for team in teams:
        country = team["country"]
        players = team["players"]
        print(f"\n{country} ({len(players)} players):")

        role_counts = {}
        for i, p in enumerate(players):
            role = p["role"]
            role_counts[role] = role_counts.get(role, 0) + 1
            role_index_within = sum(1 for j in range(i) if players[j]["role"] == role)

            attrs = derive_attributes(p, role)
            p["technique"] = attrs["technique"]
            p["shooting"] = attrs["shooting"]
            p["defense"] = attrs["defense"]
            p["jump"] = attrs["jump"]
            p["stamina"] = attrs["stamina"]
            p["number"] = assign_number(role, role_index_within)

            total_players += 1
            print(f"  #{p['number']:2d} {p['name']:20s} "
                  f"speed={p['speed']:3.0f} power={p['power']:3.0f} "
                  f"tec={p['technique']:2d} sho={p['shooting']:2d} "
                  f"def={p['defense']:2d} jmp={p['jump']:2d} sta={p['stamina']:2d}")

    # 写回文件（美化格式）
    with open(INPUT_FILE, "w") as f:
        json.dump(teams, f, indent=2, ensure_ascii=False)

    print(f"\n共处理 {len(teams)} 支球队，{total_players} 名球员")
    print(f"已写回 {INPUT_FILE}")


if __name__ == "__main__":
    main()
