class_name ChoiceService
extends RefCounted


static func get_legal_commands(
	state: GameStateData,
	actor_id: StringName
) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	var choice := state.effect_state
	if StringName(choice.get("type", "")) != &"pending_choice" \
			or _required_actor_id(choice) != actor_id:
		return commands
	if StringName(choice.get("op", "")) in [&"select_bonds", &"complete_bonds"]:
		return BondService.legal_commands(state, actor_id)
	var selected_card_ids := choice.get("selected_card_ids", []) as Array
	var candidate_ids := (
		choice.get("remaining_card_ids", []) as Array
		if StringName(choice.get("op", "")) == &"draft_gain_card"
		else choice.get("eligible_card_ids", []) as Array
	)
	for raw_card_id: Variant in candidate_ids:
		if str(raw_card_id) in selected_card_ids:
			continue
		commands.append({
			"type": "RESOLVE_CHOICE",
			"actor_id": str(actor_id),
			"expected_revision": state.revision,
			"choice_id": str(choice.get("choice_id", "")),
			"card_instance_id": str(raw_card_id),
			"skip": false,
		})
	var selected_count := int(choice.get("selected_count", selected_card_ids.size()))
	if StringName(choice.get("op", "")) != &"draft_gain_card" \
			and selected_count >= int(choice.get("min_selections", 1)):
		commands.append({
			"type": "RESOLVE_CHOICE",
			"actor_id": str(actor_id),
			"expected_revision": state.revision,
			"choice_id": str(choice.get("choice_id", "")),
			"card_instance_id": "",
			"skip": true,
		})
	return commands


