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
	if _required_actor_id(choice) != actor_id:
		return "wrong_choice_actor"
	if str(command.get("choice_id", "")) != str(choice.get("choice_id", "")):
		return "wrong_choice_id"
	if not command.get("skip", false) is bool:
		return "invalid_choice_skip"
	var skip := bool(command.get("skip", false))
	var card_instance_id := StringName(command.get("card_instance_id", ""))
	var operation := StringName(choice.get("op", ""))
	var selected_card_ids := choice.get("selected_card_ids", []) as Array
	var selected_count := int(choice.get("selected_count", selected_card_ids.size()))
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
	var card := state.cards.get(card_instance_id) as Dictionary
	if card == null:
		return "missing_choice_card"
	match operation:
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
	if operation == &"draft_gain_card":
		return _apply_draft_gain(state, actor_id, choice, card_instance_id, events)
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
			move_event["reason"] = "reward_card_gained"
			events.append(move_event)
			var card := state.cards[card_instance_id] as Dictionary
			card["owner_id"] = str(actor_id)
	var selected_count := int(choice.get("selected_count", 0))
	var choice_complete := skip or operation == &"choose_gain_card" \
			or selected_count >= int(choice.get("max_selections", 1))
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
	events.append({
		"type": "effect_resolved",
		"actor_id": str(actor_id),
		"effect_index": int(choice.get("effect_index", 0)),
		"op": str(choice.get("op", "")),
		"selected_count": selected_count if StringName(choice.get("op", "")) == &"choose_remove_card" else (0 if skip else 1),
	})
	return ""


static func _apply_draft_gain(
	state: GameStateData,
	actor_id: StringName,
	choice: Dictionary,
	card_instance_id: StringName,
	events: Array[Dictionary]
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
	move_event["reason"] = "resource_draft_gained"
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
		return ""
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


static func _required_actor_id(choice: Dictionary) -> StringName:
	return StringName(choice.get("required_actor_id", choice.get("actor_id", "")))


static func _definition_for_card(
	state: GameStateData,
	definitions: Dictionary,
	card_instance_id: StringName
) -> CardDefinition:
	var card := state.cards.get(card_instance_id) as Dictionary
	if card == null:
		return null
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
