class_name EffectResolver
extends RefCounted

const SUPPORTED_OPERATIONS: Array[StringName] = [
	&"grant_purchase_power",
	&"grant_combat",
	&"draw",
	&"conditional_combat",
	&"choose_remove_card",
	&"choose_gain_card",
]


static func validate_effects(effects: Array[Dictionary], definition_id: StringName = &"") -> PackedStringArray:
	var errors := PackedStringArray()
	for index in effects.size():
		var effect := effects[index]
		var operation := StringName(effect.get("op", ""))
		if not operation in SUPPORTED_OPERATIONS:
			errors.append("Unsupported effect op %s at %s[%d]" % [operation, definition_id, index])
		if int(effect.get("amount", 0)) < 0:
			errors.append("Effect amount must not be negative at %s[%d]" % [definition_id, index])
		if operation in [&"choose_remove_card", &"choose_gain_card"] \
				and index != effects.size() - 1:
			errors.append("Pending choice effect must be last at %s[%d]" % [definition_id, index])
		if operation == &"choose_remove_card" and int(effect.get("amount", 0)) != 1:
			errors.append("Card removal choice amount must be 1 at %s[%d]" % [definition_id, index])
		if operation == &"choose_remove_card" \
				and StringName(effect.get("source_zone_key", "")) \
				not in [&"hand", &"discard_pile"]:
			errors.append("Unsupported removal source at %s[%d]" % [definition_id, index])
		if operation == &"choose_gain_card" and int(effect.get("amount", 0)) != 1:
			errors.append("Card gain choice amount must be 1 at %s[%d]" % [definition_id, index])
		if operation == &"choose_gain_card" \
				and StringName(effect.get("source_zone_id", "")) != SupplyService.RECRUIT_ROW_ID:
			errors.append("Unsupported gain source at %s[%d]" % [definition_id, index])
		if operation == &"choose_gain_card" and int(effect.get("max_cost", -1)) < 0:
			errors.append("Card gain choice requires a non-negative max_cost at %s[%d]" % [definition_id, index])
		if operation == &"choose_gain_card" \
				and StringName(effect.get("required_tag", "")) != &"adventurer":
			errors.append("Recruit gain choice must require adventurer cards at %s[%d]" % [definition_id, index])
	return errors


