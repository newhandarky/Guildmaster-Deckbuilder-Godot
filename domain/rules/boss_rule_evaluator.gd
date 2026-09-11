class_name BossRuleEvaluator
extends RefCounted

const BossServiceType = preload("res://domain/state/boss_service.gd")

const PROFESSION_TAGS: Array[StringName] = [&"melee", &"ranged", &"mage", &"tank", &"support"]
const SUPPORTED_RULES: Array[StringName] = [
	&"participant_limit",
	&"suppress_equipment",
	&"modify_requirement_by_professions",
	&"modify_requirement_by_zone_count",
	&"replace_combat_departure",
	&"post_departure_cost",
	&"attach_on_reveal",
]


static func validate_rules(definition: CardDefinition) -> PackedStringArray:
	var errors := PackedStringArray()
	if definition.card_type != &"boss":
		if not definition.special_rules.is_empty():
			errors.append("Only boss definitions may declare special_rules: %s" % definition.definition_id)
		return errors
	if definition.rules_text.is_empty() or definition.reward_text.is_empty():
		errors.append("Boss requires public rules and reward text: %s" % definition.definition_id)
	for index in definition.special_rules.size():
		var rule := definition.special_rules[index] as Dictionary
		var operation := StringName(rule.get("op", ""))
		if operation not in SUPPORTED_RULES:
			errors.append("Unsupported boss rule %s at %s[%d]" % [operation, definition.definition_id, index])
			continue
		match operation:
			&"replace_combat_departure":
				if StringName(rule.get("destination_zone_id", "")).is_empty() \
						or StringName(rule.get("starter_destination_zone_key", "")).is_empty() \
						or StringName(rule.get("equipment_destination_zone_key", "")).is_empty():
					errors.append("Boss departure replacement requires explicit destinations: %s" % definition.definition_id)
			&"post_departure_cost":
				if StringName(rule.get("card_type", "")).is_empty() \
						or StringName(rule.get("source_zone_key", "")).is_empty() \
						or StringName(rule.get("destination_zone_key", "")).is_empty() \
						or str(rule.get("prompt", "")).is_empty():
					errors.append("Boss post-departure cost requires type, zones, and prompt: %s" % definition.definition_id)
	return errors


static func evaluate(
	state: GameStateData,
	actor_id: StringName,
	definition: CardDefinition,
	definitions: Dictionary
) -> Dictionary:
	var result := {
		"requirement": int(definition.combat),
		"participant_limit": -1,
		"equipment_suppressed": false,
		"modifiers": [],
	}
	for rule: Dictionary in definition.special_rules:
		match StringName(rule.get("op", "")):
			&"participant_limit":
				result["participant_limit"] = int(rule.get("max", -1))
			&"suppress_equipment":
				result["equipment_suppressed"] = true
			&"modify_requirement_by_professions":
				var subject_id := _subject_player_id(state, actor_id, StringName(rule.get("subject", "self")))
				var count := _distinct_profession_count(state, subject_id, definitions)
				var delta := count * int(rule.get("amount_each", 0))
				result["requirement"] = maxi(
					int(rule.get("minimum", 0)), int(result["requirement"]) + delta
				)
				(result["modifiers"] as Array).append({
					"op": "modify_requirement_by_professions",
					"subject_player_id": str(subject_id),
					"profession_count": count,
					"delta": delta,
				})
			&"modify_requirement_by_zone_count":
				var zone := state.zones.get(StringName(rule.get("zone_id", ""))) as ZoneData
				var count := 0
				if zone != null:
					for card_id: StringName in zone.card_instance_ids:
						var card := state.cards.get(card_id) as Dictionary
						var card_definition := definitions.get(
							StringName(card.get("definition_id", "")) if card != null else &""
						) as CardDefinition
						if card_definition != null and card_definition.card_type == StringName(rule.get("card_type", "")):
							count += 1
				var delta := count * int(rule.get("amount_each", 0))
				result["requirement"] = maxi(0, int(result["requirement"]) + delta)
				(result["modifiers"] as Array).append({
					"op": "modify_requirement_by_zone_count",
					"zone_id": str(rule.get("zone_id", "")),
					"count": count,
					"delta": delta,
				})
			&"attach_on_reveal":
				if not bool(rule.get("add_attached_combat", false)):
					continue
				var attached_total := 0
				var boss_card_id := _active_boss_instance_id(state, definition.definition_id)
				var boss_card := state.cards.get(boss_card_id) as Dictionary
				if boss_card != null:
					for raw_attachment_id: Variant in (boss_card.get("state", {}) as Dictionary).get("attachment_ids", []):
						var attachment_card := state.cards.get(StringName(str(raw_attachment_id))) as Dictionary
						var attachment_definition := definitions.get(
							StringName(attachment_card.get("definition_id", "")) if attachment_card != null else &""
						) as CardDefinition
						if attachment_definition != null and attachment_definition.combat != null:
							attached_total += int(attachment_definition.combat)
				result["requirement"] = int(result["requirement"]) + attached_total
				(result["modifiers"] as Array).append({
					"op": "attached_combat", "attached_combat": attached_total,
					"delta": attached_total,
				})
	return result


static func _active_boss_instance_id(
	state: GameStateData, definition_id: StringName
) -> StringName:
	var active := state.zones.get(BossServiceType.BOSS_ACTIVE_ID) as ZoneData
	if active == null:
		return &""
	for card_id: StringName in active.card_instance_ids:
		var card := state.cards.get(card_id) as Dictionary
		if card != null and StringName(card.get("definition_id", "")) == definition_id:
			return card_id
	return &""


static func _subject_player_id(
	state: GameStateData, actor_id: StringName, subject: StringName
) -> StringName:
	if subject != &"left_player":
		return actor_id
	var index := state.turn_order.find(actor_id)
	return state.turn_order[(index + 1) % state.turn_order.size()]


static func _distinct_profession_count(
	state: GameStateData, player_id: StringName, definitions: Dictionary
) -> int:
	var player := state.players.get(player_id) as PlayerStateData
	if player == null:
		return 0
	var party := state.zones.get(player.zone_ids.get(&"party", &"")) as ZoneData
	if party == null:
		return 0
	var found: Dictionary = {}
	for card_id: StringName in party.card_instance_ids:
		var card := state.cards.get(card_id) as Dictionary
		var definition := definitions.get(
			StringName(card.get("definition_id", "")) if card != null else &""
		) as CardDefinition
		if definition == null:
			continue
		for tag: StringName in PROFESSION_TAGS:
			if tag in definition.tags:
				found[tag] = true
	return found.size()
