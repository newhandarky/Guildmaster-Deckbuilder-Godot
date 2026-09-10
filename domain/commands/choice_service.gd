class_name ChoiceService
extends RefCounted


static func get_legal_commands(
	state: GameStateData,
	actor_id: StringName
) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	var choice := state.effect_state
	if StringName(choice.get("type", "")) != &"pending_choice" \
			or StringName(choice.get("actor_id", "")) != actor_id:
		return commands
	for raw_card_id: Variant in choice.get("eligible_card_ids", []):
		commands.append({
			"type": "RESOLVE_CHOICE",
			"actor_id": str(actor_id),
			"expected_revision": state.revision,
			"choice_id": str(choice.get("choice_id", "")),
			"card_instance_id": str(raw_card_id),
			"skip": false,
		})
	if int(choice.get("min_selections", 1)) == 0:
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
	if StringName(choice.get("actor_id", "")) != actor_id:
		return "wrong_choice_actor"
	if str(command.get("choice_id", "")) != str(choice.get("choice_id", "")):
		return "wrong_choice_id"
	if not command.get("skip", false) is bool:
		return "invalid_choice_skip"
	var skip := bool(command.get("skip", false))
	var card_instance_id := StringName(command.get("card_instance_id", ""))
	if skip:
		if int(choice.get("min_selections", 1)) > 0:
			return "choice_required"
		if not card_instance_id.is_empty():
			return "invalid_skipped_choice"
		return ""
	if card_instance_id.is_empty():
		return "missing_choice_card"
	if not str(card_instance_id) in (choice.get("eligible_card_ids", []) as Array):
		return "ineligible_choice_card"
	if ZoneService.find_card_zone(state, card_instance_id) \
			!= StringName(choice.get("source_zone_id", "")):
		return "choice_card_moved"
	var card := state.cards.get(card_instance_id) as Dictionary
	if card == null:
		return "missing_choice_card"
	match StringName(choice.get("op", "")):
		&"choose_remove_card":
			if StringName(card.get("owner_id", "")) != actor_id:
				return "choice_card_not_owned"
		&"choose_gain_card":
			if not StringName(card.get("owner_id", "")).is_empty():
				return "choice_card_already_owned"
			var definition := _definition_for_card(state, definitions, card_instance_id)
			if definition == null or definition.cost == null:
				return "choice_card_missing_definition"
			var required_tag := StringName(choice.get("required_tag", ""))
			if not required_tag.is_empty() and required_tag not in definition.tags:
				return "choice_card_wrong_type"
			if int(definition.cost) > int(choice.get("max_cost", -1)):
				return "choice_card_cost_exceeded"
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
	if not skip:
		var move_result := ZoneService.move_card(
			state,
			card_instance_id,
			StringName(choice.get("source_zone_id", "")),
			StringName(choice.get("destination_zone_id", ""))
		)
		if not bool(move_result.get("ok", false)):
			return str(move_result.get("error", "choice_move_failed"))
		var move_event := (move_result.get("event", {}) as Dictionary).duplicate(true)
		var operation := StringName(choice.get("op", ""))
		move_event["reason"] = (
			"card_removed" if operation == &"choose_remove_card" else "reward_card_gained"
		)
		events.append(move_event)
		if operation == &"choose_gain_card":
			var card := state.cards[card_instance_id] as Dictionary
			card["owner_id"] = str(actor_id)
	state.effect_state.clear()
	events.append({
		"type": "choice_resolved",
		"choice_id": str(choice.get("choice_id", "")),
		"actor_id": str(actor_id),
		"op": str(choice.get("op", "")),
		"card_instance_id": str(card_instance_id),
		"skipped": skip,
		"source_card_instance_id": str(choice.get("source_card_instance_id", "")),
		"source_zone_id": str(choice.get("source_zone_id", "")),
		"source_zone_key": str(choice.get("source_zone_key", "")),
		"destination_zone_id": str(choice.get("destination_zone_id", "")),
	})
	events.append({
		"type": "effect_resolved",
		"actor_id": str(actor_id),
		"effect_index": int(choice.get("effect_index", 0)),
		"op": str(choice.get("op", "")),
		"selected_count": 0 if skip else 1,
	})
	return ""


static func _definition_for_card(
	state: GameStateData,
	definitions: Dictionary,
	card_instance_id: StringName
) -> CardDefinition:
	var card := state.cards.get(card_instance_id) as Dictionary
	if card == null:
		return null
	return definitions.get(StringName(card.get("definition_id", ""))) as CardDefinition
