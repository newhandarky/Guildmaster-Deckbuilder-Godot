class_name EquipmentService
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
	var party := state.zones.get(player.zone_ids.get(&"party", &"")) as ZoneData
	if hand == null or party == null:
		return commands
	for card_instance_id: StringName in hand.card_instance_ids:
		var definition := _definition_for_card(state, definitions, card_instance_id)
		if definition == null:
			continue
		for target_card_id: StringName in party.card_instance_ids:
			var command := {
				"type": "EQUIP_ITEM",
				"actor_id": str(actor_id),
				"expected_revision": state.revision,
				"card_instance_id": str(card_instance_id),
				"target_card_id": str(target_card_id),
			}
			if validate(state, actor_id, command, definitions).is_empty():
				commands.append(command)
	for card_instance_id: StringName in party.card_instance_ids:
		var definition := _definition_for_card(state, definitions, card_instance_id)
		if definition == null or not _has_operation(definition, &"self_as_equipment"):
			continue
		for target_card_id: StringName in party.card_instance_ids:
			if target_card_id == card_instance_id:
				continue
			var command := {
				"type": "EQUIP_ITEM", "actor_id": str(actor_id),
				"expected_revision": state.revision,
				"card_instance_id": str(card_instance_id),
				"target_card_id": str(target_card_id),
			}
			if validate(state, actor_id, command, definitions).is_empty():
				commands.append(command)
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
	if card_instance_id.is_empty() or not state.cards.has(card_instance_id):
		return "missing_card"
	var card := state.cards[card_instance_id] as Dictionary
	if StringName(card.get("owner_id", "")) != actor_id:
		return "card_not_owned"
	var definition := _definition_for_card(state, definitions, card_instance_id)
	if definition == null:
		return "missing_definition"
	var source_zone_id := ZoneService.find_card_zone(state, card_instance_id)
	var is_self_equipment := _has_operation(definition, &"self_as_equipment")
	if is_self_equipment and not ((card.get("state", {}) as Dictionary).get("equipment_ids", []) as Array).is_empty():
		return "equipped_adventurer_cannot_convert"
	if source_zone_id != StringName(player.zone_ids.get(&"hand", &"")) \
			and (not is_self_equipment \
			or source_zone_id != StringName(player.zone_ids.get(&"party", &""))):
		return "card_not_in_hand"
	var target_card_id := StringName(command.get("target_card_id", ""))
	if target_card_id.is_empty() or not state.cards.has(target_card_id):
		return "missing_target"
	var target_card := state.cards[target_card_id] as Dictionary
	if StringName(target_card.get("owner_id", "")) != actor_id:
		return "target_not_owned"
	if ZoneService.find_card_zone(state, target_card_id) != StringName(player.zone_ids.get(&"party", &"")):
		return "target_not_in_party"
	var target_definition := _definition_for_card(state, definitions, target_card_id)
	if target_definition == null or not &"adventurer" in target_definition.tags:
		return "target_not_adventurer"
	var policy := _equipment_policy(target_definition)
	if int(policy.get("capacity", 1)) <= 0:
		return "target_cannot_equip"
	if not is_self_equipment \
			and definition.card_type not in (policy.get("allowed_card_types", [&"equipment"]) as Array):
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
	var target_card_id := StringName(command.get("target_card_id", ""))
	var equipment_zone_id := StringName(player.zone_ids[&"equipment"])
	var target_card := state.cards[target_card_id] as Dictionary
	var target_state := target_card.get("state", {}) as Dictionary
	var existing_equipment := target_state.get("equipment_ids", []) as Array
	var target_definition := _definition_for_card(state, definitions, target_card_id)
	var policy := _equipment_policy(target_definition)
	var capacity := int(policy.get("capacity", 1))
	var source_zone_id := ZoneService.find_card_zone(state, card_instance_id)
	if str(policy.get("replacement", "automatic")) == "choose" \
			and existing_equipment.size() >= capacity:
		var eligible_ids: Array[String] = []
		for raw_id: Variant in existing_equipment:
			eligible_ids.append(str(raw_id))
		state.effect_state = {
			"type": "pending_choice", "choice_id": "choice-%06d" % (state.revision + 1),
			"actor_id": str(actor_id), "required_actor_id": str(actor_id),
			"op": "choose_equipment_replacement",
			"prompt": "裝備已滿，選擇 1 張棄置後配戴新卡",
			"source_zone_id": str(equipment_zone_id), "source_zone_key": "equipment",
			"destination_zone_id": str(player.zone_ids[&"discard_pile"]),
			"eligible_card_ids": eligible_ids, "selected_card_ids": [], "selected_count": 0,
			"min_selections": 1, "max_selections": 1,
			"pending_equipment_id": str(card_instance_id),
			"pending_equipment_source_zone_id": str(source_zone_id),
			"target_card_id": str(target_card_id),
		}
		events.append({
			"type": "choice_requested", "choice_id": str(state.effect_state["choice_id"]),
			"actor_id": str(actor_id), "required_actor_id": str(actor_id),
			"op": "choose_equipment_replacement", "eligible_card_ids": eligible_ids,
			"optional": false, "source_card_instance_id": str(card_instance_id),
		})
		return ""

	var replaced_equipment: Array = []
	if existing_equipment.size() >= capacity and str(policy.get("replacement", "automatic")) != "choose":
		replaced_equipment.append(existing_equipment[0])
	for raw_existing_id: Variant in replaced_equipment:
		var existing_id := StringName(str(raw_existing_id))
		var existing_card := state.cards[existing_id] as Dictionary
		var existing_state := existing_card.get("state", {}) as Dictionary
		existing_state.erase("equipped_to")
		existing_card["state"] = existing_state
		var replace_result := ZoneService.move_card(
			state,
			existing_id,
			equipment_zone_id,
			StringName(player.zone_ids[&"discard_pile"])
		)
		if not bool(replace_result.get("ok", false)):
			return str(replace_result.get("error", "equipment_replace_failed"))
		var replace_event: Dictionary = (replace_result.get("event", {}) as Dictionary).duplicate(true)
		replace_event["reason"] = "equipment_replaced"
		events.append(replace_event)
		existing_equipment.erase(str(existing_id))
		existing_equipment.erase(existing_id)

	var move_result := ZoneService.move_card(
		state,
		card_instance_id,
		source_zone_id,
		equipment_zone_id
	)
	if not bool(move_result.get("ok", false)):
		return str(move_result.get("error", "card_move_failed"))
	var move_event: Dictionary = (move_result.get("event", {}) as Dictionary).duplicate(true)
	move_event["reason"] = "equipment_attached"
	events.append(move_event)
	var card := state.cards[card_instance_id] as Dictionary
	var card_state := card.get("state", {}) as Dictionary
	card_state["equipped_to"] = str(target_card_id)
	card["state"] = card_state
	existing_equipment.append(str(card_instance_id))
	target_state["equipment_ids"] = existing_equipment
	target_card["state"] = target_state
	events.append({
		"type": "card_equipped",
		"actor_id": str(actor_id),
		"card_instance_id": str(card_instance_id),
		"target_card_id": str(target_card_id),
	})

	var definition := _definition_for_card(state, definitions, card_instance_id)
	var on_play_effects: Array[Dictionary] = []
	for effect: Dictionary in definition.effects:
		if StringName(effect.get("timing", "on_play")) == &"on_play":
			on_play_effects.append(effect)
	var effect_error := EffectResolver.resolve(
		state, actor_id, on_play_effects, events, definitions
	)
	if not effect_error.is_empty() or not state.effect_state.is_empty():
		return effect_error
	return EffectResolver.resolve_trigger_for_source(
		state, actor_id, target_card_id, &"on_equipment_attached", events, definitions
	)


static func _equipment_policy(definition: CardDefinition) -> Dictionary:
	var policy := {"capacity": 1, "allowed_card_types": [&"equipment"], "replacement": "automatic"}
	if definition == null:
		return policy
	for effect: Dictionary in definition.effects:
		if StringName(effect.get("op", "")) != &"equipment_policy":
			continue
		policy["capacity"] = int(effect.get("capacity", 1))
		policy["replacement"] = str(effect.get("replacement", "automatic"))
		if effect.has("allowed_card_types"):
			var allowed: Array[StringName] = []
			for raw_type: Variant in effect.get("allowed_card_types", []):
				allowed.append(StringName(str(raw_type)))
			policy["allowed_card_types"] = allowed
	return policy


static func _has_operation(definition: CardDefinition, operation: StringName) -> bool:
	for effect: Dictionary in definition.effects:
		if StringName(effect.get("op", "")) == operation:
			return true
	return false


static func _definition_for_card(
	state: GameStateData,
	definitions: Dictionary,
	card_instance_id: StringName
) -> CardDefinition:
	var card := state.cards.get(card_instance_id) as Dictionary
	if card == null:
		return null
	return definitions.get(StringName(card.get("definition_id", ""))) as CardDefinition
