class_name ResourceService
extends RefCounted


static func evaluate_player(
	state: GameStateData,
	player_id: StringName,
	definitions: Dictionary
) -> Dictionary:
	var player := state.players.get(player_id) as PlayerStateData
	if player == null:
		return {"ok": false, "error": "missing_player"}

	var combat := int(player.turn_resources.get("combat", 0))
	var purchase_power := int(player.turn_resources.get("purchase_power", 0))
	var party := state.zones.get(player.zone_ids.get(&"party", &"")) as ZoneData
	var hand := state.zones.get(player.zone_ids.get(&"hand", &"")) as ZoneData
	var equipment := state.zones.get(player.zone_ids.get(&"equipment", &"")) as ZoneData
	if party == null or hand == null or equipment == null:
		return {"ok": false, "error": "missing_player_card_zone"}

	for card_instance_id: StringName in party.card_instance_ids:
		combat += _printed_value(state, definitions, card_instance_id, &"combat")
	for card_instance_id: StringName in equipment.card_instance_ids:
		var card := state.cards.get(card_instance_id) as Dictionary
		var card_state := card.get("state", {}) as Dictionary if card != null else {}
		if not StringName(card_state.get("equipped_to", "")).is_empty():
			combat += _printed_value(state, definitions, card_instance_id, &"combat")
	for card_instance_id: StringName in hand.card_instance_ids:
		purchase_power += _printed_value(state, definitions, card_instance_id, &"purchase_power")
	purchase_power = maxi(0, purchase_power - player.spent_purchase_power)
	return {
		"ok": true,
		"combat": maxi(0, combat),
		"purchase_power": purchase_power,
		"spent_purchase_power": player.spent_purchase_power,
	}


static func _printed_value(
	state: GameStateData,
	definitions: Dictionary,
	card_instance_id: StringName,
	field_name: StringName
) -> int:
	var card := state.cards.get(card_instance_id) as Dictionary
	if card == null:
		return 0
	var definition := definitions.get(StringName(card.get("definition_id", ""))) as CardDefinition
	if definition == null:
		return 0
	var value: Variant = definition.get(str(field_name))
	return 0 if value == null else int(value)
