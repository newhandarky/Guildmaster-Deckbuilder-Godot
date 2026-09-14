"""Rebuild the official bond definitions from the local, non-Git card transcription.

The output is committed, so game builds do not depend on the private docs directory.
"""

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/card-data/卡片02-羈絆.md"
OUTPUT = ROOT / "content/packs/official_bonds.json"
CATALOG = ROOT / "content/packs/OFFICIAL_BONDS.md"


def rule(timing, op, **kwargs):
    return {"timing": timing, "op": op, **kwargs}


RULES = [
    rule("combat_start", "party_exact_all_tags", count=3, tags=["support", "mage"]),
    rule("after_defeat", "combat_participants_exact", count=1, target_type="monster"),
    rule("combat_start", "party_edge_tags", edge="back", count=2, tag="mage"),
    rule("after_defeat", "party_exact", count=1),
    rule("turn_fact", "fact_min", key="bought_equipment", count=2),
    rule("turn_fact", "facts_all_min", keys=["recruited_adventurer", "bought_resource"], count=1),
    rule("combat_start", "party_edge_tags", edge="back", count=2, tag="ranged"),
    rule("turn_fact", "fact_min", key="nonstarter_party_entries", count=3),
    rule("combat_start", "party_tag_count", count=3, tags=["tank", "melee"]),
    rule("combat_start", "party_edge_tags", edge="front", count=2, tag="melee"),
    rule("after_defeat", "party_tag_count", count=2, tags=["support"]),
    rule("after_defeat", "party_tag_count", count=2, tags=["tank"]),
    rule("turn_fact", "action_fact_min", key="items_used", count=3),
    rule("combat_start", "party_profession_set", tags=["support", "mage", "tank", "melee", "ranged"], nonstarter_min=3),
    rule("after_defeat", "party_tag_count", count=2, tags=["ranged"]),
    rule("turn_fact", "fact_min", key="recruited_adventurer", count=2),
    rule("turn_fact", "fact_min", key="extra_cards_drawn", count=3),
    rule("combat_departure", "combat_departure_professions", count=3),
    rule("after_defeat", "party_tag_count", count=2, tags=["mage"]),
    rule("after_defeat", "party_tag_count", count=2, tags=["melee"]),
    rule("party_state", "party_same_profession_min", count=3),
    rule("combat_start", "party_edge_tags", edge="front", count=2, tag="tank"),
    rule("turn_fact", "fact_min", key="combat_equipment_discarded", count=3),
    rule("after_defeat", "fact_min", key="defeated_monster_count", count=1),
    rule("turn_fact", "fact_min", key="monster_cards_used_for_purchase", count=3),
    rule("after_defeat", "fact_min", key="defeated_monster_count", count=2),
    rule("turn_fact", "spent_purchase_min", count=7),
    rule("after_defeat", "party_all_same_profession_min", count=2),
    rule("combat_start", "party_edge_tags", edge="back", count=2, tag="support"),
    rule("party_state", "party_nonstarter_professions_min", count=3),
]


def main():
    definitions = []
    for line in SOURCE.read_text(encoding="utf-8").splitlines():
        match = re.match(
            r"^\| R\dC\d \| `base:bond/bond-(\d\d)` \| ([^|]+) \| (\d+) \| ([^|]+) \|",
            line,
        )
        if not match:
            continue
        number, name, honor, text = match.groups()
        index = int(number) - 1
        definitions.append({
            "definition_id": f"base:bond/bond-{number}",
            "display_name": name.strip(),
            "card_type": "bond",
            "copies": 1,
            "honor": int(honor),
            "tags": ["bond"],
            "rules_text": text.strip(),
            "completion_rule": RULES[index],
            "presentation_id": f"base:presentation/bond-{number}",
        })
    if len(definitions) != 30 or len(RULES) != 30:
        raise ValueError("Expected exactly 30 official bonds")
    OUTPUT.write_text(json.dumps({"definitions": definitions}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines = [
        "# 官方羈絆卡池對照",
        "",
        "依本機 `docs/card-data/卡片02-羈絆.md` 建立；30 種各 1 張，無自定義卡。",
        "",
        "| 編號 | 名稱 | 榮譽 | 正式條件 | 共用 predicate |",
        "|---:|---|---:|---|---|",
    ]
    for number, definition in enumerate(definitions, 1):
        lines.append(
            f"| {number:02d} | {definition['display_name']} | {definition['honor']} "
            f"| {definition['rules_text']} | `{definition['completion_rule']['op']}` |"
        )
    CATALOG.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
