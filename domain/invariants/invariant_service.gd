class_name InvariantService
extends RefCounted


static func validate(state: GameStateData) -> PackedStringArray:
	var errors := PackedStringArray()
	_validate_turn_order(state, errors)
	_validate_players(state, errors)
	_validate_supply_zones(state, errors)
	var locations: Dictionary = {}
	for zone_id: Variant in state.zones:
		var zone := state.zones[zone_id] as ZoneData
		if zone == null:
			errors.append("Invalid zone at %s" % zone_id)
			continue
		if zone.zone_id.is_empty():
			errors.append("Zone ID must not be empty")
		elif StringName(zone_id) != zone.zone_id:
			errors.append("Zone key %s does not match zone_id %s" % [zone_id, zone.zone_id])
		var zone_owner_id := StringName(zone.metadata.get("owner_id", ""))
		if not zone_owner_id.is_empty():
			var owner := state.players.get(zone_owner_id) as PlayerStateData
			if owner == null:
				errors.append("Zone %s references missing owner %s" % [zone_id, zone_owner_id])
			elif not zone.zone_id in owner.zone_ids.values():
				errors.append("Owned zone %s is not referenced by player %s" % [zone_id, zone_owner_id])
		for instance_id: StringName in zone.card_instance_ids:
			if not state.cards.has(instance_id):
				errors.append("Zone %s references missing card %s" % [zone_id, instance_id])
				continue
			if locations.has(instance_id):
				errors.append("Card %s exists in both %s and %s" % [instance_id, locations[instance_id], zone_id])
				continue
			locations[instance_id] = zone_id
	for instance_id: Variant in state.cards:
		var card := state.cards[instance_id] as Dictionary
		if card == null:
			errors.append("Invalid card at %s" % instance_id)
			continue
		if StringName(card.get("instance_id", "")) != StringName(instance_id):
			errors.append("Card key %s does not match instance_id %s" % [instance_id, card.get("instance_id", "")])
		var owner_id := StringName(card.get("owner_id", ""))
		if not owner_id.is_empty() and not state.players.has(owner_id):
			errors.append("Card %s references missing owner %s" % [instance_id, owner_id])
		if not locations.has(instance_id):
			errors.append("Card %s is not in any zone" % instance_id)
	_validate_equipment_attachments(state, locations, errors)
	var command_ids: Dictionary = {}
	for command_id: String in state.processed_command_ids:
		if command_id.is_empty():
			errors.append("Processed command ID must not be empty")
		elif command_ids.has(command_id):
			errors.append("Processed command ID is duplicated: %s" % command_id)
		else:
			command_ids[command_id] = true
	if not state.phase in [&"action1", &"combat", &"action2", &"purchase", &"rest"]:
		errors.append("Invalid phase: %s" % state.phase)
	if state.status == &"active" and state.active_player_id.is_empty():
		errors.append("Active game requires an active player")
	if not state.status in [&"active", &"finished"]:
		errors.append("Invalid game status: %s" % state.status)
	if state.round_number < 1:
		errors.append("Round must be positive")
	if state.revision < 0 or state.event_cursor < 0:
		errors.append("Revision and event cursor must not be negative")
	return errors


static func _validate_supply_zones(state: GameStateData, errors: PackedStringArray) -> void:
	for row_zone_id: StringName in [SupplyService.RECRUIT_ROW_ID, SupplyService.SHOP_ROW_ID]:
		var row := state.zones.get(row_zone_id) as ZoneData
		if row == null:
			errors.append("Missing supply row %s" % row_zone_id)
		elif row.kind != &"face_up_row" or row.visibility != &"public":
			errors.append("Supply row %s must be a public face-up row" % row_zone_id)
		elif row.card_instance_ids.size() > SupplyService.ROW_SIZE:
			errors.append("Supply row %s exceeds capacity" % row_zone_id)
	for deck_zone_id: StringName in [SupplyService.RECRUIT_DECK_ID, SupplyService.SHOP_DECK_ID]:
		var deck := state.zones.get(deck_zone_id) as ZoneData
		if deck == null:
			errors.append("Missing supply deck %s" % deck_zone_id)
		elif deck.kind != &"ordered_deck" or deck.visibility != &"hidden":
			errors.append("Supply deck %s must be a hidden ordered deck" % deck_zone_id)


