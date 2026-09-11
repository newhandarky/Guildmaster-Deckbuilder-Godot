class_name PartyService
extends RefCounted

const ACTION_PHASES: Array[StringName] = [&"action1", &"action2"]
const BASE_PARTY_CAPACITY := 5


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
		if _is_adventurer(definition):
			commands.append({
				"type": "PLAY_ADVENTURER",
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
	if not _is_adventurer(definition):
		return "unsupported_card_type"
	return ""


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
	var party_zone_id := StringName(player.zone_ids[&"party"])
	var party := state.zones[party_zone_id] as ZoneData
	if party.card_instance_ids.size() >= BASE_PARTY_CAPACITY:
		var outgoing_id: StringName = party.card_instance_ids[0]
		var departure_error := discard_party_member_with_equipment(
			state, player, outgoing_id, &"party_capacity", events
		)
		if not departure_error.is_empty():
			return departure_error

	var card_instance_id := StringName(command.get("card_instance_id", ""))
	var move_result := ZoneService.move_card(
		state,
		card_instance_id,
		StringName(player.zone_ids[&"hand"]),
		party_zone_id
	)
	if not bool(move_result.get("ok", false)):
		return str(move_result.get("error", "party_entry_failed"))
	var move_event: Dictionary = (move_result.get("event", {}) as Dictionary).duplicate(true)
	move_event["reason"] = "adventurer_joined_party"
	events.append(move_event)
	events.append({
		"type": "adventurer_joined_party",
		"actor_id": str(actor_id),
		"card_instance_id": str(card_instance_id),
		"party_size": party.card_instance_ids.size(),
	})
	var card := state.cards[card_instance_id] as Dictionary
	var card_state := card.get("state", {}) as Dictionary
	card_state["entered_turn"] = "%s:%d" % [actor_id, state.round_number]
	card["state"] = card_state
	var trigger_error := EffectResolver.resolve_trigger_for_source(
		state, actor_id, card_instance_id, &"on_enter_party", events, definitions
	)
	if not trigger_error.is_empty():
		return trigger_error
	return enforce_position_departures(state, player, definitions, events)


static func enforce_position_departures(
	state: GameStateData,
	player: PlayerStateData,
	definitions: Dictionary,
	events: Array[Dictionary]
) -> String:
	var party := state.zones.get(player.zone_ids.get(&"party", &"")) as ZoneData
	if party == null:
		return "missing_player_card_zone"
	while not party.card_instance_ids.is_empty():
		var first_id := party.card_instance_ids[0]
		var definition := _definition_for_card(state, definitions, first_id)
		var must_depart := false
		if definition != null:
			for effect: Dictionary in definition.effects:
				if StringName(effect.get("op", "")) == &"position_departure" \
						and int(effect.get("party_index", effect.get("position", -1))) == 0:
					must_depart = true
					break
		if not must_depart:
			break
		var departure_error := discard_party_member_with_equipment(
			state, player, first_id, &"position_departure", events
		)
		if not departure_error.is_empty():
			return departure_error
		events.append({
			"type": "position_departure_resolved",
			"actor_id": str(player.player_id),
			"card_instance_id": str(first_id),
			"position": 0,
		})
	return ""


static func discard_party_member_with_equipment(
	state: GameStateData,
	player: PlayerStateData,
	target_card_id: StringName,
	reason: StringName,
	events: Array[Dictionary]
) -> String:
	return _move_party_member_with_equipment(
		state,
		player,
		target_card_id,
		StringName(player.zone_ids[&"discard_pile"]),
		reason,
		events
	)


static func remove_party_member_with_equipment(
	state: GameStateData,
	player: PlayerStateData,
	target_card_id: StringName,
	reason: StringName,
	events: Array[Dictionary]
) -> String:
	return _move_party_member_with_equipment(
		state,
		player,
		target_card_id,
		StringName(player.zone_ids[&"removed"]),
		reason,
		events
	)


static func move_party_member_with_equipment(
	state: GameStateData,
	player: PlayerStateData,
	target_card_id: StringName,
	target_destination_zone_id: StringName,
	equipment_destination_zone_id: StringName,
	reason: StringName,
	events: Array[Dictionary]
) -> String:
	return _move_party_member_with_equipment(
		state,
		player,
		target_card_id,
		target_destination_zone_id,
		reason,
		events,
		equipment_destination_zone_id
	)


static func detach_equipment(
	state: GameStateData,
	player: PlayerStateData,
	target_card_id: StringName,
	equipment_id: StringName,
	destination_zone_id: StringName,
	reason: StringName,
	events: Array[Dictionary]
) -> String:
	if ZoneService.find_card_zone(state, target_card_id) != StringName(player.zone_ids.get(&"party", &"")) \
			or ZoneService.find_card_zone(state, equipment_id) != StringName(player.zone_ids.get(&"equipment", &"")):
		return "attachment_not_in_expected_zone"
	var target := state.cards.get(target_card_id) as Dictionary
	var equipment := state.cards.get(equipment_id) as Dictionary
	if target == null or equipment == null:
		return "missing_attachment_card"
	var target_state := target.get("state", {}) as Dictionary
	var equipment_ids := target_state.get("equipment_ids", []) as Array
	if str(equipment_id) not in equipment_ids and equipment_id not in equipment_ids:
		return "attachment_link_missing"
	equipment_ids.erase(str(equipment_id))
	equipment_ids.erase(equipment_id)
	target_state["equipment_ids"] = equipment_ids
	target["state"] = target_state
	var equipment_state := equipment.get("state", {}) as Dictionary
	equipment_state.erase("equipped_to")
	equipment["state"] = equipment_state
	var move_result := ZoneService.move_card(
		state, equipment_id, StringName(player.zone_ids.get(&"equipment", &"")),
		destination_zone_id
	)
	if not bool(move_result.get("ok", false)):
		return str(move_result.get("error", "attachment_move_failed"))
	var move_event := (move_result.get("event", {}) as Dictionary).duplicate(true)
	move_event["reason"] = str(reason)
	events.append(move_event)
	return ""


static func _move_party_member_with_equipment(
	state: GameStateData,
	player: PlayerStateData,
	target_card_id: StringName,
	target_destination_zone_id: StringName,
	reason: StringName,
	events: Array[Dictionary],
	equipment_destination_zone_id: StringName = &""
) -> String:
	if ZoneService.find_card_zone(state, target_card_id) != StringName(player.zone_ids[&"party"]):
		return "party_member_not_in_party"
	var target_card := state.cards[target_card_id] as Dictionary
	var target_state := target_card.get("state", {}) as Dictionary
	var equipment_ids := target_state.get("equipment_ids", []) as Array
	if equipment_destination_zone_id.is_empty():
		equipment_destination_zone_id = StringName(player.zone_ids[&"discard_pile"])
	for raw_equipment_id: Variant in equipment_ids.duplicate():
		var equipment_id := StringName(str(raw_equipment_id))
		var equipment_card := state.cards[equipment_id] as Dictionary
		var equipment_state := equipment_card.get("state", {}) as Dictionary
		equipment_state.erase("equipped_to")
		equipment_card["state"] = equipment_state
		var move_result := ZoneService.move_card(
			state,
			equipment_id,
			StringName(player.zone_ids[&"equipment"]),
			equipment_destination_zone_id
		)
		if not bool(move_result.get("ok", false)):
			return str(move_result.get("error", "equipment_departure_failed"))
		var event: Dictionary = (move_result.get("event", {}) as Dictionary).duplicate(true)
		event["reason"] = "%s_equipment" % reason
		events.append(event)
	target_state["equipment_ids"] = []
	target_card["state"] = target_state
	var outgoing_result := ZoneService.move_card(
		state,
		target_card_id,
		StringName(player.zone_ids[&"party"]),
		target_destination_zone_id
	)
	if not bool(outgoing_result.get("ok", false)):
		return str(outgoing_result.get("error", "party_member_discard_failed"))
	var outgoing_event: Dictionary = (outgoing_result.get("event", {}) as Dictionary).duplicate(true)
	outgoing_event["reason"] = str(reason)
	events.append(outgoing_event)
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


static func _is_adventurer(definition: CardDefinition) -> bool:
	return definition != null and &"adventurer" in definition.tags
