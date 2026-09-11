class_name EffectResolver
extends RefCounted

const SUPPORTED_OPERATIONS: Array[StringName] = [
	&"grant_purchase_power",
	&"grant_combat",
	&"draw",
	&"discard_hand_and_draw",
	&"conditional_combat",
	&"choose_remove_card",
	&"choose_gain_card",
	&"roll_resource_reward",
	&"draft_gain_card",
	&"gain_from_supply_deck",
	&"choose_move_card",
	&"choose_refresh_row",
	&"choose_target_combat_modifier",
	&"inspect_deck_top",
	&"reposition_source",
	&"reveal_top_if_type",
	&"draw_then_choose_discard",
	&"roll_self_combat",
	&"roll_target_combat_modifier",
	&"equipment_policy",
	&"party_combat_aura",
	&"purchase_cost_modifier",
	&"position_departure",
	&"combat_departure_replacement",
	&"attached_value_combat",
	&"self_as_equipment",
	&"hand_purchase_power_modifier",
]


static func validate_effects(effects: Array[Dictionary], definition_id: StringName = &"") -> PackedStringArray:
	var errors := PackedStringArray()
	for index in effects.size():
		var effect := effects[index]
		var operation := StringName(effect.get("op", ""))
		if not operation in SUPPORTED_OPERATIONS:
			errors.append("Unsupported effect op %s at %s[%d]" % [operation, definition_id, index])
		if operation in [&"grant_purchase_power", &"grant_combat", &"draw"] \
				and int(effect.get("amount", 0)) < 0:
			errors.append("Effect amount must not be negative at %s[%d]" % [definition_id, index])
		if operation == &"choose_remove_card":
			var removal_amount := int(effect.get("amount", 0))
			if removal_amount < 1 or removal_amount > 2:
				errors.append("Card removal choice amount must be 1 or 2 at %s[%d]" % [definition_id, index])
			var removal_sources := _normalized_removal_sources(effect)
			if removal_sources.is_empty():
				errors.append("Card removal choice requires source zones at %s[%d]" % [definition_id, index])
			for source_zone_key: StringName in removal_sources:
				if source_zone_key not in [&"hand", &"party", &"discard_pile"]:
					errors.append("Unsupported removal source at %s[%d]" % [definition_id, index])
		if operation == &"choose_gain_card" \
				and (int(effect.get("amount", 0)) < 1 or int(effect.get("amount", 0)) > 2):
			errors.append("Card gain choice amount must be 1 or 2 at %s[%d]" % [definition_id, index])
		if operation == &"choose_gain_card" \
				and StringName(effect.get("source_zone_id", "")) \
				not in [SupplyService.RECRUIT_ROW_ID, SupplyService.SHOP_ROW_ID]:
			errors.append("Unsupported gain source at %s[%d]" % [definition_id, index])
		if operation == &"choose_gain_card" and int(effect.get("max_cost", -1)) < 0:
			errors.append("Card gain choice requires a non-negative max_cost at %s[%d]" % [definition_id, index])
		if operation == &"choose_gain_card":
			var allowed_card_types := _normalized_allowed_tags(
				effect.get("allowed_card_types", [])
			)
			var allowed_tags := _normalized_allowed_tags(effect.get("allowed_tags", []))
			if allowed_card_types.is_empty() or allowed_tags.is_empty():
				errors.append("Card gain choice requires type and tag filters at %s[%d]" % [definition_id, index])
			elif not _gain_filter_matches_source(
				StringName(effect.get("source_zone_id", "")), allowed_card_types, allowed_tags
			):
				errors.append("Card gain filters do not match source at %s[%d]" % [definition_id, index])
		if operation == &"roll_resource_reward":
			if int(effect.get("die_sides", 0)) < 2:
				errors.append("Dice reward requires at least two sides at %s[%d]" % [definition_id, index])
			if StringName(effect.get("resource", "")) not in [&"purchase_power", &"combat"]:
				errors.append("Dice reward resource is unsupported at %s[%d]" % [definition_id, index])
			if StringName(effect.get("conversion", "")) != &"ceil_divide" \
					or int(effect.get("divisor", 0)) < 1:
				errors.append("Dice reward conversion is invalid at %s[%d]" % [definition_id, index])
		if operation == &"draft_gain_card":
			if StringName(effect.get("source_deck_zone_id", "")).is_empty() \
					or StringName(effect.get("choice_zone_id", "")).is_empty():
				errors.append("Draft gain requires source and choice zones at %s[%d]" % [definition_id, index])
			if int(effect.get("cards_per_player", 0)) != 1 \
					or StringName(effect.get("destination_zone_key", "")) != &"hand":
				errors.append("Draft gain rule is invalid at %s[%d]" % [definition_id, index])
		if operation == &"gain_from_supply_deck":
			if StringName(effect.get("source_deck_zone_id", "")) \
					not in [SupplyService.RECRUIT_DECK_ID, SupplyService.SHOP_DECK_ID]:
				errors.append("Supply gain requires a supported source deck at %s[%d]" % [definition_id, index])
			var amount_source := StringName(effect.get("amount_source", ""))
			if amount_source not in [&"", &"participant_count"] \
					or (amount_source.is_empty() and int(effect.get("amount", 0)) < 1):
				errors.append("Supply gain requires a positive amount or participant_count at %s[%d]" % [definition_id, index])
			if StringName(effect.get("destination_zone_key", "discard_pile")) \
					not in [&"discard_pile", &"hand"]:
				errors.append("Supply gain destination is unsupported at %s[%d]" % [definition_id, index])
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
		if bool(effect.get("optional", false)) and effect.has("prompt") \
				and not bool(effect.get("_consent_granted", false)) \
				and operation not in [&"choose_remove_card", &"choose_gain_card", &"choose_move_card", &"choose_refresh_row", &"choose_target_combat_modifier", &"inspect_deck_top"]:
			var source_card_id := StringName(effect.get("source_card_instance_id", ""))
			var source_zone_id := ZoneService.find_card_zone(state, source_card_id)
			if source_zone_id.is_empty():
				return "optional_effect_source_moved"
			var accepted_effect := effect.duplicate(true)
			accepted_effect["_consent_granted"] = true
			state.effect_state = {
				"type": "pending_choice", "choice_id": "choice-%06d" % (state.revision + 1),
				"actor_id": str(actor_id), "required_actor_id": str(actor_id),
				"op": "confirm_effect", "prompt": str(effect.get("prompt", "可以發動此效果")),
				"source_zone_id": str(source_zone_id), "source_zone_key": "effect_source",
				"destination_zone_id": str(source_zone_id),
				"eligible_card_ids": [str(source_card_id)], "selected_card_ids": [], "selected_count": 0,
				"min_selections": 0, "max_selections": 1,
				"source_card_instance_id": str(source_card_id),
				"accepted_effect": accepted_effect,
				"continuation_effects": _remaining_effects(effects, index + 1),
			}
			events.append({"type":"choice_requested","choice_id":str(state.effect_state["choice_id"]),"actor_id":str(actor_id),"required_actor_id":str(actor_id),"op":"confirm_effect","eligible_card_ids":[str(source_card_id)],"optional":true,"source_card_instance_id":str(source_card_id)})
			return ""
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
			&"discard_hand_and_draw":
				var hand_zone_id := StringName(player.zone_ids.get(&"hand", &""))
				var discard_zone_id := StringName(player.zone_ids.get(&"discard_pile", &""))
				var draw_zone_id := StringName(player.zone_ids.get(&"draw_pile", &""))
				var hand := state.zones.get(hand_zone_id) as ZoneData
				var discard := state.zones.get(discard_zone_id) as ZoneData
				var draw_pile := state.zones.get(draw_zone_id) as ZoneData
				if hand == null or discard == null or draw_pile == null:
					return "missing_player_card_zone"
				var locked_card_ids := hand.card_instance_ids.duplicate()
				var locked_count := locked_card_ids.size()
				events.append({
					"type": "hand_redraw_started",
					"actor_id": str(actor_id),
					"locked_card_ids": _string_name_array_to_strings(locked_card_ids),
					"locked_count": locked_count,
				})
				for card_instance_id: StringName in locked_card_ids:
					var move_result := ZoneService.move_card(
						state, card_instance_id, hand_zone_id, discard_zone_id
					)
					if not bool(move_result.get("ok", false)):
						return str(move_result.get("error", "hand_redraw_discard_failed"))
					var move_event := (move_result.get("event", {}) as Dictionary).duplicate(true)
					move_event["reason"] = "hand_redraw_discard"
					events.append(move_event)
				var redraw_result := DeckService.draw_cards(
					state, actor_id, locked_count, events
				)
				if not bool(redraw_result.get("ok", false)):
					return str(redraw_result.get("error", "hand_redraw_draw_failed"))
				if int(redraw_result.get("drawn_count", 0)) != locked_count:
					return "hand_redraw_count_mismatch"
				events.append({
					"type": "effect_resolved",
					"actor_id": str(actor_id),
					"effect_index": index,
					"op": str(operation),
					"discarded_count": locked_count,
					"drawn_count": int(redraw_result.get("drawn_count", 0)),
				})
				continue
			&"choose_remove_card":
				var source_zone_keys := _normalized_removal_sources(effect)
				var removed := state.zones.get(player.zone_ids.get(&"removed", &"")) as ZoneData
				if removed == null:
					return "missing_choice_zone"
				var source_zone_ids: Dictionary = {}
				var eligible_card_ids: Array[String] = []
				var eligible_card_sources: Dictionary = {}
				for source_zone_key: StringName in source_zone_keys:
					var source_zone_id := StringName(player.zone_ids.get(source_zone_key, &""))
					var source := state.zones.get(source_zone_id) as ZoneData
					if source == null:
						return "missing_choice_zone"
					source_zone_ids[str(source_zone_key)] = str(source_zone_id)
					for card_instance_id: StringName in source.card_instance_ids:
						eligible_card_ids.append(str(card_instance_id))
						eligible_card_sources[str(card_instance_id)] = {
							"zone_key": str(source_zone_key),
							"zone_id": str(source_zone_id),
						}
				if eligible_card_ids.is_empty() or amount == 0:
					events.append({
						"type": "effect_resolved",
						"actor_id": str(actor_id),
						"effect_index": index,
						"op": str(operation),
						"selected_count": 0,
						"source_zone_ids": source_zone_ids.duplicate(true),
						"source_zone_keys": _string_name_array_to_strings(source_zone_keys),
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
					"prompt": _removal_prompt(source_zone_keys, amount),
					"source_zone_ids": source_zone_ids,
					"source_zone_keys": _string_name_array_to_strings(source_zone_keys),
					"destination_zone_id": str(removed.zone_id),
					"eligible_card_ids": eligible_card_ids,
					"eligible_card_sources": eligible_card_sources,
					"min_selections": 0 if bool(effect.get("optional", false)) else amount,
					"max_selections": amount,
					"selected_card_ids": [],
					"selected_count": 0,
					"effect_index": index,
					"source_card_instance_id": str(
						effect.get("source_card_instance_id", "")
					),
					"continuation_effects": _remaining_effects(effects, index + 1),
				}
				events.append({
					"type": "choice_requested",
					"choice_id": str(state.effect_state["choice_id"]),
					"actor_id": str(actor_id),
					"op": str(operation),
					"eligible_card_ids": eligible_card_ids.duplicate(),
					"optional": bool(effect.get("optional", false)),
					"source_zone_ids": source_zone_ids.duplicate(true),
					"source_zone_keys": _string_name_array_to_strings(source_zone_keys),
					"min_selections": int(state.effect_state["min_selections"]),
					"max_selections": amount,
				})
				return ""
			&"choose_gain_card":
				var source_zone_id := StringName(effect.get("source_zone_id", ""))
				var source_zone_key := _gain_source_zone_key(source_zone_id)
				var source := state.zones.get(source_zone_id) as ZoneData
				var destination := state.zones.get(
					player.zone_ids.get(&"discard_pile", &"")
				) as ZoneData
				if source == null or destination == null:
					return "missing_choice_zone"
				var max_cost := int(effect.get("max_cost", -1))
				var allowed_card_types := _normalized_allowed_tags(
					effect.get("allowed_card_types", [])
				)
				var allowed_tags := _normalized_allowed_tags(effect.get("allowed_tags", []))
				var eligible_card_ids: Array[String] = []
				for card_instance_id: StringName in source.card_instance_ids:
					var definition := _definition_for_card(state, definitions, card_instance_id)
					if definition == null or definition.cost == null:
						continue
					if definition.card_type not in allowed_card_types \
							or not _definition_has_any_tag(definition, allowed_tags):
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
						"source_zone_key": str(source_zone_key),
						"reason": "no_eligible_candidates",
					})
					continue
				if not state.effect_state.is_empty():
					return "effect_state_occupied"
				var required_count := mini(amount, eligible_card_ids.size())
				state.effect_state = {
					"type": "pending_choice",
					"choice_id": "choice-%06d" % (state.revision + 1),
					"actor_id": str(actor_id),
					"op": str(operation),
					"prompt": "從%s取得 %d 張費用不超過 %d 的%s" % [
						_gain_source_label(source_zone_key),
						required_count,
						max_cost,
						_gain_filter_label(allowed_card_types),
					],
					"source_zone_id": str(source.zone_id),
					"source_zone_key": str(source_zone_key),
					"destination_zone_id": str(destination.zone_id),
					"eligible_card_ids": eligible_card_ids,
					"min_selections": 0 if bool(effect.get("optional", false)) else required_count,
					"max_selections": required_count,
					"selected_card_ids": [],
					"selected_count": 0,
					"effect_index": index,
					"source_card_instance_id": str(effect.get("source_card_instance_id", "")),
					"source_effect": effect.duplicate(true),
					"max_cost": max_cost,
					"allowed_card_types": _string_name_array_to_strings(allowed_card_types),
					"allowed_tags": _string_name_array_to_strings(allowed_tags),
					"continuation_effects": _remaining_effects(effects, index + 1),
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
					"destination_zone_id": str(destination.zone_id),
					"max_cost": max_cost,
					"allowed_card_types": _string_name_array_to_strings(allowed_card_types),
					"allowed_tags": _string_name_array_to_strings(allowed_tags),
				})
				return ""
			&"gain_from_supply_deck":
				var source_deck_zone_id := StringName(effect.get("source_deck_zone_id", ""))
				var source_deck := state.zones.get(source_deck_zone_id) as ZoneData
				var destination_zone_key := StringName(effect.get("destination_zone_key", "discard_pile"))
				var destination := state.zones.get(player.zone_ids.get(destination_zone_key, &"")) as ZoneData
				if source_deck == null or destination == null:
					return "missing_supply_gain_zone"
				var requested_amount := (
					int(effect.get("participant_count", 0))
					if StringName(effect.get("amount_source", "")) == &"participant_count"
					else amount
				)
				var gain_result := SupplyService.take_supply_cards(
					state, source_deck_zone_id, destination.zone_id, actor_id,
					requested_amount, &"supply_deck_reward_gained", events
				)
				if not bool(gain_result.get("ok", false)):
					return str(gain_result.get("error", "supply_gain_failed"))
				var gained_ids := gain_result.get("gained_card_ids", []) as Array
				events.append({
					"type": "effect_resolved", "actor_id": str(actor_id),
					"effect_index": index, "op": str(operation),
					"requested_count": requested_amount, "selected_count": gained_ids.size(),
					"gained_card_ids": gained_ids, "source_zone_id": str(source_deck_zone_id),
					"destination_zone_id": str(destination.zone_id),
				})
				continue
			&"choose_move_card":
				var source_zone_key := StringName(effect.get("source_zone_key", ""))
				var destination_zone_key := StringName(effect.get("destination_zone_key", ""))
				var source := state.zones.get(player.zone_ids.get(source_zone_key, &"")) as ZoneData
				var destination := state.zones.get(player.zone_ids.get(destination_zone_key, &"")) as ZoneData
				if source == null or destination == null:
					return "missing_choice_zone"
				var allowed_tags := _normalized_allowed_tags(effect.get("allowed_tags", []))
				var eligible_ids: Array[String] = []
				for card_id: StringName in source.card_instance_ids:
					var definition := _definition_for_card(state, definitions, card_id)
					if allowed_tags.is_empty() or _definition_has_any_tag(definition, allowed_tags):
						eligible_ids.append(str(card_id))
				if eligible_ids.is_empty():
					events.append({"type":"effect_resolved","actor_id":str(actor_id),"effect_index":index,"op":str(operation),"selected_count":0,"reason":"no_eligible_candidates"})
					continue
				state.effect_state = _card_choice(
					state, actor_id, operation, effect, source.zone_id, source_zone_key,
					destination.zone_id, eligible_ids, 0 if bool(effect.get("optional", false)) else 1, 1
				)
				state.effect_state["allowed_tags"] = _string_name_array_to_strings(allowed_tags)
				state.effect_state["continuation_effects"] = _remaining_effects(effects, index + 1)
				events.append(_choice_requested_event(state.effect_state))
				return ""
			&"choose_target_combat_modifier":
				var source_zone_id := StringName(effect.get("source_zone_id", ""))
				var source := state.zones.get(source_zone_id) as ZoneData
				if source == null:
					return "missing_choice_zone"
				var allowed_types := _normalized_allowed_tags(effect.get("allowed_card_types", []))
				var eligible_ids: Array[String] = []
				for card_id: StringName in source.card_instance_ids:
					var definition := _definition_for_card(state, definitions, card_id)
					if definition != null and definition.card_type in allowed_types:
						eligible_ids.append(str(card_id))
				if eligible_ids.is_empty():
					events.append({"type":"effect_resolved","actor_id":str(actor_id),"effect_index":index,"op":str(operation),"selected_count":0,"reason":"no_eligible_candidates"})
					continue
				state.effect_state = _card_choice(state, actor_id, operation, effect, source.zone_id, &"public_enemy", source.zone_id, eligible_ids, 0 if bool(effect.get("optional", false)) else 1, 1)
				state.effect_state["allowed_card_types"] = _string_name_array_to_strings(allowed_types)
				state.effect_state["modifier_amount"] = int(effect.get("amount", 0))
				state.effect_state["continuation_effects"] = _remaining_effects(effects, index + 1)
				events.append(_choice_requested_event(state.effect_state))
				return ""
			&"choose_refresh_row":
				var source_zone_id := StringName(effect.get("source_zone_id", ""))
				var destination_zone_id := StringName(effect.get("destination_zone_id", ""))
				var source := state.zones.get(source_zone_id) as ZoneData
				if source == null or not state.zones.has(destination_zone_id):
					return "missing_choice_zone"
				var eligible_ids: Array[String] = []
				for card_id: StringName in source.card_instance_ids:
					eligible_ids.append(str(card_id))
				if eligible_ids.is_empty():
					continue
				var maximum := mini(amount, eligible_ids.size())
				state.effect_state = _card_choice(state, actor_id, operation, effect, source.zone_id, &"monster_row", destination_zone_id, eligible_ids, 0, maximum)
				state.effect_state["original_order"] = eligible_ids.duplicate()
				state.effect_state["continuation_effects"] = _remaining_effects(effects, index + 1)
				events.append(_choice_requested_event(state.effect_state))
				return ""
			&"inspect_deck_top":
				var deck := state.zones.get(player.zone_ids.get(&"draw_pile", &"")) as ZoneData
				var inspection := state.zones.get(player.zone_ids.get(&"inspection", &"")) as ZoneData
				if deck == null or inspection == null or not inspection.card_instance_ids.is_empty():
					return "missing_inspection_zone"
				var revealed_ids: Array[String] = []
				for reveal_index in mini(amount, deck.card_instance_ids.size()):
					var revealed_id := StringName(deck.card_instance_ids.back())
					var move_result := ZoneService.move_card(
						state, revealed_id, deck.zone_id, inspection.zone_id
					)
					if not bool(move_result.get("ok", false)):
						return str(move_result.get("error", "inspection_reveal_failed"))
					revealed_ids.append(str(revealed_id))
				if revealed_ids.is_empty():
					continue
				state.effect_state = _card_choice(
					state, actor_id, operation, effect, inspection.zone_id, &"inspection",
					StringName(player.zone_ids.get(&"removed", &"")), revealed_ids,
					0, mini(int(effect.get("remove_max", 1)), revealed_ids.size())
				)
				state.effect_state["draw_pile_zone_id"] = str(deck.zone_id)
				state.effect_state["original_order"] = revealed_ids.duplicate()
				state.effect_state["continuation_effects"] = _remaining_effects(effects, index + 1)
				events.append({
					"type": "cards_inspected", "actor_id": str(actor_id),
					"source_card_instance_id": str(effect.get("source_card_instance_id", "")),
					"card_instance_ids": revealed_ids.duplicate(), "count": revealed_ids.size(),
				})
				events.append(_choice_requested_event(state.effect_state))
				return ""
			&"reposition_source":
				var source_card_id := StringName(effect.get("source_card_instance_id", ""))
				var party := state.zones.get(player.zone_ids.get(&"party", &"")) as ZoneData
				if party == null or source_card_id not in party.card_instance_ids:
					return "effect_source_moved"
				party.card_instance_ids.erase(source_card_id)
				party.card_instance_ids.insert(clampi(int(effect.get("destination_index", 0)), 0, party.card_instance_ids.size()), source_card_id)
				events.append({"type":"party_reordered","actor_id":str(actor_id),"card_instance_id":str(source_card_id),"destination_index":int(effect.get("destination_index",0))})
				continue
			&"reveal_top_if_type":
				var deck := state.zones.get(player.zone_ids.get(&"draw_pile", &"")) as ZoneData
				if deck == null:
					return "missing_player_card_zone"
				if deck.card_instance_ids.is_empty():
					continue
				var top_id := StringName(deck.card_instance_ids.back())
				var top_definition := _definition_for_card(state, definitions, top_id)
				if top_definition != null and top_definition.card_type in _normalized_allowed_tags(effect.get("allowed_card_types", [])):
					var destination_id := StringName(player.zone_ids.get(StringName(effect.get("destination_zone_key", "hand")), &""))
					var move_result := ZoneService.move_card(state, top_id, deck.zone_id, destination_id)
					if not bool(move_result.get("ok", false)):
						return str(move_result.get("error", "reveal_gain_failed"))
					var move_event := (move_result.get("event", {}) as Dictionary).duplicate(true)
					move_event["reason"] = "revealed_top_card_gained"
					events.append(move_event)
					events.append({"type":"card_revealed","actor_id":str(actor_id),"card_instance_id":str(top_id)})
				continue
			&"draw_then_choose_discard":
				var draw_result := DeckService.draw_cards(state, actor_id, int(effect.get("draw_amount", 0)), events)
				if not bool(draw_result.get("ok", false)):
					return str(draw_result.get("error", "draw_failed"))
				var discard_effect := {"op":"choose_move_card","source_zone_key":"hand","destination_zone_key":"discard_pile","amount":int(effect.get("discard_amount",1)),"optional":false,"prompt":"從手牌棄置 1 張牌","source_card_instance_id":str(effect.get("source_card_instance_id",""))}
				var remaining: Array[Dictionary] = [discard_effect]
				remaining.append_array(_remaining_effects(effects, index + 1))
				return resolve(state, actor_id, remaining, events, definitions)
			&"roll_self_combat":
				var rng := DeterministicRng.new(state.seed_value, state.rng_state)
				var die_result: int = rng.roll_die(int(effect.get("die_sides", 6)))
				state.rng_state = rng.get_state()
				var bonus := int(effect.get("odd_amount", 0)) if die_result % 2 == 1 else 0
				var modifiers := player.turn_bonuses.get("card_combat_modifiers", {}) as Dictionary
				var source_card_id := str(effect.get("source_card_instance_id", ""))
				modifiers[source_card_id] = int(modifiers.get(source_card_id, 0)) + bonus
				player.turn_bonuses["card_combat_modifiers"] = modifiers
				events.append({"type":"die_rolled","actor_id":str(actor_id),"source_card_instance_id":source_card_id,"die_sides":int(effect.get("die_sides",6)),"die_result":die_result,"resource":"card_combat","amount":bonus})
				continue
			&"roll_target_combat_modifier":
				var target_effect := effect.duplicate(true)
				target_effect["op"] = "choose_target_combat_modifier"
				target_effect["_consent_granted"] = true
				var source := state.zones.get(StringName(effect.get("source_zone_id", ""))) as ZoneData
				if source == null or source.card_instance_ids.is_empty():
					continue
				var rng := DeterministicRng.new(state.seed_value, state.rng_state)
				var die_result := rng.roll_die(int(effect.get("die_sides", 6)))
				state.rng_state = rng.get_state()
				target_effect["amount"] = -((die_result + int(effect.get("divisor", 2)) - 1) / int(effect.get("divisor", 2)))
				events.append({"type":"die_rolled","actor_id":str(actor_id),"source_card_instance_id":str(effect.get("source_card_instance_id","")),"die_sides":int(effect.get("die_sides",6)),"die_result":die_result,"resource":"target_combat","amount":int(target_effect["amount"])})
				var remaining: Array[Dictionary] = [target_effect]
				remaining.append_array(_remaining_effects(effects, index + 1))
				return resolve(state, actor_id, remaining, events, definitions)
			&"roll_resource_reward":
				var die_sides := int(effect.get("die_sides", 0))
				var divisor := int(effect.get("divisor", 0))
				resource_key = StringName(effect.get("resource", ""))
				var rng := DeterministicRng.new(state.seed_value, state.rng_state)
				var die_result := rng.roll_die(die_sides)
				state.rng_state = rng.get_state()
				amount = (die_result + divisor - 1) / divisor
				player.turn_resources[resource_key] = int(
					player.turn_resources.get(resource_key, 0)
				) + amount
				var source_card_instance_id := str(effect.get("source_card_instance_id", ""))
				events.append({
					"type": "die_rolled",
					"actor_id": str(actor_id),
					"source_card_instance_id": source_card_instance_id,
					"die_sides": die_sides,
					"die_result": die_result,
					"conversion": str(effect.get("conversion", "")),
					"divisor": divisor,
					"resource": str(resource_key),
					"amount": amount,
				})
				events.append({
					"type": "effect_resolved",
					"actor_id": str(actor_id),
					"effect_index": index,
					"op": str(operation),
					"source_card_instance_id": source_card_instance_id,
					"die_sides": die_sides,
					"die_result": die_result,
					"amount": amount,
					"resource": str(resource_key),
					"new_value": int(player.turn_resources[resource_key]),
				})
				continue
			&"draft_gain_card":
				var source_deck_zone_id := StringName(effect.get("source_deck_zone_id", ""))
				var choice_zone_id := StringName(effect.get("choice_zone_id", ""))
				var source_deck := state.zones.get(source_deck_zone_id) as ZoneData
				var choice_zone := state.zones.get(choice_zone_id) as ZoneData
				if source_deck == null or choice_zone == null:
					return "missing_draft_zone"
				if source_deck.kind != &"ordered_deck" or source_deck.visibility != &"hidden" \
						or choice_zone.kind != &"face_up_row" or choice_zone.visibility != &"public" \
						or not bool(choice_zone.metadata.get("temporary_choice_zone", false)):
					return "invalid_draft_zone"
				if not choice_zone.card_instance_ids.is_empty():
					return "draft_zone_not_empty"
				if not state.effect_state.is_empty():
					return "effect_state_occupied"
				var reveal_count := mini(
					state.turn_order.size() * int(effect.get("cards_per_player", 1)),
					source_deck.card_instance_ids.size()
				)
				var revealed_card_ids: Array[String] = []
				for reveal_index in reveal_count:
					var revealed_id: StringName = source_deck.card_instance_ids.back()
					var reveal_result := ZoneService.move_card(
						state, revealed_id, source_deck_zone_id, choice_zone_id
					)
					if not bool(reveal_result.get("ok", false)):
						return str(reveal_result.get("error", "draft_reveal_failed"))
					var reveal_event := (reveal_result.get("event", {}) as Dictionary).duplicate(true)
					reveal_event["reason"] = "resource_draft_reveal"
					reveal_event["actor_id"] = str(actor_id)
					reveal_event["source_card_instance_id"] = str(
						effect.get("source_card_instance_id", "")
					)
					events.append(reveal_event)
					revealed_card_ids.append(str(revealed_id))
				if revealed_card_ids.is_empty():
					events.append({
						"type": "effect_resolved",
						"actor_id": str(actor_id),
						"effect_index": index,
						"op": str(operation),
						"selected_count": 0,
						"reason": "source_deck_empty",
					})
					continue
				var selection_order := _turn_order_from_actor(state, actor_id)
				selection_order.resize(revealed_card_ids.size())
				state.effect_state = {
					"type": "pending_choice",
					"choice_id": "choice-%06d" % (state.revision + 1),
					"actor_id": str(actor_id),
					"required_actor_id": selection_order[0],
					"defeated_by_actor_id": str(actor_id),
					"op": str(operation),
					"choice_title": str(effect.get("choice_title", "多人輪抽")),
					"prompt": str(effect.get("prompt", "選擇 1 張加入自己的手牌")),
					"source_deck_zone_id": str(source_deck_zone_id),
					"source_zone_id": str(choice_zone_id),
					"source_zone_key": "resource_draft_row",
					"choice_zone_id": str(choice_zone_id),
					"destination_zone_key": str(effect.get("destination_zone_key", "hand")),
					"eligible_card_ids": revealed_card_ids.duplicate(),
					"remaining_card_ids": revealed_card_ids.duplicate(),
					"selected_card_ids": [],
					"selected_count": 0,
					"min_selections": 1,
					"max_selections": 1,
					"selection_order": selection_order,
					"selection_index": 0,
					"completed_selections": [],
					"effect_index": index,
					"source_effect": effect.duplicate(true),
					"source_card_instance_id": str(effect.get("source_card_instance_id", "")),
					"continuation_effects": _remaining_effects(effects, index + 1),
				}
				events.append({
					"type": "choice_requested",
					"choice_id": str(state.effect_state["choice_id"]),
					"actor_id": str(actor_id),
					"required_actor_id": selection_order[0],
					"op": str(operation),
					"eligible_card_ids": revealed_card_ids.duplicate(),
					"remaining_card_ids": revealed_card_ids.duplicate(),
					"selection_order": selection_order.duplicate(),
					"source_deck_zone_id": str(source_deck_zone_id),
					"choice_zone_id": str(choice_zone_id),
					"optional": false,
				})
				return ""
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


