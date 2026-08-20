#!/usr/bin/env python3
"""
为 squads.json 中的球员生成属性默认值，并扩展阵容到 11 人（4-3-3 阵型）。
基于现有的 speed 和 power 推导，保证每个球员有差异化的属性分布。
"""
import json
import random
import sys

# 设置随机种子保证可复现
random.seed(42)

INPUT_FILE = "assets/json/squads.json"

# 每个国家的球员姓池（用于生成新球员名字）
NAME_POOLS = {
    "FRANCE": [
        "K. MBAPPE", "A. GRIEZMANN", "N. KANTE", "R. VARANE",
        "T. HERNANDEZ", "B. PAVARD", "A. RABIOT", "O. DEMBELE",
        "M. SALIBA", "W. SALIBA", "Y. FOFANA", "T. UPAMECANO",
        "K. KONATE", "I. TOLISSO", "C. NKUNKU", "M. THURAM",
    ],
    "ARGENTINA": [
        "L. MESSI", "S. AGUERO", "A. DI MARIA", "N. OTAMENDI",
        "C. RODRIGUEZ", "L. PAREDES", "N. TAGLIAFICO", "G. MONTIEL",
        "J. ALVAREZ", "P. DE PAUL", "L. MARTINEZ", "R. DE PAUL",
        "F. ARMANI", "G. LO CELSO", "E. FERNANDEZ", "C. ROMERO",
    ],
    "BRAZIL": [
        "NEYMAR", "VINICIUS JR", "CASIMIRO", "THIAGO SILVA",
        "MARQUINHOS", "ALISSON", "EDERSON", "G. JESUS",
        "R. LEWANDOWSKI", "FABINHO", "BRUNO G.", "PAQUETA",
        "RAPHINHA", "ANTONY", "MILITAO", "DANILO",
    ],
    "ENGLAND": [
        "H. KANE", "RAHEEM S.", "M. RASHFORD", "J. GREALISH",
        "B. CHILWELL", "K. TRIPPIER", "D. RICE", "J. SANCHO",
        "P. FODEN", "T. ALEXANDER-A", "E. WHITE", "C. POPE",
        "J. HENDERSON", "M. MOUNT", "B. SAKA", "J. STONES",
    ],
    "GERMANY": [
        "T. MULLER", "M. REUS", "I. GUNDOGAN", "J. KIMMICH",
        "T. KROOS", "M. HUMMELS", "N. SULE", "L. GNABRY",
        "K. HAVERTZ", "L. SANE", "J. BRANDT", "T. WERNER",
        "M. GINTER", "R. GOSENS", "K. TRAAP", "A. RUDIGER",
    ],
    "ITALY": [
        "C. IMMOBILE", "L. INSIGNE", "JORGINHO", "M. VERRATTI",
        "L. BARELLA", "G. CHIELLINI", "L. BONUCCI", "G. DONNARUMMA",
        "F. TORRES", "D. BERARDI", "N. BARELLA", "F. CHIESA",
        "B. CRISTANTE", "G. MANCINI", "L. SPINAZZOLA", "G. DI LORENZO",
    ],
    "SPAIN": [
        "A. MORATA", "F. TORRES", "S. BUSQUETS", "I. GAVI",
        "PEDRI", "A. BALDE", "D. CARVAJAL", "R. LAPORTE",
        "M. ASENSIO", "D. OLMO", "C. SOLER", "M. LLORENTE",
        "E. LAMINE YAMAL", "J. CANCELO", "A. GRIMALDO", "J. ALBIOL",
    ],
    "USA": [
        "C. PULISIC", "G. REYNA", "W. MCKENNIE", "T. ADAMS",
        "S. DEST", "A. ROBINSON", "R. BALOGUN", "F. FERREIRA",
        "T. WEAH", "G. OCHOA", "M. TURNER", "Z. STEFFEN",
        "J. MUSAH", "A. LENHARDT", "K. ACOSTA", "C. ROBINSON",
    ],
    "CANADA": [
        "A. DAVIES", "J. DAVID", "T. BUCHANAN", "J. LARYEA",
        "K. MILLER", "S. VITORIA", "M. JONSTON", "A. HUTCHINSON",
        "L. MILLER", "R. EDWARDS", "I. KONE", "M. BRYMO",
        "C. CIMPODEA", "D. WATERS", "B. OSMAN", "F. CORMIER",
    ],
}

