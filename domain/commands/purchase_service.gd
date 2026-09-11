class_name PurchaseService
extends RefCounted

const PURCHASABLE_ROWS: Array[StringName] = [
	SupplyService.RECRUIT_ROW_ID,
	SupplyService.SHOP_ROW_ID,
]


static func get_legal_commands(
	state: GameStateData,
	actor_id: StringName,
	definitions: Dictionary
) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	if state.phase != &"purchase":
		return commands
	var resources := ResourceService.evaluate_player(state, actor_id, definitions)
	if not bool(resources.get("ok", false)):
		return commands
	var available := int(resources.get("purchase_power", 0))
	for row_zone_id: StringName in PURCHASABLE_ROWS:
		var row := state.zones.get(row_zone_id) as ZoneData
		if row == null:
			continue
		for card_instance_id: StringName in row.card_instance_ids:
			var definition := _definition_for_card(state, definitions, card_instance_id)
			if definition == null or definition.cost == null:
				continue
			var cost := ResourceService.effective_purchase_cost(
				state, actor_id, card_instance_id, definitions
			)
			if cost <= available:
				commands.append({
					"type": "BUY_CARD",
					"actor_id": str(actor_id),
					"expected_revision": state.revision,
					"card_instance_id": str(card_instance_id),
					"source_row_id": str(row_zone_id),
					"effective_cost": cost,
				})
	return commands


static func validate(
	state: GameStateData,
	actor_id: StringName,
	command: Dictionary,
	definitions: Dictionary
) -> String:
	if state.phase != &"purchase":
		return "wrong_phase"
	var player := state.players.get(actor_id) as PlayerStateData
	if player == null:
		return "missing_player"
	var row_zone_id := StringName(command.get("source_row_id", ""))
	if not row_zone_id in PURCHASABLE_ROWS:
		return "invalid_purchase_row"
	var card_instance_id := StringName(command.get("card_instance_id", ""))
	if not state.cards.has(card_instance_id):
		return "missing_card"
	if ZoneService.find_card_zone(state, card_instance_id) != row_zone_id:
		return "card_not_in_market_row"
	var card := state.cards[card_instance_id] as Dictionary
	if not StringName(card.get("owner_id", "")).is_empty():
		return "market_card_already_owned"
	var definition := _definition_for_card(state, definitions, card_instance_id)
	if definition == null:
		return "missing_definition"
	if definition.cost == null:
		return "card_not_purchasable"
	var resources := ResourceService.evaluate_player(state, actor_id, definitions)
	if not bool(resources.get("ok", false)):
		return str(resources.get("error", "resource_evaluation_failed"))
	if ResourceService.effective_purchase_cost(state, actor_id, card_instance_id, definitions) \
			> int(resources.get("purchase_power", 0)):
		return "insufficient_purchase_power"
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
	var card_instance_id := StringName(command.get("card_instance_id", ""))
	var row_zone_id := StringName(command.get("source_row_id", ""))
	var definition := _definition_for_card(state, definitions, card_instance_id)
	var cost := ResourceService.effective_purchase_cost(
		state, actor_id, card_instance_id, definitions
	)
	var move_result := ZoneService.move_card(
		state,
		card_instance_id,
		row_zone_id,
		StringName(player.zone_ids[&"discard_pile"])
	)
	if not bool(move_result.get("ok", false)):
		return str(move_result.get("error", "purchase_move_failed"))
	var card := state.cards[card_instance_id] as Dictionary
	card["owner_id"] = str(actor_id)
	player.spent_purchase_power += cost
	var move_event: Dictionary = (move_result.get("event", {}) as Dictionary).duplicate(true)
	move_event["reason"] = "card_purchased"
	events.append(move_event)
	events.append({
		"type": "card_purchased",
		"actor_id": str(actor_id),
		"card_instance_id": str(card_instance_id),
		"source_row_id": str(row_zone_id),
		"cost": cost,
		"remaining_purchase_power": int(
			ResourceService.evaluate_player(state, actor_id, definitions).get("purchase_power", 0)
		),
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