static func validate(
	state: GameStateData,
	actor_id: StringName,
	command: Dictionary,
	definitions: Dictionary = {}
) -> String:
	var choice := state.effect_state
	if StringName(choice.get("type", "")) != &"pending_choice":
		return "no_pending_choice"
	if StringName(choice.get("op", "")) in [&"select_bonds", &"complete_bonds"]:
		return BondService.validate_choice(state, actor_id, command)
	if _required_actor_id(choice) != actor_id:
		return "wrong_choice_actor"
	if str(command.get("choice_id", "")) != str(choice.get("choice_id", "")):
		return "wrong_choice_id"
	if not command.get("skip", false) is bool:
		return "invalid_choice_skip"
	var skip := bool(command.get("skip", false))
	var card_instance_id := StringName(command.get("card_instance_id", ""))
	var operation := StringName(choice.get("op", ""))
	var locked_source_zone := StringName(choice.get("source_card_zone_id", ""))
	if not locked_source_zone.is_empty() and ZoneService.find_card_zone(
		state, StringName(choice.get("source_card_instance_id", ""))
	) != locked_source_zone:
		return "choice_effect_source_moved"
	var selected_card_ids := choice.get("selected_card_ids", []) as Array
	var selected_count := int(choice.get("selected_count", selected_card_ids.size()))
	var completion_error := _validate_boss_completion_payload(
		state, actor_id, choice, definitions
	)
	if not completion_error.is_empty():
		return completion_error
	if skip:
		if operation == &"draft_gain_card":
			return "choice_required"
		if selected_count < int(choice.get("min_selections", 1)):
			return "choice_required"
		if not card_instance_id.is_empty():
			return "invalid_skipped_choice"
		return ""
	if card_instance_id.is_empty():
		return "missing_choice_card"
	if str(card_instance_id) in selected_card_ids:
		return "choice_card_already_selected"
	if operation != &"draft_gain_card" \
			and selected_count >= int(choice.get("max_selections", 1)):
		return "choice_selection_limit_reached"
	if not str(card_instance_id) in (choice.get("eligible_card_ids", []) as Array):
		return "ineligible_choice_card"
	if operation == &"choose_supply_deck_draft":
		var source_effect := choice.get("source_effect", {}) as Dictionary
		var source_deck := state.zones.get(card_instance_id) as ZoneData
		var draft_zone := state.zones.get(HelperService.DRAFT_ROW_ID) as ZoneData
		if StringName(source_effect.get("op", "")) != operation \
				or str(card_instance_id) not in (source_effect.get("source_deck_zone_ids", []) as Array) \
				or StringName(source_effect.get("choice_zone_id", "")) != HelperService.DRAFT_ROW_ID \
				or source_deck == null or source_deck.kind != &"ordered_deck" \
				or source_deck.visibility != &"hidden" \
				or draft_zone == null or not draft_zone.card_instance_ids.is_empty() \
				or ZoneService.find_card_zone(state, StringName(choice.get("source_card_instance_id", ""))) \
				!= StringName(choice.get("source_card_zone_id", "")):
			return "invalid_helper_draft_source"
		return ""
	var card := state.cards.get(card_instance_id) as Dictionary
	if card == null:
		return "missing_choice_card"
	match operation:
		&"choose_transfer_card":
			var player := state.players.get(actor_id) as PlayerStateData
			var next_index := (state.turn_order.find(actor_id) + 1) % state.turn_order.size()
			var recipient_id := state.turn_order[next_index]
			var recipient := state.players.get(recipient_id) as PlayerStateData
			if player == null or recipient == null \
					or ZoneService.find_card_zone(state, card_instance_id) != StringName(player.zone_ids.get(&"hand", &"")) \
					or StringName(choice.get("source_zone_id", "")) != StringName(player.zone_ids.get(&"hand", &"")) \
					or StringName(choice.get("destination_zone_id", "")) != StringName(recipient.zone_ids.get(&"hand", &"")) \
					or StringName(choice.get("recipient_id", "")) != recipient_id:
				return "invalid_transfer_source"
			if StringName(card.get("owner_id", "")) != actor_id:
				return "choice_card_not_owned"
		&"choose_equipment_replacement":
			var player := state.players.get(actor_id) as PlayerStateData
			var target_id := StringName(choice.get("target_card_id", ""))
			var pending_id := StringName(choice.get("pending_equipment_id", ""))
			if player == null or ZoneService.find_card_zone(state, card_instance_id) \
					!= StringName(player.zone_ids.get(&"equipment", &"")):
				return "choice_card_moved"
			if ZoneService.find_card_zone(state, target_id) != StringName(player.zone_ids.get(&"party", &"")) \
					or ZoneService.find_card_zone(state, pending_id) \
					!= StringName(choice.get("pending_equipment_source_zone_id", "")):
				return "choice_source_moved"
			var target := state.cards.get(target_id) as Dictionary
			if target == null or str(card_instance_id) not in ((target.get("state", {}) as Dictionary).get("equipment_ids", []) as Array):
				return "attachment_link_missing"
		&"inspect_deck_top", &"order_deck_top":
			var player := state.players.get(actor_id) as PlayerStateData
			if player == null or StringName(choice.get("source_zone_id", "")) \
					!= StringName(player.zone_ids.get(&"inspection", &"")) \
					or ZoneService.find_card_zone(state, card_instance_id) \
					!= StringName(player.zone_ids.get(&"inspection", &"")):
				return "choice_card_moved"
			if StringName(card.get("owner_id", "")) != actor_id:
				return "choice_card_not_owned"
		&"confirm_effect":
			if ZoneService.find_card_zone(state, card_instance_id) \
					!= StringName(choice.get("source_zone_id", "")):
				return "choice_card_moved"
			if str(card_instance_id) != str(choice.get("source_card_instance_id", "")):
				return "ineligible_choice_card"
			var source_card := state.cards.get(card_instance_id) as Dictionary
			if source_card == null or StringName(source_card.get("owner_id", "")) != actor_id:
				return "choice_card_not_owned"
		&"choose_move_card":
			var source_zone_key := StringName(choice.get("source_zone_key", ""))
			var destination_zone_id := StringName(choice.get("destination_zone_id", ""))
			var player := state.players.get(actor_id) as PlayerStateData
			if player == null or StringName(player.zone_ids.get(source_zone_key, &"")) \
					!= StringName(choice.get("source_zone_id", "")) \
					or destination_zone_id not in player.zone_ids.values():
				return "invalid_choice_source"
			if ZoneService.find_card_zone(state, card_instance_id) \
					!= StringName(choice.get("source_zone_id", "")):
				return "choice_card_moved"
			if StringName(card.get("owner_id", "")) != actor_id:
				return "choice_card_not_owned"
			var allowed_tags := _normalized_allowed_tags(choice.get("allowed_tags", []))
			var allowed_types := _normalized_allowed_tags(choice.get("allowed_card_types", []))
			var definition := _definition_for_card(state, definitions, card_instance_id)
			if not allowed_tags.is_empty() and (definition == null \
					or not _definition_has_any_tag(definition, allowed_tags)):
				return "choice_card_wrong_type"
			if not allowed_types.is_empty() and (definition == null \
					or definition.card_type not in allowed_types):
				return "choice_card_wrong_type"
			if bool(choice.get("exclude_source_definition", false)):
				var source_definition := _definition_for_card(
					state, definitions, StringName(choice.get("source_card_instance_id", ""))
				)
				if definition != null and source_definition != null \
						and definition.definition_id == source_definition.definition_id:
					return "choice_card_wrong_type"
		&"choose_target_combat_modifier":
			if ZoneService.find_card_zone(state, card_instance_id) \
					!= StringName(choice.get("source_zone_id", "")):
				return "choice_card_moved"
			if not StringName(card.get("owner_id", "")).is_empty():
				return "choice_card_already_owned"
			var definition := _definition_for_card(state, definitions, card_instance_id)
			if definition == null or definition.card_type not in _normalized_allowed_tags(
					choice.get("allowed_card_types", [])
			):
				return "choice_card_wrong_type"
		&"choose_refresh_row":
			if ZoneService.find_card_zone(state, card_instance_id) \
					!= StringName(choice.get("source_zone_id", "")):
				return "choice_card_moved"
			if not StringName(card.get("owner_id", "")).is_empty():
				return "choice_card_already_owned"
		&"choose_remove_card":
			var source_record := (choice.get("eligible_card_sources", {}) as Dictionary).get(
				str(card_instance_id), {}
			) as Dictionary
			var source_zone_key := StringName(source_record.get("zone_key", ""))
			var source_zone_id := StringName(source_record.get("zone_id", ""))
			var player := state.players.get(actor_id) as PlayerStateData
			if player == null or source_zone_key not in [&"hand", &"party", &"discard_pile"]:
				return "invalid_choice_source"
			if source_zone_id != StringName(player.zone_ids.get(source_zone_key, &"")):
				return "choice_source_not_owned"
			if ZoneService.find_card_zone(state, card_instance_id) != source_zone_id:
				return "choice_card_moved"
			if StringName(card.get("owner_id", "")) != actor_id:
				return "choice_card_not_owned"
		&"choose_gain_card":
			var source_effect := choice.get("source_effect", {}) as Dictionary
			if StringName(source_effect.get("op", "")) != &"choose_gain_card" \
					or StringName(source_effect.get("source_zone_id", "")) != StringName(choice.get("source_zone_id", "")) \
					or int(source_effect.get("max_cost", -1)) != int(choice.get("max_cost", -1)) \
					or source_effect.get("allowed_card_types", []) != choice.get("allowed_card_types", []) \
					or source_effect.get("allowed_tags", []) != choice.get("allowed_tags", []):
				return "invalid_choice_source"
			if ZoneService.find_card_zone(state, card_instance_id) \
					!= StringName(choice.get("source_zone_id", "")):
				return "choice_card_moved"
			if not StringName(card.get("owner_id", "")).is_empty():
				return "choice_card_already_owned"
			var definition := _definition_for_card(state, definitions, card_instance_id)
			if definition == null or definition.cost == null:
				return "choice_card_missing_definition"
			var allowed_card_types := _normalized_allowed_tags(
				choice.get("allowed_card_types", [])
			)
			if allowed_card_types.is_empty() or definition.card_type not in allowed_card_types:
				return "choice_card_wrong_type"
			var allowed_tags := _normalized_allowed_tags(choice.get("allowed_tags", []))
			if allowed_tags.is_empty() or not _definition_has_any_tag(definition, allowed_tags):
				return "choice_card_wrong_type"
			if int(definition.cost) > int(choice.get("max_cost", -1)):
				return "choice_card_cost_exceeded"
		&"pay_post_departure_cost":
			var source_zone_id := StringName(choice.get("source_zone_id", ""))
			var destination_zone_id := StringName(choice.get("destination_zone_id", ""))
			var source_zone_key := StringName(choice.get("source_zone_key", ""))
			var source_rule := choice.get("source_rule", {}) as Dictionary
			var player := state.players.get(actor_id) as PlayerStateData
			if player == null or source_zone_id != StringName(player.zone_ids.get(source_zone_key, &"")) \
					or destination_zone_id != StringName(player.zone_ids.get(
						StringName(source_rule.get("destination_zone_key", "")), &""
					)) or StringName(source_rule.get("op", "")) != &"post_departure_cost" \
					or StringName(source_rule.get("source_zone_key", "")) != source_zone_key \
					or StringName(source_rule.get("card_type", "")) \
					!= StringName(choice.get("required_card_type", "")):
				return "invalid_choice_source"
			if ZoneService.find_card_zone(state, card_instance_id) != source_zone_id:
				return "choice_card_moved"
			if StringName(card.get("owner_id", "")) != actor_id:
				return "choice_card_not_owned"
			var definition := _definition_for_card(state, definitions, card_instance_id)
			if definition == null or definition.card_type != StringName(choice.get("required_card_type", "")):
				return "choice_card_wrong_type"
		&"draft_gain_card":
			if not str(card_instance_id) in (choice.get("remaining_card_ids", []) as Array):
				return "ineligible_choice_card"
			var source_effect := choice.get("source_effect", {}) as Dictionary
			if StringName(source_effect.get("op", "")) != &"draft_gain_card" \
					or StringName(source_effect.get("source_deck_zone_id", "")) \
					!= StringName(choice.get("source_deck_zone_id", "")) \
					or StringName(source_effect.get("choice_zone_id", "")) \
					!= StringName(choice.get("choice_zone_id", "")) \
					or StringName(source_effect.get("destination_zone_key", "")) \
					!= StringName(choice.get("destination_zone_key", "")):
				return "invalid_choice_source"
			var source_deck := state.zones.get(
				StringName(choice.get("source_deck_zone_id", ""))
			) as ZoneData
			var choice_zone := state.zones.get(
				StringName(choice.get("choice_zone_id", ""))
			) as ZoneData
			if source_deck == null or source_deck.kind != &"ordered_deck" \
					or source_deck.visibility != &"hidden" or choice_zone == null \
					or choice_zone.kind != &"face_up_row" or choice_zone.visibility != &"public" \
					or not bool(choice_zone.metadata.get("temporary_choice_zone", false)) \
					or StringName(choice.get("source_zone_id", "")) != choice_zone.zone_id:
				return "invalid_choice_source"
			if ZoneService.find_card_zone(state, card_instance_id) \
					!= StringName(choice.get("choice_zone_id", "")):
				return "choice_card_moved"
			if not StringName(card.get("owner_id", "")).is_empty():
				return "choice_card_already_owned"
			if StringName(choice.get("destination_zone_key", "")) != &"hand":
				return "invalid_choice_destination"
			var destination_player := state.players.get(actor_id) as PlayerStateData
			if destination_player == null \
					or not state.zones.has(destination_player.zone_ids.get(&"hand", &"")):
				return "invalid_choice_destination"
			var selection_order := choice.get("selection_order", []) as Array
			var selection_index := int(choice.get("selection_index", -1))
			if selection_index < 0 or selection_index >= selection_order.size() \
					or StringName(str(selection_order[selection_index])) != actor_id:
				return "wrong_choice_actor"
		_:
			return "unsupported_choice_operation"
	return ""


