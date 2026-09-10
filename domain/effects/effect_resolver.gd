class_name EffectResolver
extends RefCounted

const SUPPORTED_OPERATIONS: Array[StringName] = [
	&"grant_purchase_power",
	&"grant_combat",
	&"draw",
	&"conditional_combat",
	&"choose_remove_from_hand",
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
		if operation == &"choose_remove_from_hand" and index != effects.size() - 1:
			errors.append("Pending choice effect must be last at %s[%d]" % [definition_id, index])
		if operation == &"choose_remove_from_hand" and int(effect.get("amount", 0)) != 1:
			errors.append("Hand removal choice amount must be 1 at %s[%d]" % [definition_id, index])
	return errors


static func resolve(
	state: GameStateData,
	actor_id: StringName,
	effects: Array[Dictionary],
	events: Array[Dictionary]
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
			&"choose_remove_from_hand":
				var hand := state.zones.get(player.zone_ids.get(&"hand", &"")) as ZoneData
				var removed := state.zones.get(player.zone_ids.get(&"removed", &"")) as ZoneData
				if hand == null or removed == null:
					return "missing_choice_zone"
				var eligible_card_ids: Array[String] = []
				for card_instance_id: StringName in hand.card_instance_ids:
					eligible_card_ids.append(str(card_instance_id))
				if eligible_card_ids.is_empty() or amount == 0:
					events.append({
						"type": "effect_resolved",
						"actor_id": str(actor_id),
						"effect_index": index,
						"op": str(operation),
						"selected_count": 0,
					})
					continue
				if not state.effect_state.is_empty():
					return "effect_state_occupied"
				state.effect_state = {
					"type": "pending_choice",
					"choice_id": "choice-%06d" % (state.revision + 1),
					"actor_id": str(actor_id),
					"op": str(operation),
					"prompt": "可以從手牌移除 1 張牌",
					"source_zone_id": str(hand.zone_id),
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
