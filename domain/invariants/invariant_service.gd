class_name InvariantService
extends RefCounted


static func validate(state: GameStateData) -> PackedStringArray:
	var errors := PackedStringArray()
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
		if not locations.has(instance_id):
			errors.append("Card %s is not in any zone" % instance_id)
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
	return errors
