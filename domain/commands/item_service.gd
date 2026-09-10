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
		if definition != null and definition.card_type == &"item":
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