static func _validate_boss_completion_payload(
	state: GameStateData,
	actor_id: StringName,
	choice: Dictionary,
	definitions: Dictionary
) -> String:
	if not choice.has("boss_completion"):
		return ""
	if not choice.get("boss_completion", {}) is Dictionary:
		return "invalid_boss_completion"
	var completion := choice.get("boss_completion", {}) as Dictionary
	if StringName(completion.get("actor_id", "")) != actor_id:
		return "invalid_boss_completion_actor"
	var target_card_id := StringName(completion.get("target_card_id", ""))
	if ZoneService.find_card_zone(state, target_card_id) != BossService.BOSS_ACTIVE_ID:
		return "boss_completion_target_moved"
	var target_card := state.cards.get(target_card_id) as Dictionary
	var target_definition := definitions.get(
		StringName(target_card.get("definition_id", "")) if target_card != null else &""
	) as CardDefinition
	if target_definition == null or target_definition.card_type != &"boss":
		return "invalid_boss_completion_target"
	var expected_remaining: Array[Dictionary] = []
	if StringName(choice.get("op", "")) == &"pay_post_departure_cost":
		for effect: Dictionary in target_definition.effects:
			if StringName(effect.get("timing", "")) != &"on_defeat" \
					or (bool(effect.get("optional", false)) \
					and not bool(completion.get("claim_optional_reward", true))):
				continue
			var expected_effect := effect.duplicate(true)
			expected_effect["source_card_instance_id"] = str(target_card_id)
			expected_effect["participant_count"] = (
				completion.get("participant_ids", []) as Array
			).size()
			expected_remaining.append(expected_effect)
	if completion.get("remaining_effects", []) != expected_remaining:
		return "invalid_boss_completion_effects"
	return ""


