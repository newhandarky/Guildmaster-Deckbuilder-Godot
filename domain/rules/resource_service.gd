class_name ResourceService
extends RefCounted


static func evaluate_player(
	state: GameStateData,
	player_id: StringName,
	definitions: Dictionary
) -> Dictionary:
	var player := state.players.get(player_id) as PlayerStateData
	if player == null:
		return {"ok": false, "error": "missing_player"}

	var combat := int(player.turn_resources.get("combat", 0))
	var purchase_power := int(player.turn_resources.get("purchase_power", 0))
	var party := state.zones.get(player.zone_ids.get(&"party", &"")) as ZoneData
	var hand := state.zones.get(player.zone_ids.get(&"hand", &"")) as ZoneData
	var equipment := state.zones.get(player.zone_ids.get(&"equipment", &"")) as ZoneData
	if party == null or hand == null or equipment == null:
		return {"ok": false, "error": "missing_player_card_zone"}

	for party_index in party.card_instance_ids.size():
		var card_instance_id := party.card_instance_ids[party_index]
		combat += _printed_value(state, definitions, card_instance_id, &"combat")
		combat += _continuous_combat_bonus(
			state,
			definitions,
			card_instance_id,
			party_index,
			party
		)
	for card_instance_id: StringName in equipment.card_instance_ids:
		var card := state.cards.get(card_instance_id) as Dictionary
		var card_state := card.get("state", {}) as Dictionary if card != null else {}
		if not StringName(card_state.get("equipped_to", "")).is_empty():
			combat += _printed_value(state, definitions, card_instance_id, &"combat")
			combat += _continuous_combat_bonus(state, definitions, card_instance_id, -1, party)
	for card_instance_id: StringName in hand.card_instance_ids:
		purchase_power += _printed_value(state, definitions, card_instance_id, &"purchase_power")
	purchase_power = maxi(0, purchase_power - player.spent_purchase_power)
	return {
		"ok": true,
		"combat": maxi(0, combat),
		"purchase_power": purchase_power,
		"spent_purchase_power": player.spent_purchase_power,
	}


static func _printed_value(
	state: GameStateData,
	definitions: Dictionary,
	card_instance_id: StringName,
	field_name: StringName
) -> int:
	var card := state.cards.get(card_instance_id) as Dictionary
	if card == null:
		return 0
	var definition := definitions.get(StringName(card.get("definition_id", ""))) as CardDefinition
	if definition == null:
		return 0
	var value: Variant = definition.get(str(field_name))
	return 0 if value == null else int(value)


static func _continuous_combat_bonus(
	state: GameStateData,
	definitions: Dictionary,
	card_instance_id: StringName,
	party_index: int,
	party: ZoneData
) -> int:
	var card := state.cards.get(card_instance_id) as Dictionary
	if card == null:
		return 0
	var definition := definitions.get(StringName(card.get("definition_id", ""))) as CardDefinition
	if definition == null:
		return 0
	var bonus := 0
	for effect: Dictionary in definition.effects:
		if StringName(effect.get("op", "")) != &"conditional_combat" \
				or StringName(effect.get("timing", "")) != &"continuous":
			continue
		var condition := StringName(effect.get("condition", ""))
		var applies := false
		match condition:
			&"has_equipment":
				var card_state := card.get("state", {}) as Dictionary
				applies = not (card_state.get("equipment_ids", []) as Array).is_empty()
			&"party_index_0":
				applies = party_index == 0
			&"party_index_3_or_4":
				applies = party_index in [3, 4]
			&"equipped_target_tag":
				var equipment_state := card.get("state", {}) as Dictionary
				var target_id := StringName(equipment_state.get("equipped_to", ""))
				if target_id in party.card_instance_ids:
					var target_card := state.cards.get(target_id) as Dictionary
					var target_definition := definitions.get(
						StringName(target_card.get("definition_id", ""))
					) as CardDefinition
					applies = target_definition != null and StringName(effect.get("tag", "")) in target_definition.tags
		if applies:
			bonus += int(effect.get("amount", 0))
	return bonus
