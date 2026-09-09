class_name ZoneService
extends RefCounted


static func find_card_zone(state: GameStateData, card_instance_id: StringName) -> StringName:
	for zone_id: Variant in state.zones:
		var zone := state.zones[zone_id] as ZoneData
		if zone != null and card_instance_id in zone.card_instance_ids:
			return zone.zone_id
	return &""


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
	return {
		"ok": true,
		"event": {
			"type": "card_moved",
			"card_instance_id": str(card_instance_id),
			"from_zone_id": str(from_zone_id),
			"to_zone_id": str(to_zone_id),
			"to_index": resolved_index,
		},
	}


static func _failure(error_code: String) -> Dictionary:
	return {"ok": false, "error": error_code}