static func resolve_trigger_for_source(
	state: GameStateData,
	actor_id: StringName,
	source_card_id: StringName,
	timing: StringName,
	events: Array[Dictionary],
	definitions: Dictionary
) -> String:
	var definition := _definition_for_card(state, definitions, source_card_id)
	if definition == null:
		return "missing_definition"
	var effects: Array[Dictionary] = []
	for effect: Dictionary in definition.effects:
		if StringName(effect.get("timing", "")) != timing or not _condition_matches(state, actor_id, effect):
			continue
		var runtime_effect := effect.duplicate(true)
		runtime_effect["source_card_instance_id"] = str(source_card_id)
		effects.append(runtime_effect)
	return resolve(state, actor_id, effects, events, definitions)


static func resolve_party_trigger(
	state: GameStateData,
	actor_id: StringName,
	timing: StringName,
	events: Array[Dictionary],
	definitions: Dictionary
) -> String:
	var player := state.players.get(actor_id) as PlayerStateData
	var party := state.zones.get(player.zone_ids.get(&"party", &"")) as ZoneData if player != null else null
	if party == null:
		return "missing_player_card_zone"
	var effects: Array[Dictionary] = []
	var source_ids: Array[StringName] = party.card_instance_ids.duplicate()
	for raw_source_id: Variant in player.turn_facts.get("combat_participant_ids", []):
		var departed_id := StringName(str(raw_source_id))
		if departed_id not in source_ids:
			source_ids.append(departed_id)
	for source_card_id: StringName in source_ids:
		var definition := _definition_for_card(state, definitions, source_card_id)
		if definition == null:
			continue
		for effect: Dictionary in definition.effects:
			if StringName(effect.get("timing", "")) == timing and _condition_matches(state, actor_id, effect):
				var runtime_effect := effect.duplicate(true)
				runtime_effect["source_card_instance_id"] = str(source_card_id)
				effects.append(runtime_effect)
	return resolve(state, actor_id, effects, events, definitions)


