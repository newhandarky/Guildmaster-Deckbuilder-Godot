class_name MarketRefreshService
extends RefCounted

const REFRESHABLE_ROWS: Dictionary = {
	SupplyService.RECRUIT_ROW_ID: SupplyService.RECRUIT_DECK_ID,
	SupplyService.SHOP_ROW_ID: SupplyService.SHOP_DECK_ID,
}
const TURN_FACT_KEY := &"market_refreshed"


static func get_legal_commands(state: GameStateData, actor_id: StringName) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	if state.phase != &"purchase":
		return commands
	var player := state.players.get(actor_id) as PlayerStateData
	if player == null or bool(player.turn_facts.get(TURN_FACT_KEY, false)):
		return commands
	var hand := state.zones.get(player.zone_ids.get(&"hand", &"")) as ZoneData
	if hand == null or hand.card_instance_ids.is_empty():
		return commands
	var rows: Dictionary = {}
	for row_zone_id: StringName in REFRESHABLE_ROWS:
		var row := state.zones.get(row_zone_id) as ZoneData
		if row != null and not row.card_instance_ids.is_empty():
			rows[str(row_zone_id)] = _to_strings(row.card_instance_ids)
	if rows.is_empty():
		return commands
	commands.append({
		"type": "REFRESH_MARKET",
		"actor_id": str(actor_id),
		"expected_revision": state.revision,
		"discard_card_ids": _to_strings(hand.card_instance_ids),
		"rows": rows,
		"minimum_cards": 1,
		"maximum_cards": 3,
	})
	return commands


static func validate(state: GameStateData, actor_id: StringName, command: Dictionary) -> String:
	if state.phase != &"purchase":
		return "wrong_phase"
	var player := state.players.get(actor_id) as PlayerStateData
	if player == null:
		return "missing_player"
	if bool(player.turn_facts.get(TURN_FACT_KEY, false)):
		return "market_refresh_already_used"
	var discard_card_id := StringName(command.get("discard_card_id", ""))
	if not state.cards.has(discard_card_id):
		return "missing_discard_card"
	if ZoneService.find_card_zone(state, discard_card_id) != StringName(player.zone_ids[&"hand"]):
		return "refresh_cost_not_in_hand"
	var discard_card := state.cards[discard_card_id] as Dictionary
	if StringName(discard_card.get("owner_id", "")) != actor_id:
		return "refresh_cost_not_owned"
	var row_zone_id := StringName(command.get("row_id", ""))
	if not REFRESHABLE_ROWS.has(row_zone_id):
		return "invalid_refresh_row"
	var selected_raw: Variant = command.get("card_instance_ids", [])
	if not selected_raw is Array:
		return "invalid_refresh_selection"
	var selected := selected_raw as Array
	if selected.size() < 1 or selected.size() > 3:
		return "invalid_refresh_count"
	var unique_ids: Dictionary = {}
	for raw_card_id: Variant in selected:
		var card_instance_id := StringName(str(raw_card_id))
		if unique_ids.has(card_instance_id):
			return "duplicate_refresh_card"
		unique_ids[card_instance_id] = true
		if not state.cards.has(card_instance_id):
			return "missing_card"
		if ZoneService.find_card_zone(state, card_instance_id) != row_zone_id:
			return "card_not_in_refresh_row"
	return ""


static func apply(
	state: GameStateData,
	actor_id: StringName,
	command: Dictionary,
	events: Array[Dictionary]
) -> String:
	var validation_error := validate(state, actor_id, command)
	if not validation_error.is_empty():
		return validation_error
	var player := state.players[actor_id] as PlayerStateData
	var discard_card_id := StringName(command.get("discard_card_id", ""))
	var discard_result := ZoneService.move_card(
		state,
		discard_card_id,
		StringName(player.zone_ids[&"hand"]),
		StringName(player.zone_ids[&"discard_pile"])
	)
	if not bool(discard_result.get("ok", false)):
		return str(discard_result.get("error", "refresh_cost_failed"))
	var discard_event: Dictionary = (discard_result.get("event", {}) as Dictionary).duplicate(true)
	discard_event["reason"] = "market_refresh_cost"
	events.append(discard_event)

	var row_zone_id := StringName(command.get("row_id", ""))
	var deck_zone_id := StringName(REFRESHABLE_ROWS[row_zone_id])
	var row := state.zones[row_zone_id] as ZoneData
	var deck := state.zones[deck_zone_id] as ZoneData
	var original_row_size := row.card_instance_ids.size()
	var selected_ids: Array[StringName] = []
	for raw_card_id: Variant in command.get("card_instance_ids", []):
		selected_ids.append(StringName(str(raw_card_id)))
	selected_ids.sort()
	for card_instance_id: StringName in selected_ids:
		var return_result := ZoneService.move_card(state, card_instance_id, row_zone_id, deck_zone_id)
		if not bool(return_result.get("ok", false)):
			return str(return_result.get("error", "refresh_return_failed"))
		var return_event: Dictionary = (return_result.get("event", {}) as Dictionary).duplicate(true)
		return_event["reason"] = "market_refresh_return"
		events.append(return_event)

	deck.metadata["depletion_announced"] = false
	var rng := DeterministicRng.new(state.seed_value, state.rng_state)
	rng.shuffle(deck.card_instance_ids)
	state.rng_state = rng.get_state()
	events.append({
		"type": "supply_deck_shuffled",
		"deck_zone_id": str(deck_zone_id),
		"reason": "market_refresh",
	})
	var refill_error := SupplyService.refill_row(
		state,
		deck_zone_id,
		row_zone_id,
		original_row_size,
		events
	)
	if not refill_error.is_empty():
		return refill_error
	player.turn_facts[TURN_FACT_KEY] = true
	events.append({
		"type": "market_refreshed",
		"actor_id": str(actor_id),
		"discard_card_id": str(discard_card_id),
		"row_id": str(row_zone_id),
		"returned_card_ids": _to_strings(selected_ids),
	})
	return ""


static func _to_strings(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value: StringName in values:
		result.append(str(value))
	return result