static func apply(
	state: GameStateData,
	actor_id: StringName,
	command: Dictionary,
	events: Array[Dictionary],
	definitions: Dictionary = {}
) -> String:
	var validation_error := validate(state, actor_id, command, definitions)
	if not validation_error.is_empty():
		return validation_error
	var choice := state.effect_state.duplicate(true)
	var skip := bool(command.get("skip", false))
	var card_instance_id := StringName(command.get("card_instance_id", ""))
	var operation := StringName(choice.get("op", ""))
	if operation in [&"select_bonds", &"complete_bonds"]:
		return BondService.apply_choice(state, actor_id, command, events, definitions)
	if operation == &"draft_gain_card":
		return _apply_draft_gain(state, actor_id, choice, card_instance_id, events, definitions)
	if operation == &"choose_supply_deck_draft":
		state.effect_state.clear()
		events.append({"type":"choice_resolved","actor_id":str(actor_id),"op":str(operation),"source_deck_zone_id":str(card_instance_id),"source_card_instance_id":str(choice.get("source_card_instance_id", ""))})
		var draft_effect: Dictionary = {
			"op":"draft_gain_card", "source_deck_zone_id":str(card_instance_id),
			"choice_zone_id":str(HelperService.DRAFT_ROW_ID), "cards_per_player":1,
			"destination_zone_key":"hand", "choice_title":str(choice.get("choice_title", "多人輪抽")),
			"prompt":str((choice.get("source_effect", {}) as Dictionary).get("draft_prompt", "從公開區選擇卡牌")),
			"source_card_instance_id":str(choice.get("source_card_instance_id", "")),
			"source_card_zone_id":str(choice.get("source_card_zone_id", "")),
		}
		var sequence: Array[Dictionary] = [draft_effect]
		for raw_effect: Variant in choice.get("continuation_effects", []):
			if raw_effect is Dictionary:
				sequence.append((raw_effect as Dictionary).duplicate(true))
		var draft_error := EffectResolver.resolve(state, actor_id, sequence, events, definitions)
		if not draft_error.is_empty():
			return draft_error
		return _resume_helper_boundary(state, choice, actor_id, events, definitions)
	var resolved_source_record: Dictionary = {}
	if not skip:
		if operation == &"choose_remove_card":
			var source_record := (choice.get("eligible_card_sources", {}) as Dictionary)[
				str(card_instance_id)
			] as Dictionary
			resolved_source_record = source_record
			var source_zone_key := StringName(source_record.get("zone_key", ""))
			if source_zone_key == &"party":
				var player := state.players[actor_id] as PlayerStateData
				var departure_error := PartyService.remove_party_member_with_equipment(
					state, player, card_instance_id, &"card_removed", events
				)
				if not departure_error.is_empty():
					return departure_error
			else:
				var move_result := ZoneService.move_card(
					state,
					card_instance_id,
					StringName(source_record.get("zone_id", "")),
					StringName(choice.get("destination_zone_id", ""))
				)
				if not bool(move_result.get("ok", false)):
					return str(move_result.get("error", "choice_move_failed"))
				var move_event := (move_result.get("event", {}) as Dictionary).duplicate(true)
				move_event["reason"] = "card_removed"
				events.append(move_event)
			var selected_card_ids := choice.get("selected_card_ids", []) as Array
			selected_card_ids.append(str(card_instance_id))
			choice["selected_card_ids"] = selected_card_ids
			choice["selected_count"] = selected_card_ids.size()
		elif operation in [&"confirm_effect", &"choose_target_combat_modifier", \
				&"choose_refresh_row", &"order_deck_top", &"choose_equipment_replacement"]:
			var selected_card_ids := choice.get("selected_card_ids", []) as Array
			selected_card_ids.append(str(card_instance_id))
			choice["selected_card_ids"] = selected_card_ids
			choice["selected_count"] = selected_card_ids.size()
		else:
			var move_result := ZoneService.move_card(
				state,
				card_instance_id,
				StringName(choice.get("source_zone_id", "")),
				StringName(choice.get("destination_zone_id", ""))
			)
			if not bool(move_result.get("ok", false)):
				return str(move_result.get("error", "choice_move_failed"))
			var move_event := (move_result.get("event", {}) as Dictionary).duplicate(true)
			move_event["reason"] = (
				"card_discarded_as_cost"
				if operation == &"choose_move_card" \
						and bool((choice.get("source_effect", {}) as Dictionary).get("is_cost", false))
				else ("card_moved_by_effect" if operation == &"choose_move_card" else "reward_card_gained")
			)
			events.append(move_event)
			var card := state.cards[card_instance_id] as Dictionary
			if operation == &"choose_gain_card":
				card["owner_id"] = str(ZoneService.actual_owner_after_move(
					state, move_result, actor_id
				))
			if operation in [&"choose_gain_card", &"choose_move_card"]:
				var destinations := choice.get("selected_destination_zone_ids", {}) as Dictionary
				destinations[str(card_instance_id)] = str(move_event.get("to_zone_id", ""))
				choice["selected_destination_zone_ids"] = destinations
			if operation == &"choose_transfer_card":
				card["owner_id"] = str(choice.get("recipient_id", ""))
				events.append({
					"type":"card_transferred", "actor_id":str(actor_id),
					"from_player_id":str(actor_id),
					"to_player_id":str(choice.get("recipient_id", "")),
					"card_instance_id":str(card_instance_id),
					"source_card_instance_id":str(choice.get("source_card_instance_id", "")),
				})
			var selected_card_ids := choice.get("selected_card_ids", []) as Array
			selected_card_ids.append(str(card_instance_id))
			choice["selected_card_ids"] = selected_card_ids
			choice["selected_count"] = selected_card_ids.size()
	var selected_count := int(choice.get("selected_count", 0))
	var choice_complete := skip or selected_count >= int(choice.get("max_selections", 1))
	if not choice_complete:
		state.effect_state = choice
		events.append({
			"type": "choice_progressed",
			"choice_id": str(choice.get("choice_id", "")),
			"actor_id": str(actor_id),
			"op": str(choice.get("op", "")),
			"card_instance_id": str(card_instance_id),
			"selected_card_ids": (choice.get("selected_card_ids", []) as Array).duplicate(),
			"selected_count": selected_count,
			"max_selections": int(choice.get("max_selections", 1)),
		})
		return ""
	if operation == &"choose_target_combat_modifier" and not skip:
		var target_modifiers := (state.players[actor_id] as PlayerStateData).turn_bonuses.get(
			"target_combat_modifiers", {}
		) as Dictionary
		target_modifiers[str(card_instance_id)] = int(
			target_modifiers.get(str(card_instance_id), 0)
		) + int(choice.get("modifier_amount", 0))
		(state.players[actor_id] as PlayerStateData).turn_bonuses["target_combat_modifiers"] = target_modifiers
		events.append({
			"type": "target_combat_modified", "actor_id": str(actor_id),
			"card_instance_id": str(card_instance_id),
			"amount": int(choice.get("modifier_amount", 0)),
			"source_card_instance_id": str(choice.get("source_card_instance_id", "")),
		})
	if operation == &"choose_refresh_row":
		var refresh_error := _apply_row_refresh(state, actor_id, choice, events)
		if not refresh_error.is_empty():
			return refresh_error
	if operation == &"choose_equipment_replacement":
		var player := state.players[actor_id] as PlayerStateData
		var detach_error := PartyService.detach_equipment(
			state, player, StringName(choice.get("target_card_id", "")), card_instance_id,
			StringName(choice.get("destination_zone_id", "")), &"equipment_replaced", events
		)
		if not detach_error.is_empty():
			return detach_error
	if operation == &"order_deck_top":
		var order_error := _restore_inspected_order(state, actor_id, choice, events)
		if not order_error.is_empty():
			return order_error
	state.effect_state.clear()
	events.append({
		"type": "choice_resolved",
		"choice_id": str(choice.get("choice_id", "")),
		"actor_id": str(actor_id),
		"op": str(choice.get("op", "")),
		"card_instance_id": str(card_instance_id),
		"skipped": skip and selected_count == 0,
		"completed_early": skip and selected_count > 0,
		"selected_card_ids": (choice.get("selected_card_ids", []) as Array).duplicate(),
		"selected_count": selected_count,
		"source_card_instance_id": str(choice.get("source_card_instance_id", "")),
		"source_zone_id": str(resolved_source_record.get(
			"zone_id", choice.get("source_zone_id", "")
		)),
		"source_zone_key": str(resolved_source_record.get(
			"zone_key", choice.get("source_zone_key", "")
		)),
		"source_zone_ids": (choice.get("source_zone_ids", {}) as Dictionary).duplicate(true),
		"source_zone_keys": (choice.get("source_zone_keys", []) as Array).duplicate(),
		"destination_zone_id": str(choice.get("destination_zone_id", "")),
	})
	if operation == &"choose_equipment_replacement":
		return EquipmentService.apply(state, actor_id, {
			"type": "EQUIP_ITEM",
			"card_instance_id": str(choice.get("pending_equipment_id", "")),
			"target_card_id": str(choice.get("target_card_id", "")),
		}, definitions, events)
	events.append({
		"type": "effect_resolved",
		"actor_id": str(actor_id),
		"effect_index": int(choice.get("effect_index", 0)),
		"op": str(choice.get("op", "")),
		"selected_count": (
			selected_count
			if StringName(choice.get("op", "")) in [&"choose_remove_card", &"choose_gain_card"]
			else (0 if skip else 1)
		),
	})
	if operation == &"choose_remove_card" \
			and StringName(resolved_source_record.get("zone_key", "")) == &"party":
		var position_error := PartyService.enforce_position_departures(
			state, state.players[actor_id] as PlayerStateData, definitions, events
		)
		if not position_error.is_empty():
			return position_error
	if operation == &"inspect_deck_top":
		var ordering_error := _start_inspection_order(state, actor_id, choice, events)
		if not ordering_error.is_empty():
			return ordering_error
		if not state.effect_state.is_empty():
			return ""
	var continuation: Array[Dictionary] = []
	if operation == &"confirm_effect" and not skip:
		var accepted := choice.get("accepted_effect", {}) as Dictionary
		if not accepted.is_empty():
			continuation.append(accepted)
	for raw_effect: Variant in choice.get("continuation_effects", []):
		if raw_effect is Dictionary:
			var continued_effect := (raw_effect as Dictionary).duplicate(true)
			continued_effect["_selection_count"] = selected_count
			if not (choice.get("selected_card_ids", []) as Array).is_empty():
				continued_effect["_selected_card_instance_id"] = str(
					(choice.get("selected_card_ids", []) as Array).back()
				)
			continuation.append(continued_effect)
	if not continuation.is_empty():
		var continuation_error := EffectResolver.resolve(
			state, actor_id, continuation, events, definitions
		)
		if not continuation_error.is_empty():
			return continuation_error
		if not state.effect_state.is_empty() and choice.has("boss_completion"):
			state.effect_state["boss_completion"] = choice["boss_completion"]
			return ""
	var boundary_error := _resume_helper_boundary(state, choice, StringName(choice.get("actor_id", actor_id)), events, definitions)
	if not boundary_error.is_empty() or not state.effect_state.is_empty():
		return boundary_error
	var boss_completion := choice.get("boss_completion", {}) as Dictionary
	if not boss_completion.is_empty():
		return BossService.continue_defeat_after_choice(
			state, actor_id, boss_completion, events, definitions
		)
	return ""


