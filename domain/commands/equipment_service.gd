class_name EquipmentService
extends RefCounted

const ACTION_PHASES: Array[StringName] = [&"action1", &"action2"]


static func get_legal_commands(
	state: GameStateData,
	actor_id: StringName,
	definitions: Dictionary
) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	if state.phase not in ACTION_PHASES and state.phase != &"combat":
		return commands
	var player := state.players.get(actor_id) as PlayerStateData
	if player == null:
		return commands
	var hand := state.zones.get(player.zone_ids.get(&"hand", &"")) as ZoneData
	var party := state.zones.get(player.zone_ids.get(&"party", &"")) as ZoneData
	if hand == null or party == null:
		return commands
	if state.phase == &"combat":
		return _get_combat_effect_commands(state, actor_id, definitions, hand)
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


static func _get_combat_effect_commands(
	state: GameStateData,
	actor_id: StringName,
	definitions: Dictionary,
	hand: ZoneData
) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	var player := state.players.get(actor_id) as PlayerStateData
	var equipment := state.zones.get(player.zone_ids.get(&"equipment", &"")) as ZoneData
	if equipment == null:
		return commands
	for equipment_id: StringName in equipment.card_instance_ids:
		var definition := _definition_for_card(state, definitions, equipment_id)
		if definition == null or bool(player.turn_facts.get("equipment_attack_used:%s" % equipment_id, false)):
			continue
		for effect_index in definition.effects.size():
			var effect := definition.effects[effect_index]
			if StringName(effect.get("op", "")) != &"discard_for_equipment_combat" \
					or StringName(effect.get("timing", "")) != &"on_attack":
				continue
			var has_candidate := false
			for hand_id: StringName in hand.card_instance_ids:
				var hand_definition := _definition_for_card(state, definitions, hand_id)
				has_candidate = has_candidate or (hand_definition != null \
						and hand_definition.card_type in _string_names(effect.get("allowed_card_types", [])))
			if has_candidate:
				commands.append({"type":"ACTIVATE_EQUIPMENT_EFFECT","actor_id":str(actor_id),"expected_revision":state.revision,"card_instance_id":str(equipment_id),"effect_index":effect_index})
	return commands


static func validate(
	state: GameStateData,
	actor_id: StringName,
	command: Dictionary,
	definitions: Dictionary
) -> String:
	if StringName(command.get("type", "")) == &"ACTIVATE_EQUIPMENT_EFFECT":
		return _validate_combat_effect(state, actor_id, command, definitions)
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
	if not is_self_equipment:
		for effect: Dictionary in definition.effects:
			if StringName(effect.get("op", "")) != &"equipment_policy":
				continue
			var allowed_target_tags: Array[StringName] = []
			for raw_tag: Variant in effect.get("allowed_target_tags", []):
				allowed_target_tags.append(StringName(str(raw_tag)))
			if not allowed_target_tags.is_empty():
				var matches := false
				for tag: StringName in allowed_target_tags:
					matches = matches or tag in target_definition.tags
				if not matches:
					return "equipment_target_tag_restricted"
	return ""


static func _validate_combat_effect(
	state: GameStateData, actor_id: StringName, command: Dictionary, definitions: Dictionary
) -> String:
	if state.phase != &"combat": return "wrong_phase"
	var player := state.players.get(actor_id) as PlayerStateData
	var equipment_id := StringName(command.get("card_instance_id", ""))
	if player == null or ZoneService.find_card_zone(state, equipment_id) != StringName(player.zone_ids.get(&"equipment", &"")): return "equipment_not_attached"
	if bool(player.turn_facts.get("equipment_attack_used:%s" % equipment_id, false)): return "equipment_effect_already_used"
	var definition := _definition_for_card(state, definitions, equipment_id)
	var effect_index := int(command.get("effect_index", -1))
	if definition == null or effect_index < 0 or effect_index >= definition.effects.size(): return "missing_equipment_effect"
	var effect := definition.effects[effect_index]
	if StringName(effect.get("op", "")) != &"discard_for_equipment_combat": return "unsupported_equipment_effect"
	var hand := state.zones.get(player.zone_ids.get(&"hand", &"")) as ZoneData
	for card_id: StringName in hand.card_instance_ids if hand != null else []:
		var card_definition := _definition_for_card(state, definitions, card_id)
		if card_definition != null and card_definition.card_type in _string_names(effect.get("allowed_card_types", [])): return ""
	return "equipment_cost_unpayable"


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
	if StringName(command.get("type", "")) == &"ACTIVATE_EQUIPMENT_EFFECT":
		return _apply_combat_effect(state, actor_id, command, definitions, events)
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
	if capacity > 1:
		target_state["equipment_capacity"] = capacity
	else:
		target_state.erase("equipment_capacity")
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


static func _apply_combat_effect(
	state: GameStateData, actor_id: StringName, command: Dictionary,
	definitions: Dictionary, events: Array[Dictionary]
) -> String:
	var player := state.players[actor_id] as PlayerStateData
	var equipment_id := StringName(command.get("card_instance_id", ""))
	var equipment_card := state.cards[equipment_id] as Dictionary
	var wearer_id := str((equipment_card.get("state", {}) as Dictionary).get("equipped_to", ""))
	var definition := _definition_for_card(state, definitions, equipment_id)
	var effect := definition.effects[int(command.get("effect_index", -1))]
	var cost_effect := {
		"op":"discard_card_cost", "source_zone_key":"hand", "amount":1,
		"allowed_card_types":(effect.get("allowed_card_types", []) as Array).duplicate(),
		"source_card_instance_id":str(equipment_id),
		"prompt":"棄置 1 張手牌中的魔物或魔王，依其印刷購買力增加配戴者戰力",
		"then_effects":[{"op":"grant_card_combat_from_selected_field","field":str(effect.get("value_field", "purchase_power")),"target_card_id":wearer_id,"source_equipment_id":str(equipment_id)}],
	}
	player.turn_facts["equipment_attack_used:%s" % equipment_id] = true
	return EffectResolver.resolve(state, actor_id, [cost_effect], events, definitions)


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


static func _string_names(values: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Variant in values if values is Array else []:
		result.append(StringName(str(value)))
	return result