# 球衣颜色（皮肤颜色枚举，与 Player.SkinColor 对应）
SKIN_COLORS = [0, 1, 2, 3]  # 0=LIGHT, 1=MEDIUM, 2=DARK, 3=VERY_DARK（假设）


def derive_attributes(player, role_index):
    """根据现有属性和位置，生成新的 5 维属性"""
    speed = player["speed"]
    power = player["power"]

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

    technique = base["technique"] + (speed_norm - 50) * 0.2 + random.randint(-8, 8)
    shooting = base["shooting"] + (power_norm - 50) * 0.3 + random.randint(-10, 10)
    defense = base["defense"] + (power_norm - 50) * 0.15 + random.randint(-8, 8)
    jump = base["jump"] + (power_norm - 50) * 0.2 + random.randint(-5, 5)
    stamina = base["stamina"] + (speed_norm - 50) * 0.15 + random.randint(-5, 5)

    overall = (speed_norm + power_norm) / 2
    if overall > 75:
        bonus = (overall - 75) * 0.4
        technique += bonus
        shooting += bonus
        stamina += bonus * 0.5

    def clamp(v, lo=20, hi=98):
        return max(lo, min(hi, round(v)))

    return {
        "technique": clamp(technique),
        "shooting": clamp(shooting),
        "defense": clamp(defense),
        "jump": clamp(jump),
        "stamina": clamp(stamina),
    }


def generate_new_player(role, country, used_names):
    """生成一个新球员（填补阵容到 11 人）"""
    # 从名字池中选一个未使用的名字
    pool = NAME_POOLS.get(country, NAME_POOLS["FRANCE"])
    available = [n for n in pool if n not in used_names]
    if available:
        name = random.choice(available)
    else:
        name = f"PLAYER_{random.randint(100, 999)}"

    # 根据位置生成基础 speed/power
    role_speed_ranges = {
        0: (65, 72),    # 门将速度较慢
        1: (72, 82),    # 后卫中等偏快
        2: (75, 85),    # 中场速度较快
        3: (78, 90),    # 前锋最快
    }
    role_power_ranges = {
        0: (150, 170),  # 门将力量中等
        1: (160, 190),  # 后卫力量大
        2: (155, 180),  # 中场均衡
        3: (165, 195),  # 前锋射门力量大
    }
    speed_range = role_speed_ranges.get(role, (75, 85))
    power_range = role_power_ranges.get(role, (160, 185))

    speed = random.randint(*speed_range)
    power = random.randint(*power_range)

    player = {
        "name": name,
        "skin": random.choice(SKIN_COLORS),
        "role": role,
        "speed": speed,
        "power": power,
    }

    # 生成 5 维属性
    attrs = derive_attributes(player, role)
    player.update(attrs)

    return player


def assign_numbers(players):
    """为整队分配球衣号码（经典号码体系，11 人制）"""
    # 经典 11 人号码分配：
    # GK: 1
    # DEF (4): 2, 3, 4, 5 (RB, LB, CB, CB)
    # MID (3): 6, 8, 10  (CDM, CM, CAM)
    # FWD (3): 7, 9, 11  (RW, ST, LW)
    number_map = {
        0: [1],           # GK
        1: [2, 5, 4, 3],  # DEF: RB, RCB, LCB, LB
        2: [6, 8, 10],    # MID: CDM, CM, CAM
        3: [7, 9, 11],    # FWD: RW, ST, LW
    }

    role_counters = {}
    for p in players:
        role = p["role"]
        role_counters[role] = role_counters.get(role, 0)
        nums = number_map.get(role, [])
        idx = role_counters[role] % len(nums) if nums else 0
        p["number"] = nums[idx] if nums else role_counters[role] + 12
        role_counters[role] += 1