static func _validate_equipment_attachments(
	state: GameStateData,
	locations: Dictionary,
	errors: PackedStringArray
) -> void:
	var occupied_targets: Dictionary = {}
	for instance_id: Variant in state.cards:
		var card := state.cards[instance_id] as Dictionary
		if card == null or not card.get("state", {}) is Dictionary:
			errors.append("Card %s state must be a Dictionary" % instance_id)
			continue
		var card_state := card.get("state", {}) as Dictionary
		var equipment_ids_value: Variant = card_state.get("equipment_ids", [])
		if not equipment_ids_value is Array:
			errors.append("Card %s equipment_ids must be an Array" % instance_id)
		else:
			var seen_equipment: Dictionary = {}
			for raw_equipment_id: Variant in equipment_ids_value as Array:
				var equipment_id := StringName(str(raw_equipment_id))
				if seen_equipment.has(equipment_id):
					errors.append("Card %s lists equipment %s more than once" % [instance_id, equipment_id])
					continue
				seen_equipment[equipment_id] = true
				var equipment_card := state.cards.get(equipment_id) as Dictionary
				if equipment_card == null:
					errors.append("Card %s lists missing equipment %s" % [instance_id, equipment_id])
					continue
				var equipment_state := equipment_card.get("state", {}) as Dictionary
				if StringName(equipment_state.get("equipped_to", "")) != StringName(instance_id):
					errors.append("Card %s and equipment %s attachment is not bidirectional" % [instance_id, equipment_id])
		var target_id := StringName(card_state.get("equipped_to", ""))
		if target_id.is_empty():
			continue
		if not state.cards.has(target_id):
			errors.append("Equipment %s references missing target %s" % [instance_id, target_id])
			continue
		if occupied_targets.has(target_id):
			errors.append("Target %s has more than one equipment" % target_id)
		else:
			occupied_targets[target_id] = instance_id
		var owner_id := StringName(card.get("owner_id", ""))
		var target_card := state.cards[target_id] as Dictionary
		if StringName(target_card.get("owner_id", "")) != owner_id:
			errors.append("Equipment %s and target %s have different owners" % [instance_id, target_id])
		var target_state := target_card.get("state", {}) as Dictionary
		var target_equipment_value: Variant = target_state.get("equipment_ids", [])
		if not target_equipment_value is Array:
			errors.append("Equipment target %s equipment_ids must be an Array" % target_id)
			continue
		var target_equipment_ids := target_equipment_value as Array
		if not str(instance_id) in target_equipment_ids and not StringName(instance_id) in target_equipment_ids:
			errors.append("Equipment %s is not listed by target %s" % [instance_id, target_id])
		var player := state.players.get(owner_id) as PlayerStateData
		if player == null:
			continue
		if StringName(locations.get(instance_id, "")) != StringName(player.zone_ids.get(&"equipment", &"")):
			errors.append("Equipped card %s must be in its owner's equipment zone" % instance_id)
		if StringName(locations.get(target_id, "")) != StringName(player.zone_ids.get(&"party", &"")):
			errors.append("Equipment target %s must be in its owner's party" % target_id)


static func _validate_turn_order(state: GameStateData, errors: PackedStringArray) -> void:
	if state.turn_order.size() < 2 or state.turn_order.size() > 4:
		errors.append("Turn order must contain 2 to 4 players")
	var seen: Dictionary = {}
	for player_id: StringName in state.turn_order:
		if player_id.is_empty():
			errors.append("Turn order contains an empty player ID")
		elif seen.has(player_id):
			errors.append("Turn order contains duplicate player %s" % player_id)
		else:
			seen[player_id] = true
		if not state.players.has(player_id):
			errors.append("Turn order references missing player %s" % player_id)
	if state.players.size() != state.turn_order.size():
		errors.append("Players and turn order must contain the same entries")
	if not state.starting_player_id in state.turn_order:
		errors.append("Starting player must be in turn order")
	if not state.active_player_id in state.turn_order:
		errors.append("Active player must be in turn order")


static func _validate_players(state: GameStateData, errors: PackedStringArray) -> void:
	var seats: Dictionary = {}
	var referenced_zone_ids: Dictionary = {}
	var expected_zone_kinds := {
		&"draw_pile": &"ordered_deck",
		&"hand": &"hand",
		&"discard_pile": &"discard_pile",
		&"party": &"party",
		&"equipment": &"equipment",
		&"play_area": &"play_area",
		&"bonds": &"bonds",
	}
	for player_id: Variant in state.players:
		var player := state.players[player_id] as PlayerStateData
		if player == null:
			errors.append("Invalid player at %s" % player_id)
			continue
		if StringName(player_id) != player.player_id:
			errors.append("Player key %s does not match player_id %s" % [player_id, player.player_id])
		if player.display_name.is_empty():
			errors.append("Player %s requires a display name" % player_id)
		if player.seat_index < 0 or player.seat_index >= state.turn_order.size():
			errors.append("Player %s has invalid seat index %d" % [player_id, player.seat_index])
		elif seats.has(player.seat_index):
			errors.append("Seat index %d is assigned more than once" % player.seat_index)
		else:
			seats[player.seat_index] = player_id
			if state.turn_order[player.seat_index] != player.player_id:
				errors.append("Player %s seat does not match turn order" % player_id)
		for zone_key: StringName in PlayerStateData.REQUIRED_ZONE_KEYS:
			if not player.zone_ids.has(zone_key):
				errors.append("Player %s is missing zone reference %s" % [player_id, zone_key])
				continue
			var zone_id := StringName(player.zone_ids[zone_key])
			if zone_id.is_empty():
				errors.append("Player %s has an empty zone reference for %s" % [player_id, zone_key])
				continue
			if referenced_zone_ids.has(zone_id):
				errors.append("Player zone %s is referenced more than once" % zone_id)
			else:
				referenced_zone_ids[zone_id] = true
			var zone := state.zones.get(zone_id) as ZoneData
			if zone == null:
				errors.append("Player %s references missing zone %s" % [player_id, zone_id])
			elif StringName(zone.metadata.get("owner_id", "")) != player.player_id:
				errors.append("Player zone %s has the wrong owner" % zone_id)
			elif zone.kind != expected_zone_kinds[zone_key]:
				errors.append("Player zone %s has invalid kind %s" % [zone_id, zone.kind])
			var expected_visibility: StringName = &"owner_only" if zone_key in [&"draw_pile", &"hand", &"bonds"] else &"public"
			if zone != null and zone.visibility != expected_visibility:
				errors.append("Player zone %s has invalid visibility %s" % [zone_id, zone.visibility])
