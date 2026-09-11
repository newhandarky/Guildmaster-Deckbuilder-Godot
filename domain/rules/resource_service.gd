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
		combat += evaluate_party_member_combat(
			state, definitions, card_instance_id, party_index, party
		)
	for card_instance_id: StringName in hand.card_instance_ids:
		purchase_power += _printed_value(state, definitions, card_instance_id, &"purchase_power")
		var hand_definition := _definition_for_card(state, definitions, card_instance_id)
		if hand_definition == null:
			continue
		for source_id: StringName in party.card_instance_ids:
			var source_definition := _definition_for_card(state, definitions, source_id)
			if source_definition == null:
				continue
			for effect: Dictionary in source_definition.effects:
				if StringName(effect.get("op", "")) == &"hand_purchase_power_modifier" \
						and state.phase == &"purchase" \
						and _entered_party_this_turn(state, player_id, source_id) \
						and hand_definition.card_type \
						in _string_names(effect.get("card_types", [])):
					purchase_power += int(effect.get("amount", 0))
	purchase_power = maxi(0, purchase_power - player.spent_purchase_power)
	return {
		"ok": true,
		"combat": maxi(0, combat),
		"purchase_power": purchase_power,
		"spent_purchase_power": player.spent_purchase_power,
	}


static func effective_purchase_cost(
	state: GameStateData,
	player_id: StringName,
	card_instance_id: StringName,
	definitions: Dictionary
) -> int:
	var definition := _definition_for_card(state, definitions, card_instance_id)
	if definition == null or definition.cost == null:
		return -1
	var cost := int(definition.cost)
	var player := state.players.get(player_id) as PlayerStateData
	var party := state.zones.get(player.zone_ids.get(&"party", &"")) as ZoneData if player != null else null
	if party == null:
		return cost
	var source_zone_id := ZoneService.find_card_zone(state, card_instance_id)
	for source_id: StringName in party.card_instance_ids:
		var source_definition := _definition_for_card(state, definitions, source_id)
		if source_definition == null:
			continue
		for effect: Dictionary in source_definition.effects:
			if StringName(effect.get("op", "")) == &"purchase_cost_modifier" \
					and StringName(effect.get("source_zone_id", "")) == source_zone_id \
					and StringName(effect.get("card_type", "")) == definition.card_type:
				cost += int(effect.get("amount", 0))
	return maxi(0, cost)


static func evaluate_party_member_combat(
	state: GameStateData,
	definitions: Dictionary,
	card_instance_id: StringName,
	party_index: int,
	party: ZoneData = null,
	include_equipment: bool = true,
	target_card_type: StringName = &""
) -> int:
	if party == null:
		var card := state.cards.get(card_instance_id) as Dictionary
		if card == null:
			return 0
		var owner := state.players.get(StringName(card.get("owner_id", ""))) as PlayerStateData
		if owner == null:
			return 0
		party = state.zones.get(owner.zone_ids.get(&"party", &"")) as ZoneData
	if party == null or party_index < 0 or party_index >= party.card_instance_ids.size() \
			or party.card_instance_ids[party_index] != card_instance_id:
		return 0
	var combat := _printed_value(state, definitions, card_instance_id, &"combat")
	combat += _continuous_combat_bonus(
		state, definitions, card_instance_id, party_index, party, target_card_type
	)
	combat += int(((state.players[StringName((state.cards[card_instance_id] as Dictionary).get("owner_id", ""))] as PlayerStateData).turn_bonuses.get("card_combat_modifiers", {}) as Dictionary).get(str(card_instance_id), 0))
	combat += _party_aura_bonus(state, definitions, card_instance_id, party_index, party)
	if include_equipment:
		var card := state.cards.get(card_instance_id) as Dictionary
		var card_state := card.get("state", {}) as Dictionary if card != null else {}
		for raw_equipment_id: Variant in card_state.get("equipment_ids", []) as Array:
			var equipment_id := StringName(str(raw_equipment_id))
			var equipment_definition := _definition_for_card(state, definitions, equipment_id)
			if equipment_definition != null:
				if equipment_definition.card_type == &"equipment":
					combat += _printed_value(state, definitions, equipment_id, &"combat")
					combat += _continuous_combat_bonus(
						state, definitions, equipment_id, -1, party, target_card_type
					)
				for effect: Dictionary in equipment_definition.effects:
					if StringName(effect.get("op", "")) == &"self_as_equipment":
						combat += int(effect.get("amount", 0))
		var source_definition := _definition_for_card(state, definitions, card_instance_id)
		for effect: Dictionary in source_definition.effects if source_definition != null else []:
			if StringName(effect.get("op", "")) != &"attached_value_combat":
				continue
			for raw_equipment_id: Variant in card_state.get("equipment_ids", []) as Array:
				var attached_definition := _definition_for_card(state, definitions, StringName(str(raw_equipment_id)))
				if attached_definition != null and attached_definition.card_type in _string_names(effect.get("card_types", [])):
					var attached_value: Variant = attached_definition.get(str(effect.get("field", "combat")))
					combat += 0 if attached_value == null else int(attached_value)
	return maxi(0, combat)


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
	party: ZoneData,
	target_card_type: StringName = &""
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
			&"minus_other_party_count":
				applies = true
				bonus += int(effect.get("amount", -1)) * maxi(0, party.card_instance_ids.size() - 1)
			&"target_card_type":
				applies = target_card_type == StringName(effect.get("target_card_type", ""))
		if applies:
			if condition != &"minus_other_party_count":
				bonus += int(effect.get("amount", 0))
	return bonus


static func _party_aura_bonus(
	state: GameStateData,
	definitions: Dictionary,
	target_card_id: StringName,
	target_index: int,
	party: ZoneData
) -> int:
	var bonus := 0
	for source_index in party.card_instance_ids.size():
		var source_id := party.card_instance_ids[source_index]
		var source_definition := _definition_for_card(state, definitions, source_id)
		if source_definition == null:
			continue
		for effect: Dictionary in source_definition.effects:
			if StringName(effect.get("op", "")) != &"party_combat_aura" \
					or (bool(effect.get("exclude_source", false)) and source_id == target_card_id):
				continue
			var selector := StringName(effect.get("selector", "all"))
			if selector == &"first" and target_index != 0:
				continue
			if selector == &"adjacent" and absi(target_index - source_index) != 1:
				continue
			bonus += int(effect.get("amount", 0))
	return bonus


static func _definition_for_card(
	state: GameStateData, definitions: Dictionary, card_id: StringName
) -> CardDefinition:
	var card := state.cards.get(card_id) as Dictionary
	return definitions.get(StringName(card.get("definition_id", ""))) as CardDefinition if card != null else null


static func _string_names(values: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Variant in values if values is Array else []:
		result.append(StringName(str(value)))
	return result


static func _entered_party_this_turn(
	state: GameStateData, player_id: StringName, card_id: StringName
) -> bool:
	var card := state.cards.get(card_id) as Dictionary
	return card != null and str((card.get("state", {}) as Dictionary).get("entered_turn", "")) \
			== "%s:%d" % [player_id, state.round_number]