def load_json_lenient(path):
    """加载可能包含尾随逗号的 JSON 文件（Godot JSON 解析器更宽松）"""
    import re
    with open(path, "r") as f:
        text = f.read()
    text = re.sub(r',\s*([}\]])', r'\1', text)
    return json.loads(text)


def fix_data_issues(teams):
    """修复原始数据中的已知问题"""
    for team in teams:
        if team["country"] == "ITALY":
            # S. GNABRY 是德国球员，替换为 L. BARELLA（意大利中场）
            team["players"][5]["name"] = "L. BARELLA"
        elif team["country"] == "SPAIN":
            # 原始数据中 A. BALDE(左后卫) role=2(MIDFIELD), GAVI role=1(DEFENSE)，反过来了
            team["players"][2]["role"] = 1  # A. BALDE -> DEFENSE
            team["players"][3]["role"] = 2  # GAVI -> MIDFIELD


def expand_squad_to_11(team):
    """将球队从 6 人扩展到 11 人（4-3-3 阵型）"""
    players = team["players"]
    country = team["country"]

    if len(players) >= 11:
        return

    used_names = {p["name"] for p in players}

    # 当前角色统计
    role_counts = {0: 0, 1: 0, 2: 0, 3: 0}
    for p in players:
        r = p["role"]
        if r in role_counts:
            role_counts[r] += 1

    # 目标 4-3-3: 1 GK, 4 DEF, 3 MID, 3 FWD
    targets = {0: 1, 1: 4, 2: 3, 3: 3}

    # 按角色顺序添加：先加后卫，再加中场，再加前锋
    # 保持顺序： GK, DEF*4, MID*3, FWD*3
    new_players = []

    # 需要添加的角色列表（按位置顺序）
    for role in [1, 2, 3]:  # 不需要加门将
        needed = targets[role] - role_counts[role]
        for _ in range(needed):
            np = generate_new_player(role, country, used_names)
            used_names.add(np["name"])
            new_players.append(np)
            role_counts[role] += 1

    # 插入到正确的位置：保持 GK + DEF + MID + FWD 的顺序
    # 现有球员顺序可能不完全按角色排，重新组织
    all_players = list(players) + new_players

    # 按角色分组排序：GK(0) → DEF(1) → MID(2) → FWD(3)
    all_players.sort(key=lambda p: (p["role"], p["name"]))

    team["players"] = all_players


def main():
    teams = load_json_lenient(INPUT_FILE)
    fix_data_issues(teams)

    total_players = 0
    for team in teams:
        country = team["country"]

        # 扩展到 11 人
        expand_squad_to_11(team)

        players = team["players"]
        print(f"\n{country} ({len(players)} players):")

        # 为已有的 6 人也补全属性（兼容旧数据）
        for p in players:
            if "technique" not in p:
                attrs = derive_attributes(p, p["role"])
                p.update(attrs)

        # 分配球衣号码
        assign_numbers(players)

        role_counts = {}
        for i, p in enumerate(players):
            role = p["role"]
            role_counts[role] = role_counts.get(role, 0) + 1

            total_players += 1
            role_names = ["GK", "DF", "MF", "FW"]
            print(f"  #{p.get('number', '?'):2d} {p['name']:20s} "
                  f"{role_names[role]:3s} "
                  f"speed={p['speed']:3.0f} power={p['power']:3.0f} "
                  f"tec={p.get('technique', '?'):>3} sho={p.get('shooting', '?'):>3} "
                  f"def={p.get('defense', '?'):>3} jmp={p.get('jump', '?'):>3} "
                  f"sta={p.get('stamina', '?'):>3}")

    # 写回文件（美化格式）
    with open(INPUT_FILE, "w") as f:
        json.dump(teams, f, indent=2, ensure_ascii=False)

    print(f"\n共处理 {len(teams)} 支球队，{total_players} 名球员")
    print(f"每队 11 人（4-3-3 阵型）")
    print(f"已写回 {INPUT_FILE}")


if __name__ == "__main__":
    main()
