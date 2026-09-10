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
		"reward_summary": "",
		"returns_to_cycle": false,
		"deferred_choice": false,
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
					reward_parts.append("取得%s 1 張費用不超過 %d 的%s" % [
						source_label,
						int(effect.get("max_cost", 0)),
						filter_label,
					])
				&"roll_resource_reward":
					reward_parts.append(_dice_reward_summary(effect))
				&"draft_gain_card":
					reward_parts.append("公開等同玩家數的物資牌，從擊敗者開始依序輪抽至手牌")
	var returns_to_cycle := &"cycle_anchor" in target_definition.tags
	if not returns_to_cycle:
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
	result["contributions"] = contributions
	result["temporary_combat"] = int(player.turn_resources.get("combat", 0))
	result["optional_reward"] = optional_reward
	result["reward_summary"] = "、".join(reward_parts)
	result["returns_to_cycle"] = returns_to_cycle
	result["deferred_choice"] = deferred_choice
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
			var reward_effect := effect.duplicate(true)
			reward_effect["source_card_instance_id"] = str(target_card_id)
			reward_effects.append(reward_effect)
	var effect_error := EffectResolver.resolve(
		state, actor_id, reward_effects, events, definitions
	)
	if not effect_error.is_empty():
		return effect_error
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
	player.turn_facts[&"defeated_monster_count"] = int(
		player.turn_facts.get(&"defeated_monster_count", 0)
	) + 1
	events.append({
		"type": "enemy_defeated",
		"actor_id": str(actor_id),
		"target_card_id": str(target_card_id),
		"participant_ids": participant_ids.duplicate(),
		"claimed_optional_reward": claim_optional_reward,
		"destination": (
			str(SupplyService.MONSTER_CYCLE_ID)
			if &"cycle_anchor" in target_definition.tags
			else str(player.zone_ids[&"discard_pile"])
		),
		"defeated_monster_count": int(player.turn_facts[&"defeated_monster_count"]),
	})
	return ""


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
