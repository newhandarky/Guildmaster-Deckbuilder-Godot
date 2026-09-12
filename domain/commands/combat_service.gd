class_name CombatService
extends RefCounted

const BossServiceType = preload("res://domain/state/boss_service.gd")
const BossRuleEvaluatorType = preload("res://domain/rules/boss_rule_evaluator.gd")


static func get_legal_commands(
	state: GameStateData,
	actor_id: StringName,
	definitions: Dictionary
) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	if state.phase != &"combat":
		return commands
	var target_ids: Array[StringName] = []
	for zone_id: StringName in [BossServiceType.BOSS_ACTIVE_ID, SupplyService.MONSTER_ROW_ID]:
		var row := state.zones.get(zone_id) as ZoneData
		if row != null:
			target_ids.append_array(row.card_instance_ids)
	for target_card_id: StringName in target_ids:
		var preview := preview_attack(state, actor_id, target_card_id, definitions)
		if not bool(preview.get("legal", false)):
			continue
		var reward_choices: Array[bool] = [true]
		if bool(preview.get("optional_reward", false)):
			reward_choices = [true, false]
		var departure_choices: Array[bool] = [true]
		if bool(preview.get("optional_departure", false)):
			departure_choices.append(false)
		for claim_reward: bool in reward_choices:
			for use_departure: bool in departure_choices:
				commands.append({
				"type": "ATTACK_TARGET",
				"actor_id": str(actor_id),
				"expected_revision": state.revision,
				"target_card_id": str(target_card_id),
				"claim_optional_reward": claim_reward,
				"use_optional_departures": use_departure,
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
		"optional_departure": false,
		"reward_summary": "",
		"returns_to_cycle": false,
		"deferred_choice": false,
		"target_type": "",
		"equipment_suppressed": false,
		"requirement_modifiers": [],
	}
	var player := state.players.get(actor_id) as PlayerStateData
	if player == null:
		result["error"] = "missing_player"
		return result
	var target_zone_id := ZoneService.find_card_zone(state, target_card_id)
	if target_zone_id not in [SupplyService.MONSTER_ROW_ID, BossServiceType.BOSS_ACTIVE_ID]:
		result["error"] = "target_not_in_enemy_zone"
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
	if target_definition.card_type not in [&"monster", &"boss"] or target_definition.combat == null:
		result["error"] = "unsupported_target_type"
		return result
	if target_definition.card_type == &"boss" and not target_definition.framework_ready:
		result["error"] = "boss_rules_not_implemented"
		result["target_type"] = "boss"
		result["reward_summary"] = target_definition.reward_text
		return result
	var party := state.zones.get(player.zone_ids.get(&"party", &"")) as ZoneData
	if party == null:
		result["error"] = "missing_party"
		return result
	var target_rules := {
		"requirement": int(target_definition.combat),
		"participant_limit": -1,
		"equipment_suppressed": false,
		"modifiers": [],
	}
	if target_definition.card_type == &"boss":
		target_rules = BossRuleEvaluatorType.evaluate(state, actor_id, target_definition, definitions)
	var requirement := maxi(0, int(target_rules["requirement"]) + int(
		(player.turn_bonuses.get("target_combat_modifiers", {}) as Dictionary).get(str(target_card_id), 0)
	))
	var total := int(player.turn_resources.get("combat", 0))
	var participants: Array[String] = []
	var contributions: Array[Dictionary] = []
	for party_index in party.card_instance_ids.size():
		if int(target_rules["participant_limit"]) >= 0 \
				and participants.size() >= int(target_rules["participant_limit"]):
			break
		if total >= requirement and not participants.is_empty():
			break
		var card_instance_id := party.card_instance_ids[party_index]
		var contribution := ResourceService.evaluate_party_member_combat(
			state,
			definitions,
			card_instance_id,
			party_index,
			party,
			not bool(target_rules["equipment_suppressed"]),
			target_definition.card_type
		)
		participants.append(str(card_instance_id))
		contributions.append({
			"card_instance_id": str(card_instance_id),
			"combat": contribution,
		})
		total += contribution
	var optional_reward := false
	var deferred_choice := false
	var reward_parts: Array[String] = []
	for effect: Dictionary in target_definition.effects:
		if StringName(effect.get("timing", "")) == &"on_defeat":
			var operation := StringName(effect.get("op", ""))
			if operation in [&"choose_remove_card", &"choose_gain_card", &"draft_gain_card"]:
				deferred_choice = true
			else:
				optional_reward = optional_reward or bool(effect.get("optional", false))
			match operation:
				&"grant_purchase_power":
					reward_parts.append("+%d 購買力" % int(effect.get("amount", 0)))
				&"draw":
					reward_parts.append("抽 %d 張" % int(effect.get("amount", 0)))
				&"discard_hand_and_draw":
					reward_parts.append("可棄掉全部手牌，再抽相同張數")
				&"choose_remove_card":
					var source_labels: Array[String] = []
					var removal_sources := _removal_source_zone_keys(effect)
					for raw_source: Variant in removal_sources:
						var source_key := StringName(str(raw_source))
						source_labels.append(
							_source_zone_label(source_key)
							if removal_sources.size() == 1
							else _short_source_zone_label(source_key)
						)
					var removal_amount := int(effect.get("amount", 0))
					reward_parts.append("可從%s移除%s" % [
						_join_labels_with_or(source_labels),
						" 1 張" if removal_amount == 1 else "最多 %d 張" % removal_amount,
					])
				&"choose_gain_card":
					var source_zone_id := StringName(effect.get("source_zone_id", ""))
					var source_label := (
						"招募區" if source_zone_id == SupplyService.RECRUIT_ROW_ID else "商店"
					)
					var card_types := effect.get("allowed_card_types", []) as Array
					var filter_label := "冒險者" if card_types == ["adventurer"] else "道具或裝備"
					reward_parts.append("取得%s %d 張費用不超過 %d 的%s" % [
						source_label,
						int(effect.get("amount", 1)),
						int(effect.get("max_cost", 0)),
						filter_label,
					])
				&"roll_resource_reward":
					reward_parts.append(_dice_reward_summary(effect))
				&"draft_gain_card":
					reward_parts.append("公開等同玩家數的物資牌，從擊敗者開始依序輪抽至手牌")
	if target_definition.card_type == &"boss" and not target_definition.reward_text.is_empty():
		reward_parts.assign([target_definition.reward_text])
	var returns_to_cycle := &"cycle_anchor" in target_definition.tags
	if target_definition.card_type == &"monster" and not returns_to_cycle:
		reward_parts.append("取得此卡（購買力 %s／榮譽 %s）" % [
			_printed_label(target_definition.purchase_power),
			_printed_label(target_definition.honor),
		])
	result["ok"] = true
	result["legal"] = not participants.is_empty() and total >= requirement
	result["requirement"] = requirement
	result["total_combat"] = total
	result["gap"] = maxi(0, requirement - total)
	result["participant_ids"] = participants
	for raw_participant_id: Variant in participants:
		if not _adventurer_departure_replacement(
			state, StringName(str(raw_participant_id)), definitions
		).is_empty():
			result["optional_departure"] = true
			break
	result["contributions"] = contributions
	result["temporary_combat"] = int(player.turn_resources.get("combat", 0))
	result["optional_reward"] = optional_reward
	result["reward_summary"] = "、".join(reward_parts)
	result["returns_to_cycle"] = returns_to_cycle
	result["deferred_choice"] = deferred_choice
	result["target_type"] = str(target_definition.card_type)
	result["equipment_suppressed"] = bool(target_rules["equipment_suppressed"])
	result["requirement_modifiers"] = (target_rules["modifiers"] as Array).duplicate(true)
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
	if not command.get("use_optional_departures", true) is bool:
		return "invalid_departure_choice"
	var target_card_id := StringName(command.get("target_card_id", ""))
	var preview := preview_attack(state, actor_id, target_card_id, definitions)
	if not bool(preview.get("ok", false)):
		return str(preview.get("error", "combat_preview_failed"))
	if not bool(preview.get("legal", false)):
		return "insufficient_combat"
	if not bool(preview.get("optional_reward", false)) \
			and not bool(command.get("claim_optional_reward", true)):
		return "reward_not_optional"
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
	var departed_this_turn := player.turn_facts.get("combat_participant_ids", []) as Array
	for raw_participant_id: Variant in participant_ids:
		if str(raw_participant_id) not in departed_this_turn:
			departed_this_turn.append(str(raw_participant_id))
	player.turn_facts["combat_participant_ids"] = departed_this_turn
	var target_card := state.cards[target_card_id] as Dictionary
	var target_definition := definitions.get(
		StringName(target_card.get("definition_id", ""))
	) as CardDefinition
	var departure_error := _apply_combat_departures(
		state, player, participant_ids, target_definition, definitions, events,
		bool(command.get("use_optional_departures", true))
	)
	if not departure_error.is_empty():
		return departure_error
	_clear_per_attack_equipment_effects(player, events)
	var claim_optional_reward := bool(command.get("claim_optional_reward", true))
	var reward_effects: Array[Dictionary] = []
	for effect: Dictionary in target_definition.effects:
		if StringName(effect.get("timing", "")) == &"on_defeat" \
				and (not bool(effect.get("optional", false)) or claim_optional_reward):
			var reward_effect := effect.duplicate(true)
			reward_effect["source_card_instance_id"] = str(target_card_id)
			reward_effect["participant_count"] = participant_ids.size()
			reward_effects.append(reward_effect)
	var completion := {
		"actor_id": str(actor_id),
		"target_card_id": str(target_card_id),
		"participant_ids": participant_ids.duplicate(),
		"claim_optional_reward": claim_optional_reward,
		"remaining_effects": [],
	}
	if target_definition.card_type == &"boss" and _has_boss_rule(
		target_definition, &"post_departure_cost"
	):
		return _request_post_departure_cost(
			state, actor_id, target_card_id, target_definition, reward_effects,
			completion, events, definitions
		)
	var effect_error := EffectResolver.resolve(
		state, actor_id, reward_effects, events, definitions
	)
	if not effect_error.is_empty():
		return effect_error
	if target_definition.card_type == &"boss":
		if not state.effect_state.is_empty():
			state.effect_state["boss_completion"] = completion.duplicate(true)
			events.append({
				"type": "boss_reward_pending", "actor_id": str(actor_id),
				"target_card_id": str(target_card_id),
				"choice_id": str(state.effect_state.get("choice_id", "")),
			})
			return ""
		return BossServiceType.complete_defeat(
			state, actor_id, completion, events, definitions
		)
	var supply_error: String
	if &"cycle_anchor" in target_definition.tags:
		supply_error = SupplyService.cycle_defeated_monster(state, target_card_id, events)
	else:
		supply_error = SupplyService.claim_defeated_monster(
			state, target_card_id, player, events
		)
	if not supply_error.is_empty():
		return supply_error
	player.turn_facts[&"defeated_enemy"] = true
	var counter_key := &"defeated_monster_count"
	player.turn_facts[counter_key] = int(player.turn_facts.get(counter_key, 0)) + 1
	var defeat_trigger_error := EffectResolver.resolve_party_trigger(
		state, actor_id, &"on_enemy_defeated_if_attached", events, definitions
	)
	if not defeat_trigger_error.is_empty():
		return defeat_trigger_error
	events.append({
		"type": "enemy_defeated",
		"actor_id": str(actor_id),
		"target_card_id": str(target_card_id),
		"participant_ids": participant_ids.duplicate(),
		"claimed_optional_reward": claim_optional_reward,
		"target_type": str(target_definition.card_type),
		"destination": str(SupplyService.MONSTER_CYCLE_ID) \
			if &"cycle_anchor" in target_definition.tags \
			else str(player.zone_ids[&"discard_pile"]),
		"defeated_count": int(player.turn_facts[counter_key]),
		"defeated_monster_count": int(player.turn_facts.get(&"defeated_monster_count", 0)),
	})
	return ""


static func _clear_per_attack_equipment_effects(
	player: PlayerStateData, events: Array[Dictionary]
) -> void:
	var attack_modifiers := player.turn_bonuses.get("equipment_attack_modifiers", {}) as Dictionary
	var card_modifiers := player.turn_bonuses.get("card_combat_modifiers", {}) as Dictionary
	for equipment_id: Variant in attack_modifiers:
		var record := attack_modifiers[equipment_id] as Dictionary
		var target_card_id := str(record.get("target_card_id", ""))
		card_modifiers[target_card_id] = int(card_modifiers.get(target_card_id, 0)) - int(record.get("amount", 0))
		if int(card_modifiers[target_card_id]) == 0:
			card_modifiers.erase(target_card_id)
		player.turn_facts.erase("equipment_attack_used:%s" % equipment_id)
		events.append({"type":"equipment_attack_modifier_expired","actor_id":str(player.player_id),"equipment_id":str(equipment_id),"target_card_id":target_card_id})
	player.turn_bonuses["card_combat_modifiers"] = card_modifiers
	player.turn_bonuses.erase("equipment_attack_modifiers")


static func _apply_combat_departures(
	state: GameStateData,
	player: PlayerStateData,
	participant_ids: Array,
	target_definition: CardDefinition,
	definitions: Dictionary,
	events: Array[Dictionary],
	use_optional_departures: bool = true
) -> String:
	var replacement_rule: Dictionary = {}
	if target_definition.card_type == &"boss":
		for rule: Dictionary in target_definition.special_rules:
			if StringName(rule.get("op", "")) == &"replace_combat_departure":
				replacement_rule = rule
	var returned_to_supply := false
	for raw_participant_id: Variant in participant_ids:
		var participant_id := StringName(str(raw_participant_id))
		var adventurer_replacement := _adventurer_departure_replacement(
			state, participant_id, definitions
		)
		if use_optional_departures and not adventurer_replacement.is_empty():
			var replacement_error := _apply_adventurer_departure_replacement(
				state, player, participant_id, adventurer_replacement, definitions, events
			)
			if not replacement_error.is_empty():
				return replacement_error
			continue
		if replacement_rule.is_empty():
			var error := PartyService.discard_party_member_with_equipment(
				state, player, participant_id, &"combat_departure", events, definitions
			)
			if not error.is_empty():
				return error
			continue
		var card := state.cards[participant_id] as Dictionary
		var definition := definitions.get(StringName(card.get("definition_id", ""))) as CardDefinition
		var is_starter := definition != null and &"starter" in definition.tags
		var destination_zone_id := _departure_destination_zone_id(
			replacement_rule, player, is_starter
		)
		var equipment_destination_zone_id := StringName(player.zone_ids.get(
			StringName(replacement_rule.get("equipment_destination_zone_key", "discard_pile")), &""
		))
		if destination_zone_id.is_empty() or not state.zones.has(destination_zone_id) \
				or equipment_destination_zone_id.is_empty() \
				or not state.zones.has(equipment_destination_zone_id):
			return "Boss departure replacement references an invalid destination"
		var error := PartyService.move_party_member_with_equipment(
			state, player, participant_id, destination_zone_id,
			equipment_destination_zone_id,
			&"boss_combat_departure_replaced", events, definitions
		)
		if not error.is_empty():
			return error
		if destination_zone_id not in player.zone_ids.values():
			card["owner_id"] = ""
			returned_to_supply = true
	if returned_to_supply and bool(replacement_rule.get("shuffle_destination", false)):
		var deck_id := StringName(replacement_rule.get("destination_zone_id", ""))
		var deck := state.zones.get(deck_id) as ZoneData
		if deck == null or deck.kind != &"ordered_deck":
			return "Boss departure shuffle destination must be an ordered deck"
		deck.metadata.erase("depletion_announced")
		var rng := DeterministicRng.new(state.seed_value, state.rng_state)
		rng.shuffle(deck.card_instance_ids)
		state.rng_state = rng.get_state()
		events.append({
			"type": "supply_deck_shuffled", "zone_id": str(deck.zone_id),
			"reason": "boss_departure_replacement", "card_count": deck.card_instance_ids.size(),
		})
	return PartyService.enforce_position_departures(state, player, definitions, events)


static func _adventurer_departure_replacement(
	state: GameStateData,
	participant_id: StringName,
	definitions: Dictionary
) -> Dictionary:
	var card := state.cards.get(participant_id) as Dictionary
	var definition := definitions.get(
		StringName(card.get("definition_id", "")) if card != null else &""
	) as CardDefinition
	if definition == null:
		return {}
	for effect: Dictionary in definition.effects:
		if StringName(effect.get("op", "")) != &"combat_departure_replacement":
			continue
		var allowed_attachment_types: Array[StringName] = []
		for raw_type: Variant in effect.get("attachment_card_types", []):
			allowed_attachment_types.append(StringName(str(raw_type)))
		if allowed_attachment_types.is_empty():
			return effect
		var card_state := card.get("state", {}) as Dictionary
		for raw_attachment_id: Variant in card_state.get("equipment_ids", []):
			var attachment := state.cards.get(StringName(str(raw_attachment_id))) as Dictionary
			var attachment_definition := definitions.get(
				StringName(attachment.get("definition_id", "")) if attachment != null else &""
			) as CardDefinition
			if attachment_definition != null and attachment_definition.card_type in allowed_attachment_types:
				var result := effect.duplicate(true)
				result["replacement_attachment_id"] = str(raw_attachment_id)
				return result
	return {}


static func _apply_adventurer_departure_replacement(
	state: GameStateData,
	player: PlayerStateData,
	participant_id: StringName,
	effect: Dictionary,
	definitions: Dictionary,
	events: Array[Dictionary]
) -> String:
	var attachment_id := StringName(effect.get("replacement_attachment_id", ""))
	if not attachment_id.is_empty():
		var detach_error := PartyService.detach_equipment(
			state, player, participant_id, attachment_id,
			StringName(player.zone_ids.get(
				StringName(effect.get("attachment_destination_zone_key", "discard_pile")), &""
			)), &"combat_departure_replaced", events
		)
		if not detach_error.is_empty():
			return detach_error
	else:
		var destination_zone_id := StringName(player.zone_ids.get(
			StringName(effect.get("source_destination_zone_key", "discard_pile")), &""
		))
		var equipment_destination_zone_id := StringName(player.zone_ids.get(
			StringName(effect.get("equipment_destination_zone_key", "discard_pile")), &""
		))
		var move_error := PartyService.move_party_member_with_equipment(
			state, player, participant_id, destination_zone_id,
			equipment_destination_zone_id, &"combat_departure_replaced", events, definitions
		)
		if not move_error.is_empty():
			return move_error
	events.append({
		"type": "combat_departure_replaced", "actor_id": str(player.player_id),
		"card_instance_id": str(participant_id),
		"attachment_card_instance_id": str(attachment_id),
		"source_effect": effect.duplicate(true),
	})
	return ""


static func _departure_destination_zone_id(
	rule: Dictionary, player: PlayerStateData, is_starter: bool
) -> StringName:
	if is_starter:
		return StringName(player.zone_ids.get(
			StringName(rule.get("starter_destination_zone_key", "")), &""
		))
	if rule.has("destination_zone_id"):
		return StringName(rule.get("destination_zone_id", ""))
	return StringName(player.zone_ids.get(
		StringName(rule.get("destination_zone_key", "")), &""
	))


static func _request_post_departure_cost(
	state: GameStateData,
	actor_id: StringName,
	target_card_id: StringName,
	target_definition: CardDefinition,
	reward_effects: Array[Dictionary],
	completion: Dictionary,
	events: Array[Dictionary],
	definitions: Dictionary
) -> String:
	var player := state.players[actor_id] as PlayerStateData
	var cost_rule: Dictionary = {}
	for rule: Dictionary in target_definition.special_rules:
		if StringName(rule.get("op", "")) == &"post_departure_cost":
			cost_rule = rule
			break
	var source_zone_key := StringName(cost_rule.get("source_zone_key", "hand"))
	var destination_zone_key := StringName(cost_rule.get("destination_zone_key", "discard_pile"))
	var required_card_type := StringName(cost_rule.get("card_type", ""))
	var hand := state.zones.get(StringName(player.zone_ids.get(source_zone_key, &""))) as ZoneData
	if hand == null or required_card_type.is_empty() \
			or not player.zone_ids.has(destination_zone_key):
		return "Post-departure cost rule is invalid"
	var eligible_ids: Array[String] = []
	for card_id: StringName in hand.card_instance_ids:
		var card := state.cards[card_id] as Dictionary
		var definition := definitions.get(StringName(card.get("definition_id", ""))) as CardDefinition
		if definition != null and definition.card_type == required_card_type:
			eligible_ids.append(str(card_id))
	if eligible_ids.is_empty():
		events.append({
			"type": "boss_attack_failed", "actor_id": str(actor_id),
			"target_card_id": str(target_card_id),
			"reason": "post_departure_cost_unpayable",
			"participant_ids": (completion.get("participant_ids", []) as Array).duplicate(),
		})
		return ""
	completion["remaining_effects"] = reward_effects.duplicate(true)
	state.effect_state = {
		"type": "pending_choice", "choice_id": "choice-%06d" % (state.revision + 1),
		"actor_id": str(actor_id), "required_actor_id": str(actor_id),
		"op": "pay_post_departure_cost",
		"prompt": str(cost_rule.get("prompt", "支付討伐所需代價")),
		"source_zone_id": str(hand.zone_id), "source_zone_key": str(source_zone_key),
		"destination_zone_id": str(player.zone_ids[destination_zone_key]),
		"eligible_card_ids": eligible_ids, "selected_card_ids": [], "selected_count": 0,
		"min_selections": 1, "max_selections": 1, "required_card_type": str(required_card_type),
		"source_card_instance_id": str(target_card_id),
		"source_rule": cost_rule.duplicate(true),
		"boss_completion": completion.duplicate(true),
	}
	events.append({
		"type": "choice_requested", "choice_id": str(state.effect_state["choice_id"]),
		"actor_id": str(actor_id), "required_actor_id": str(actor_id),
		"op": "pay_post_departure_cost", "eligible_card_ids": eligible_ids,
		"optional": false, "source_card_instance_id": str(target_card_id),
	})
	return ""


static func _has_boss_rule(definition: CardDefinition, operation: StringName) -> bool:
	for rule: Dictionary in definition.special_rules:
		if StringName(rule.get("op", "")) == operation:
			return true
	return false


static func _printed_label(value: Variant) -> String:
	return "—" if value == null else str(int(value))


static func _source_zone_label(source_zone_key: StringName) -> String:
	return {
		&"hand": "手牌",
		&"party": "隊伍",
		&"discard_pile": "自己的棄牌堆",
	}.get(source_zone_key, str(source_zone_key))


static func _removal_source_zone_keys(effect: Dictionary) -> Array:
	var source_zone_keys := effect.get("source_zone_keys", []) as Array
	if not source_zone_keys.is_empty():
		return source_zone_keys
	return [str(effect.get("source_zone_key", ""))]


static func _short_source_zone_label(source_zone_key: StringName) -> String:
	return {
		&"hand": "手牌",
		&"party": "隊伍",
		&"discard_pile": "棄牌堆",
	}.get(source_zone_key, str(source_zone_key))


static func _join_labels_with_or(labels: Array[String]) -> String:
	if labels.size() < 2:
		return "" if labels.is_empty() else labels[0]
	return "%s或%s" % ["、".join(labels.slice(0, -1)), labels.back()]


static func _dice_reward_summary(effect: Dictionary) -> String:
	var sides := int(effect.get("die_sides", 0))
	var divisor := int(effect.get("divisor", 1))
	var resource_label: String = {
		&"purchase_power": "購買力",
		&"combat": "戰力",
	}.get(StringName(effect.get("resource", "")), str(effect.get("resource", "資源")))
	var groups: Array[String] = []
	var group_start := 1
	var previous_amount := 1
	for face in range(2, sides + 2):
		var amount: int = int((face + divisor - 1) / divisor) if face <= sides else -1
		if amount == previous_amount:
			continue
		var face_label := (
			str(group_start)
			if group_start == face - 1
			else "%d／%d" % [group_start, face - 1]
		)
		groups.append("%s → %d" % [face_label, previous_amount])
		group_start = face
		previous_amount = amount
	return "擲 1 顆 D%d：%s %s" % [sides, "、".join(groups), resource_label]