static func _start_inspection_order(
	state: GameStateData,
	actor_id: StringName,
	choice: Dictionary,
	events: Array[Dictionary]
) -> String:
	var player := state.players.get(actor_id) as PlayerStateData
	var inspection := state.zones.get(player.zone_ids.get(&"inspection", &"")) as ZoneData if player != null else null
	var deck := state.zones.get(StringName(choice.get("draw_pile_zone_id", ""))) as ZoneData
	if inspection == null or deck == null:
		return "missing_inspection_zone"
	if inspection.card_instance_ids.size() <= 1:
		if inspection.card_instance_ids.size() == 1:
			var card_id := inspection.card_instance_ids[0]
			var move_result := ZoneService.move_card(
				state, card_id, inspection.zone_id, deck.zone_id
			)
			if not bool(move_result.get("ok", false)):
				return str(move_result.get("error", "inspection_restore_failed"))
		return ""
	var eligible: Array[String] = []
	for card_id: StringName in inspection.card_instance_ids:
		eligible.append(str(card_id))
	state.effect_state = {
		"type": "pending_choice", "choice_id": "choice-%06d-order" % (state.revision + 1),
		"actor_id": str(actor_id), "required_actor_id": str(actor_id),
		"op": "order_deck_top", "prompt": "依序選擇牌庫頂順序（先選最上方）",
		"source_zone_id": str(inspection.zone_id), "source_zone_key": "inspection",
		"destination_zone_id": str(deck.zone_id), "eligible_card_ids": eligible,
		"selected_card_ids": [], "selected_count": 0,
		"min_selections": eligible.size(), "max_selections": eligible.size(),
		"source_card_instance_id": str(choice.get("source_card_instance_id", "")),
		"continuation_effects": (choice.get("continuation_effects", []) as Array).duplicate(true),
	}
	events.append({
		"type": "choice_requested", "choice_id": str(state.effect_state["choice_id"]),
		"actor_id": str(actor_id), "required_actor_id": str(actor_id),
		"op": "order_deck_top", "eligible_card_ids": eligible.duplicate(), "optional": false,
	})
	return ""