static func resolve(
	state: GameStateData,
	actor_id: StringName,
	effects: Array[Dictionary],
	events: Array[Dictionary],
	definitions: Dictionary = {}
) -> String:
	var player := state.players.get(actor_id) as PlayerStateData
	if player == null:
		return "missing_player"
	var validation_errors := validate_effects(effects)
	if not validation_errors.is_empty():
		return "invalid_effect: %s" % "; ".join(validation_errors)

	# Effects resolve FIFO in content order so replay and snapshot results stay deterministic.
	for index in effects.size():
		var effect := effects[index]
		var operation := StringName(effect.get("op", ""))
		var amount := int(effect.get("amount", 0))
		var resource_key: StringName
		match operation:
			&"grant_purchase_power":
				resource_key = &"purchase_power"
			&"grant_combat":
				resource_key = &"combat"
			&"draw":
				var draw_result := DeckService.draw_cards(state, actor_id, amount, events)
				if not bool(draw_result.get("ok", false)):
					return str(draw_result.get("error", "draw_failed"))
				events.append({
					"type": "effect_resolved",
					"actor_id": str(actor_id),
					"effect_index": index,
					"op": str(operation),
					"amount": amount,
					"drawn_count": int(draw_result.get("drawn_count", 0)),
				})
				continue
			&"choose_remove_card":
				var source_zone_key := StringName(effect.get("source_zone_key", ""))
				var source := state.zones.get(
					player.zone_ids.get(source_zone_key, &"")
				) as ZoneData
				var removed := state.zones.get(player.zone_ids.get(&"removed", &"")) as ZoneData
				if source == null or removed == null:
					return "missing_choice_zone"
				var source_zone_label := _source_zone_label(source_zone_key)
				var eligible_card_ids: Array[String] = []
				for card_instance_id: StringName in source.card_instance_ids:
					eligible_card_ids.append(str(card_instance_id))
				if eligible_card_ids.is_empty() or amount == 0:
					events.append({
						"type": "effect_resolved",
						"actor_id": str(actor_id),
						"effect_index": index,
						"op": str(operation),
						"selected_count": 0,
						"source_zone_id": str(source.zone_id),
						"source_zone_key": str(source_zone_key),
						"reason": "no_eligible_candidates",
					})
					continue
				if not state.effect_state.is_empty():
					return "effect_state_occupied"
				state.effect_state = {
					"type": "pending_choice",
					"choice_id": "choice-%06d" % (state.revision + 1),
					"actor_id": str(actor_id),
					"op": str(operation),
					"prompt": "可以從自己的%s移除 1 張牌" % source_zone_label,
					"source_zone_id": str(source.zone_id),
					"source_zone_key": str(source_zone_key),
					"destination_zone_id": str(removed.zone_id),
					"eligible_card_ids": eligible_card_ids,
					"min_selections": 0 if bool(effect.get("optional", false)) else 1,
					"max_selections": amount,
					"effect_index": index,
					"source_card_instance_id": str(
						effect.get("source_card_instance_id", "")
					),
				}
				events.append({
					"type": "choice_requested",
					"choice_id": str(state.effect_state["choice_id"]),
					"actor_id": str(actor_id),
					"op": str(operation),
					"eligible_card_ids": eligible_card_ids.duplicate(),
					"optional": bool(effect.get("optional", false)),
					"source_zone_id": str(source.zone_id),
					"source_zone_key": str(source_zone_key),
				})
				continue
			&"choose_gain_card":
				var source_zone_id := StringName(effect.get("source_zone_id", ""))
				var source := state.zones.get(source_zone_id) as ZoneData
				var destination := state.zones.get(
					player.zone_ids.get(&"discard_pile", &"")
				) as ZoneData
				if source == null or destination == null:
					return "missing_choice_zone"
				var max_cost := int(effect.get("max_cost", -1))
				var required_tag := StringName(effect.get("required_tag", ""))
				var eligible_card_ids: Array[String] = []
				for card_instance_id: StringName in source.card_instance_ids:
					var definition := _definition_for_card(state, definitions, card_instance_id)
					if definition == null or definition.cost == null:
						continue
					if not required_tag.is_empty() and required_tag not in definition.tags:
						continue
					if int(definition.cost) <= max_cost:
						eligible_card_ids.append(str(card_instance_id))
				if eligible_card_ids.is_empty() or amount == 0:
					events.append({
						"type": "effect_resolved",
						"actor_id": str(actor_id),
						"effect_index": index,
						"op": str(operation),
						"selected_count": 0,
						"source_zone_id": str(source.zone_id),
						"source_zone_key": "recruit_row",
						"reason": "no_eligible_candidates",
					})
					continue
				if not state.effect_state.is_empty():
					return "effect_state_occupied"
				state.effect_state = {
					"type": "pending_choice",
					"choice_id": "choice-%06d" % (state.revision + 1),
					"actor_id": str(actor_id),
					"op": str(operation),
					"prompt": "從招募區取得 1 張費用不超過 %d 的冒險者" % max_cost,
					"source_zone_id": str(source.zone_id),
					"source_zone_key": "recruit_row",
					"destination_zone_id": str(destination.zone_id),
					"eligible_card_ids": eligible_card_ids,
					"min_selections": 0 if bool(effect.get("optional", false)) else 1,
					"max_selections": amount,
					"effect_index": index,
					"source_card_instance_id": str(effect.get("source_card_instance_id", "")),
					"max_cost": max_cost,
					"required_tag": str(required_tag),
				}
				events.append({
					"type": "choice_requested",
					"choice_id": str(state.effect_state["choice_id"]),
					"actor_id": str(actor_id),
					"op": str(operation),
					"eligible_card_ids": eligible_card_ids.duplicate(),
					"optional": bool(effect.get("optional", false)),
					"source_zone_id": str(source.zone_id),
					"source_zone_key": "recruit_row",
					"destination_zone_id": str(destination.zone_id),
					"max_cost": max_cost,
					"required_tag": str(required_tag),
				})
				continue
			_:
				return "effect_not_immediately_resolvable: %s" % operation
		player.turn_resources[resource_key] = int(player.turn_resources.get(resource_key, 0)) + amount
		events.append({
			"type": "effect_resolved",
			"actor_id": str(actor_id),
			"effect_index": index,
			"op": str(operation),
			"amount": amount,
			"resource": str(resource_key),
			"new_value": int(player.turn_resources[resource_key]),
		})
	return ""


static func _source_zone_label(source_zone_key: StringName) -> String:
	return {
		&"hand": "手牌",
		&"discard_pile": "棄牌堆",
	}.get(source_zone_key, str(source_zone_key))


static func _definition_for_card(
	state: GameStateData,
	definitions: Dictionary,
	card_instance_id: StringName
) -> CardDefinition:
	var card := state.cards.get(card_instance_id) as Dictionary
	if card == null:
		return null
	return definitions.get(StringName(card.get("definition_id", ""))) as CardDefinition
