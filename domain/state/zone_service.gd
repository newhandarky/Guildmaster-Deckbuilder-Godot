class_name ZoneService
extends RefCounted


static func find_card_zone(state: GameStateData, card_instance_id: StringName) -> StringName:
	for zone_id: Variant in state.zones:
		var zone := state.zones[zone_id] as ZoneData
		if zone != null and card_instance_id in zone.card_instance_ids:
			return zone.zone_id
	return &""


static func resolved_destination(
	state: GameStateData, card_instance_id: StringName, requested_zone_id: StringName
) -> StringName:
	var destination := state.zones.get(requested_zone_id) as ZoneData
	if destination == null:
		return &""
	var replacement := _resolve_discard_destination_replacement(
		state, card_instance_id, destination
	)
	return StringName(replacement.get("zone_id", requested_zone_id))


static func actual_owner_after_move(
	state: GameStateData, move_result: Dictionary, fallback_id: StringName
) -> StringName:
	var actual_zone_id := StringName((move_result.get("event", {}) as Dictionary).get(
		"to_zone_id", ""
	))
	var actual_zone := state.zones.get(actual_zone_id) as ZoneData
	return StringName(actual_zone.metadata.get("owner_id", fallback_id)) \
		if actual_zone != null else fallback_id


static func move_card(
	state: GameStateData,
	card_instance_id: StringName,
	from_zone_id: StringName,
	to_zone_id: StringName,
	insert_index: int = -1
) -> Dictionary:
	if not state.cards.has(card_instance_id):
		return _failure("missing_card")
	if from_zone_id == to_zone_id:
		return _failure("same_zone")
	var source := state.zones.get(from_zone_id) as ZoneData
	var destination := state.zones.get(to_zone_id) as ZoneData
	if source == null:
		return _failure("missing_source_zone")
	if destination == null:
		return _failure("missing_destination_zone")
	var requested_destination_id := to_zone_id
	var replacement := _resolve_discard_destination_replacement(
		state, card_instance_id, destination
	)
	if not replacement.is_empty():
		to_zone_id = StringName(replacement.get("zone_id", ""))
		destination = state.zones.get(to_zone_id) as ZoneData
		if destination == null:
			return _failure("missing_replacement_destination_zone")
	var source_index := source.card_instance_ids.find(card_instance_id)
	if source_index < 0:
		return _failure("card_not_in_source")
	if destination.card_instance_ids.has(card_instance_id):
		return _failure("card_already_in_destination")
	var resolved_index := destination.card_instance_ids.size() if insert_index == -1 else insert_index
	if resolved_index < 0 or resolved_index > destination.card_instance_ids.size():
		return _failure("invalid_insert_index")

	source.card_instance_ids.remove_at(source_index)
	destination.card_instance_ids.insert(resolved_index, card_instance_id)
	if not replacement.is_empty():
		var card := state.cards[card_instance_id] as Dictionary
		card["owner_id"] = str(replacement.get("owner_id", ""))
	return {
		"ok": true,
		"event": {
			"type": "card_moved",
			"card_instance_id": str(card_instance_id),
			"from_zone_id": str(from_zone_id),
			"to_zone_id": str(to_zone_id),
			"requested_to_zone_id": str(requested_destination_id),
			"destination_replaced": not replacement.is_empty(),
			"to_index": resolved_index,
		},
	}


static func _resolve_discard_destination_replacement(
	state: GameStateData,
	card_instance_id: StringName,
	destination: ZoneData
) -> Dictionary:
	if destination.kind != &"discard_pile":
		return {}
	var card := state.cards.get(card_instance_id) as Dictionary
	if card == null or str((card.get("state", {}) as Dictionary).get(
		"discard_destination_replacement", ""
	)) != "right_player_discard":
		return {}
	var current_owner_id := StringName(destination.metadata.get("owner_id", ""))
	var current_index := state.turn_order.find(current_owner_id)
	if current_index < 0 or state.turn_order.size() < 2:
		return {}
	var next_owner_id := state.turn_order[(current_index + 1) % state.turn_order.size()]
	var next_player := state.players.get(next_owner_id) as PlayerStateData
	if next_player == null:
		return {}
	return {
		"zone_id": str(next_player.zone_ids.get(&"discard_pile", &"")),
		"owner_id": str(next_owner_id),
	}


static func _failure(error_code: String) -> Dictionary:
	return {"ok": false, "error": error_code}