static func _restore_inspected_order(
	state: GameStateData,
	actor_id: StringName,
	choice: Dictionary,
	events: Array[Dictionary]
) -> String:
	var selected := choice.get("selected_card_ids", []) as Array
	for index in range(selected.size() - 1, -1, -1):
		var card_id := StringName(str(selected[index]))
		var move_result := ZoneService.move_card(
			state, card_id, StringName(choice.get("source_zone_id", "")),
			StringName(choice.get("destination_zone_id", ""))
		)
		if not bool(move_result.get("ok", false)):
			return str(move_result.get("error", "inspection_restore_failed"))
	events.append({
		"type": "deck_top_reordered", "actor_id": str(actor_id),
		"card_instance_ids": selected.duplicate(),
		"source_card_instance_id": str(choice.get("source_card_instance_id", "")),
	})
	return ""


static func _apply_row_refresh(
	state: GameStateData,
	actor_id: StringName,
	choice: Dictionary,
	events: Array[Dictionary]
) -> String:
	var source_zone_id := StringName(choice.get("source_zone_id", ""))
	var destination_zone_id := StringName(choice.get("destination_zone_id", ""))
	var selected := choice.get("selected_card_ids", []) as Array
	var original_order := choice.get("original_order", []) as Array
	for raw_card_id: Variant in original_order:
		if str(raw_card_id) not in selected:
			continue
		var card_id := StringName(str(raw_card_id))
		var move_result := ZoneService.move_card(
			state, card_id, source_zone_id, destination_zone_id, 0
		)
		if not bool(move_result.get("ok", false)):
			return str(move_result.get("error", "row_refresh_failed"))
		var move_event := (move_result.get("event", {}) as Dictionary).duplicate(true)
		move_event["reason"] = "public_row_refreshed"
		move_event["actor_id"] = str(actor_id)
		events.append(move_event)
	return SupplyService.refill_row(
		state, SupplyService.MONSTER_CYCLE_ID, source_zone_id,
		SupplyService.MONSTER_ROW_SIZE, events, false
	)