static func _condition_matches(state: GameStateData, actor_id: StringName, effect: Dictionary) -> bool:
	var condition := StringName(effect.get("condition", ""))
	if condition.is_empty():
		return true
	var player := state.players.get(actor_id) as PlayerStateData
	return player != null and condition == &"defeated_enemy" and bool(player.turn_facts.get("defeated_enemy", false))


static func _remaining_effects(effects: Array[Dictionary], start: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(start, effects.size()):
		result.append(effects[index].duplicate(true))
	return result


static func _card_choice(
	state: GameStateData,
	actor_id: StringName,
	operation: StringName,
	effect: Dictionary,
	source_zone_id: StringName,
	source_zone_key: StringName,
	destination_zone_id: StringName,
	eligible_ids: Array[String],
	minimum: int,
	maximum: int
) -> Dictionary:
	return {"type":"pending_choice","choice_id":"choice-%06d" % (state.revision + 1),"actor_id":str(actor_id),"required_actor_id":str(actor_id),"op":str(operation),"prompt":str(effect.get("prompt","選擇卡牌")),"source_zone_id":str(source_zone_id),"source_zone_key":str(source_zone_key),"destination_zone_id":str(destination_zone_id),"eligible_card_ids":eligible_ids.duplicate(),"selected_card_ids":[],"selected_count":0,"min_selections":minimum,"max_selections":maximum,"source_card_instance_id":str(effect.get("source_card_instance_id","")),"source_effect":effect.duplicate(true)}


static func _choice_requested_event(choice: Dictionary) -> Dictionary:
	return {"type":"choice_requested","choice_id":str(choice.get("choice_id","")),"actor_id":str(choice.get("actor_id","")),"required_actor_id":str(choice.get("required_actor_id","")),"op":str(choice.get("op","")),"eligible_card_ids":choice.get("eligible_card_ids",[]),"optional":int(choice.get("min_selections",1))==0,"source_card_instance_id":str(choice.get("source_card_instance_id","")),"min_selections":int(choice.get("min_selections",0)),"max_selections":int(choice.get("max_selections",1))}


static func _source_zone_label(source_zone_key: StringName) -> String:
	return {
		&"hand": "手牌",
		&"party": "隊伍",
		&"discard_pile": "棄牌堆",
	}.get(source_zone_key, str(source_zone_key))


static func _normalized_removal_sources(effect: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	var raw_sources: Variant = effect.get("source_zone_keys", [])
	if raw_sources is Array:
		for raw_source: Variant in raw_sources:
			var source_zone_key := StringName(str(raw_source))
			if not source_zone_key.is_empty() and source_zone_key not in result:
				result.append(source_zone_key)
	if result.is_empty():
		var legacy_source := StringName(effect.get("source_zone_key", ""))
		if not legacy_source.is_empty():
			result.append(legacy_source)
	return result


static func _removal_prompt(source_zone_keys: Array[StringName], amount: int) -> String:
	var labels: Array[String] = []
	for source_zone_key: StringName in source_zone_keys:
		labels.append(_source_zone_label(source_zone_key))
	return "可以從自己的%s移除%s" % [
		_join_labels_with_or(labels),
		" 1 張牌" if amount == 1 else "最多 %d 張牌" % amount,
	]


static func _join_labels_with_or(labels: Array[String]) -> String:
	if labels.size() < 2:
		return "" if labels.is_empty() else labels[0]
	return "%s或%s" % ["、".join(labels.slice(0, -1)), labels.back()]


static func _gain_source_zone_key(source_zone_id: StringName) -> StringName:
	return &"recruit_row" if source_zone_id == SupplyService.RECRUIT_ROW_ID else &"shop_row"


static func _gain_source_label(source_zone_key: StringName) -> String:
	return "招募區" if source_zone_key == &"recruit_row" else "商店"


static func _gain_filter_label(allowed_card_types: Array[StringName]) -> String:
	if allowed_card_types == [&"adventurer"]:
		return "冒險者"
	if allowed_card_types == [&"item", &"equipment"]:
		return "道具或裝備"
	if allowed_card_types == [&"item"]:
		return "道具"
	if allowed_card_types == [&"equipment"]:
		return "裝備"
	return "指定類型卡牌"


static func _normalized_allowed_tags(raw_tags: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if not raw_tags is Array:
		return result
	for raw_tag: Variant in raw_tags:
		var tag := StringName(str(raw_tag))
		if tag.is_empty() or tag in result:
			continue
		result.append(tag)
	return result


static func _gain_filter_matches_source(
	source_zone_id: StringName,
	allowed_card_types: Array[StringName],
	allowed_tags: Array[StringName]
) -> bool:
	if source_zone_id == SupplyService.RECRUIT_ROW_ID:
		return _all_values_allowed(allowed_card_types, [&"adventurer"]) \
				and not allowed_tags.is_empty()
	if source_zone_id == SupplyService.SHOP_ROW_ID:
		return _all_values_allowed(allowed_card_types, [&"item", &"equipment"]) \
				and not allowed_tags.is_empty()
	return false


static func _all_values_allowed(
	values: Array[StringName],
	allowed_values: Array[StringName]
) -> bool:
	if values.is_empty():
		return false
	for value: StringName in values:
		if value not in allowed_values:
			return false
	return true


static func _definition_has_any_tag(
	definition: CardDefinition,
	allowed_tags: Array[StringName]
) -> bool:
	for tag: StringName in allowed_tags:
		if tag in definition.tags:
			return true
	return false


static func _definition_for_card(
	state: GameStateData,
	definitions: Dictionary,
	card_instance_id: StringName
) -> CardDefinition:
	var card := state.cards.get(card_instance_id) as Dictionary
	if card == null:
		return null
	return definitions.get(StringName(card.get("definition_id", ""))) as CardDefinition


static func _string_name_array_to_strings(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value: StringName in values:
		result.append(str(value))
	return result


static func _turn_order_from_actor(state: GameStateData, actor_id: StringName) -> Array[String]:
	var result: Array[String] = []
	var start_index := state.turn_order.find(actor_id)
	for offset in state.turn_order.size():
		result.append(str(state.turn_order[(start_index + offset) % state.turn_order.size()]))
	return result
