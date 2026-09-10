class_name CombatService
extends RefCounted


static func get_legal_commands(
	state: GameStateData,
	actor_id: StringName,
	definitions: Dictionary
) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	if state.phase != &"combat":
		return commands
	var row := state.zones.get(SupplyService.MONSTER_ROW_ID) as ZoneData
	if row == null:
		return commands
	for target_card_id: StringName in row.card_instance_ids:
		var preview := preview_attack(state, actor_id, target_card_id, definitions)
		if not bool(preview.get("legal", false)):
			continue
		var reward_choices: Array[bool] = [true]
		if bool(preview.get("optional_reward", false)):
			reward_choices = [true, false]
		for claim_reward: bool in reward_choices:
			commands.append({
				"type": "ATTACK_TARGET",
				"actor_id": str(actor_id),
				"expected_revision": state.revision,
				"target_card_id": str(target_card_id),
				"claim_optional_reward": claim_reward,
				"preview": preview.duplicate(true),
			})
	return commands


static func preview_attack(
	state: GameStateData,
	actor_id: StringName,
	target_card_id: StringName,
	definitions: Dictionary
) -> Dictionary:
	var result := {
		"ok": false,
		"legal": false,
		"target_card_id": str(target_card_id),
		"requirement": 0,
		"total_combat": 0,
		"gap": 0,
		"participant_ids": [],
		"contributions": [],
		"temporary_combat": 0,
		"optional_reward": false,
	}
	var player := state.players.get(actor_id) as PlayerStateData
	if player == null:
		result["error"] = "missing_player"
		return result
	if ZoneService.find_card_zone(state, target_card_id) != SupplyService.MONSTER_ROW_ID:
		result["error"] = "target_not_in_monster_row"
		return result
	var target_card := state.cards.get(target_card_id) as Dictionary
	if target_card == null:
		result["error"] = "missing_target"
		return result
	var target_definition := definitions.get(
		StringName(target_card.get("definition_id", ""))
	) as CardDefinition
	if target_definition == null:
		result["error"] = "missing_definition"
		return result
	if target_definition.card_type != &"monster" or target_definition.combat == null:
		result["error"] = "unsupported_target_type"
		return result
	var party := state.zones.get(player.zone_ids.get(&"party", &"")) as ZoneData
	if party == null:
		result["error"] = "missing_party"
		return result
	var requirement := int(target_definition.combat)
	var total := int(player.turn_resources.get("combat", 0))
	var participants: Array[String] = []
	var contributions: Array[Dictionary] = []
	for party_index in party.card_instance_ids.size():
		if total >= requirement and not participants.is_empty():
			break
		var card_instance_id := party.card_instance_ids[party_index]
		var contribution := ResourceService.evaluate_party_member_combat(
			state, definitions, card_instance_id, party_index, party
		)
		participants.append(str(card_instance_id))
		contributions.append({
			"card_instance_id": str(card_instance_id),
			"combat": contribution,
		})
		total += contribution
	var optional_reward := false
	for effect: Dictionary in target_definition.effects:
		if StringName(effect.get("timing", "")) == &"on_defeat":
			optional_reward = optional_reward or bool(effect.get("optional", false))
	result["ok"] = true
	result["legal"] = not participants.is_empty() and total >= requirement
	result["requirement"] = requirement
	result["total_combat"] = total
	result["gap"] = maxi(0, requirement - total)
	result["participant_ids"] = participants
	result["contributions"] = contributions
	result["temporary_combat"] = int(player.turn_resources.get("combat", 0))
	result["optional_reward"] = optional_reward
	return result


static func validate(
	state: GameStateData,
	actor_id: StringName,
	command: Dictionary,
	definitions: Dictionary
) -> String:
	if state.phase != &"combat":
		return "wrong_phase"
	if not command.get("claim_optional_reward", true) is bool:
		return "invalid_reward_choice"
	var target_card_id := StringName(command.get("target_card_id", ""))
	var preview := preview_attack(state, actor_id, target_card_id, definitions)
	if not bool(preview.get("ok", false)):
		return str(preview.get("error", "combat_preview_failed"))
	if not bool(preview.get("legal", false)):
		return "insufficient_combat"
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
	var target_card_id := StringName(command.get("target_card_id", ""))
	var preview := preview_attack(state, actor_id, target_card_id, definitions)
	var participant_ids := preview.get("participant_ids", []) as Array
	events.append({
		"type": "combat_declared",
		"actor_id": str(actor_id),
		"target_card_id": str(target_card_id),
		"requirement": int(preview.get("requirement", 0)),
		"total_combat": int(preview.get("total_combat", 0)),
		"participant_ids": participant_ids.duplicate(),
	})
	var player := state.players[actor_id] as PlayerStateData
	for raw_participant_id: Variant in participant_ids:
		var departure_error := PartyService.discard_party_member_with_equipment(
			state,
			player,
			StringName(str(raw_participant_id)),
			&"combat_departure",
			events
		)
		if not departure_error.is_empty():
			return departure_error

	var target_card := state.cards[target_card_id] as Dictionary
	var target_definition := definitions.get(
		StringName(target_card.get("definition_id", ""))
	) as CardDefinition
	var claim_optional_reward := bool(command.get("claim_optional_reward", true))
	var reward_effects: Array[Dictionary] = []
	for effect: Dictionary in target_definition.effects:
		if StringName(effect.get("timing", "")) == &"on_defeat" \
				and (not bool(effect.get("optional", false)) or claim_optional_reward):
			reward_effects.append(effect)
	var effect_error := EffectResolver.resolve(state, actor_id, reward_effects, events)
	if not effect_error.is_empty():
		return effect_error
	var cycle_error := SupplyService.cycle_defeated_monster(state, target_card_id, events)
	if not cycle_error.is_empty():
		return cycle_error
	player.turn_facts[&"defeated_enemy"] = true
	player.turn_facts[&"defeated_monster_count"] = int(
		player.turn_facts.get(&"defeated_monster_count", 0)
	) + 1
	events.append({
		"type": "enemy_defeated",
		"actor_id": str(actor_id),
		"target_card_id": str(target_card_id),
		"participant_ids": participant_ids.duplicate(),
		"claimed_optional_reward": claim_optional_reward,
		"defeated_monster_count": int(player.turn_facts[&"defeated_monster_count"]),
	})
	return ""