static func _apply_draft_gain(
	state: GameStateData,
	actor_id: StringName,
	choice: Dictionary,
	card_instance_id: StringName,
	events: Array[Dictionary],
	definitions: Dictionary
) -> String:
	var player := state.players.get(actor_id) as PlayerStateData
	if player == null:
		return "missing_player"
	var destination_zone_id := StringName(player.zone_ids.get(&"hand", &""))
	var move_result := ZoneService.move_card(
		state,
		card_instance_id,
		StringName(choice.get("choice_zone_id", "")),
		destination_zone_id
	)
	if not bool(move_result.get("ok", false)):
		return str(move_result.get("error", "choice_move_failed"))
	var card := state.cards[card_instance_id] as Dictionary
	card["owner_id"] = str(actor_id)
	var move_event := (move_result.get("event", {}) as Dictionary).duplicate(true)
	move_event["reason"] = (
		"helper_draft_gained"
		if StringName(choice.get("choice_zone_id", "")) == HelperService.DRAFT_ROW_ID
		else "resource_draft_gained"
	)
	move_event["actor_id"] = str(actor_id)
	events.append(move_event)
	var remaining_card_ids := choice.get("remaining_card_ids", []) as Array
	remaining_card_ids.erase(str(card_instance_id))
	choice["remaining_card_ids"] = remaining_card_ids
	var selected_card_ids := choice.get("selected_card_ids", []) as Array
	selected_card_ids.append(str(card_instance_id))
	choice["selected_card_ids"] = selected_card_ids
	choice["selected_count"] = selected_card_ids.size()
	var completed_selections := choice.get("completed_selections", []) as Array
	completed_selections.append({
		"actor_id": str(actor_id),
		"card_instance_id": str(card_instance_id),
		"destination_zone_id": str(destination_zone_id),
	})
	choice["completed_selections"] = completed_selections
	var selection_index := int(choice.get("selection_index", 0)) + 1
	if remaining_card_ids.is_empty():
		state.effect_state.clear()
		events.append({
			"type": "choice_resolved",
			"choice_id": str(choice.get("choice_id", "")),
			"actor_id": str(actor_id),
			"defeated_by_actor_id": str(choice.get("defeated_by_actor_id", "")),
			"op": str(choice.get("op", "")),
			"card_instance_id": str(card_instance_id),
			"selected_card_ids": selected_card_ids.duplicate(),
			"selected_count": selected_card_ids.size(),
			"completed_selections": completed_selections.duplicate(true),
			"source_card_instance_id": str(choice.get("source_card_instance_id", "")),
			"source_zone_id": str(choice.get("choice_zone_id", "")),
			"destination_zone_id": str(destination_zone_id),
		})
		events.append({
			"type": "effect_resolved",
			"actor_id": str(choice.get("defeated_by_actor_id", "")),
			"effect_index": int(choice.get("effect_index", 0)),
			"op": str(choice.get("op", "")),
			"selected_count": selected_card_ids.size(),
		})
		var continuation: Array[Dictionary] = []
		for raw_effect: Variant in choice.get("continuation_effects", []):
			if raw_effect is Dictionary:
				continuation.append((raw_effect as Dictionary).duplicate(true))
		var continuation_error := EffectResolver.resolve(state, StringName(choice.get("defeated_by_actor_id", "")), continuation, events, definitions) \
				if not continuation.is_empty() else ""
		if not continuation_error.is_empty():
			return continuation_error
		return _resume_helper_boundary(state, choice, StringName(choice.get("defeated_by_actor_id", "")), events, definitions)
	var selection_order := choice.get("selection_order", []) as Array
	if selection_index >= selection_order.size():
		return "draft_selection_order_exhausted"
	choice["selection_index"] = selection_index
	choice["required_actor_id"] = str(selection_order[selection_index])
	state.effect_state = choice
	events.append({
		"type": "choice_progressed",
		"choice_id": str(choice.get("choice_id", "")),
		"actor_id": str(actor_id),
		"required_actor_id": str(choice.get("required_actor_id", "")),
		"op": str(choice.get("op", "")),
		"card_instance_id": str(card_instance_id),
		"remaining_card_ids": remaining_card_ids.duplicate(),
		"remaining_count": remaining_card_ids.size(),
		"completed_selections": completed_selections.duplicate(true),
	})
	return ""


