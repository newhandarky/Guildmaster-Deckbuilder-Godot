class_name ItemService
extends RefCounted

const ACTION_PHASES: Array[StringName] = [&"action1", &"action2"]


static func get_legal_commands(
	state: GameStateData,
	actor_id: StringName,
	definitions: Dictionary
) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	if not state.phase in ACTION_PHASES:
		return commands
	var player := state.players.get(actor_id) as PlayerStateData
	if player == null:
		return commands
	var hand := state.zones.get(player.zone_ids.get(&"hand", &"")) as ZoneData
	if hand == null:
		return commands
	for card_instance_id: StringName in hand.card_instance_ids:
		var definition := _definition_for_card(state, definitions, card_instance_id)
		if definition != null and definition.card_type == &"item" \
				and _use_validation_error(state, actor_id, card_instance_id, definition, definitions).is_empty():
			commands.append({
				"type": "USE_ITEM",
				"actor_id": str(actor_id),
				"expected_revision": state.revision,
				"card_instance_id": str(card_instance_id),
			})
	return commands


static func validate(
	state: GameStateData,
	actor_id: StringName,
	command: Dictionary,
	definitions: Dictionary
) -> String:
	if not state.phase in ACTION_PHASES:
		return "wrong_phase"
	var player := state.players.get(actor_id) as PlayerStateData
	if player == null:
		return "missing_player"
	var card_instance_id := StringName(command.get("card_instance_id", ""))
	if not state.cards.has(card_instance_id):
		return "missing_card"
	var card := state.cards[card_instance_id] as Dictionary
	if StringName(card.get("owner_id", "")) != actor_id:
		return "card_not_owned"
	if ZoneService.find_card_zone(state, card_instance_id) != StringName(player.zone_ids[&"hand"]):
		return "card_not_in_hand"
	var definition := _definition_for_card(state, definitions, card_instance_id)
	if definition == null:
		return "missing_definition"
	if definition.card_type != &"item":
		return "unsupported_card_type"
	return _use_validation_error(state, actor_id, card_instance_id, definition, definitions)


static func apply(
	state: GameStateData,
	actor_id: StringName,
	command: Dictionary,
	definitions: Dictionary,
	events: Array[Dictionary]
) -> String:
	var validation_error := validate(state, actor_id, command, definitions)
	if not validation_error.is_empty():
		return validation_error
	var player := state.players[actor_id] as PlayerStateData
	var card_instance_id := StringName(command.get("card_instance_id", ""))
	var move_result := ZoneService.move_card(
		state,
		card_instance_id,
		StringName(player.zone_ids[&"hand"]),
		StringName(player.zone_ids[&"play_area"])
	)
	if not bool(move_result.get("ok", false)):
		return str(move_result.get("error", "item_move_failed"))
	var move_event: Dictionary = (move_result.get("event", {}) as Dictionary).duplicate(true)
	move_event["reason"] = "item_used"
	events.append(move_event)
	var definition := _definition_for_card(state, definitions, card_instance_id)
	var use_effects: Array[Dictionary] = []
	for effect: Dictionary in definition.effects:
		if StringName(effect.get("timing", "")) == &"on_use":
			use_effects.append(effect)
	var effect_error := EffectResolver.resolve(state, actor_id, use_effects, events, definitions)
	if not effect_error.is_empty():
		return effect_error
	var usage_key := "item_used:%s" % definition.definition_id
	for effect: Dictionary in use_effects:
		if bool(effect.get("once_per_turn", false)):
			player.turn_facts[usage_key] = true
	events.append({
		"type": "item_used",
		"actor_id": str(actor_id),
		"card_instance_id": str(card_instance_id),
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


static func _use_validation_error(
	state: GameStateData,
	actor_id: StringName,
	card_instance_id: StringName,
	definition: CardDefinition,
	definitions: Dictionary
) -> String:
	var use_effects: Array[Dictionary] = []
	for effect: Dictionary in definition.effects:
		if StringName(effect.get("timing", "")) == &"on_use":
			use_effects.append(effect)
	if use_effects.is_empty():
		return "item_has_no_use_effect"
	var player := state.players.get(actor_id) as PlayerStateData
	var hand := state.zones.get(player.zone_ids.get(&"hand", &"")) as ZoneData if player != null else null
	if player == null or hand == null:
		return "missing_player_card_zone"
	for effect: Dictionary in use_effects:
		if StringName(effect.get("condition", "")) == &"not_defeated_enemy" \
				and bool(player.turn_facts.get("defeated_enemy", false)):
			return "item_condition_not_met"
		if bool(effect.get("once_per_turn", false)) \
				and bool(player.turn_facts.get("item_used:%s" % definition.definition_id, false)):
			return "item_once_per_turn_used"
		if StringName(effect.get("op", "")) == &"discard_card_cost":
			var allowed_types: Array[StringName] = []
			var allowed_tags: Array[StringName] = []
			for raw_type: Variant in effect.get("allowed_card_types", []):
				allowed_types.append(StringName(str(raw_type)))
			for raw_tag: Variant in effect.get("allowed_tags", []):
				allowed_tags.append(StringName(str(raw_tag)))
			var candidates := 0
			for candidate_id: StringName in hand.card_instance_ids:
				if candidate_id == card_instance_id:
					continue
				var candidate := _definition_for_card(state, definitions, candidate_id)
				if candidate != null \
						and (allowed_types.is_empty() or candidate.card_type in allowed_types) \
						and (allowed_tags.is_empty() or _has_any_tag(candidate, allowed_tags)):
					candidates += 1
			if candidates < int(effect.get("amount", 1)):
				return "item_cost_unpayable"
	return ""


static func _has_any_tag(definition: CardDefinition, tags: Array[StringName]) -> bool:
	for tag: StringName in tags:
		if tag in definition.tags:
			return true
	return false