static func _resume_helper_boundary(
	state: GameStateData, choice: Dictionary, actor_id: StringName,
	events: Array[Dictionary], definitions: Dictionary
) -> String:
	if not state.effect_state.is_empty():
		for marker in ["helper_reveal_after_choice", "helper_rest_boundary", "helper_purchase_boundary"]:
			if bool(choice.get(marker, false)):
				state.effect_state[marker] = true
		return ""
	if bool(choice.get("helper_reveal_after_choice", false)):
		return HelperService.reveal_after_choice(state, actor_id, events, definitions)
	if bool(choice.get("helper_rest_boundary", false)):
		return RulesEngine.finish_rest_phase(state, events, definitions)
	if bool(choice.get("helper_purchase_boundary", false)):
		return HelperService.trigger(state, actor_id, &"on_purchase_start", events, definitions)
	return ""


static func _required_actor_id(choice: Dictionary) -> StringName:
	return StringName(choice.get("required_actor_id", choice.get("actor_id", "")))


static func _definition_for_card(
	state: GameStateData,
	definitions: Dictionary,
	card_instance_id: StringName
) -> CardDefinition:
	var raw_card: Variant = state.cards.get(card_instance_id)
	if not raw_card is Dictionary:
		return null
	var card := raw_card as Dictionary
	return definitions.get(StringName(card.get("definition_id", ""))) as CardDefinition


static func _normalized_allowed_tags(raw_tags: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if not raw_tags is Array:
		return result
	for raw_tag: Variant in raw_tags:
		var tag := StringName(str(raw_tag))
		if not tag.is_empty() and tag not in result:
			result.append(tag)
	return result


static func _definition_has_any_tag(
	definition: CardDefinition,
	allowed_tags: Array[StringName]
) -> bool:
	for tag: StringName in allowed_tags:
		if tag in definition.tags:
			return true
	return false
