class_name ActionFeatureService
extends RefCounted

# The server computes these from authoritative state, then exposes only public/own-card
# facts. CpuDecider has no reference to GameStateData or authoritative RNG.
static func project(
	state: GameStateData, actor_id: StringName, definitions: Dictionary,
	legal_commands: Array[Dictionary]
) -> Array[Dictionary]:
	var features: Array[Dictionary] = []
	var targets := _target_previews(state, actor_id, definitions)
	var boss_cost := _active_boss_cost(state, actor_id, definitions)
	var available_purchase := int(ResourceService.evaluate_player(
		state, actor_id, definitions
	).get("purchase_power", 0))
	var boss_gap := -1
	for target: Dictionary in targets:
		if target.get("target_type", "") == "boss":
			boss_gap = int(target.get("gap", 0))
			break
	for legal: Dictionary in legal_commands:
		var command := CpuCommandCodec.payload(legal)
		var card_id := StringName(command.get("card_instance_id", command.get("target_card_id", "")))
		var definition := _definition(state, card_id, definitions)
		var feature := {
			"command": command,
			"command_key": CpuCommandCodec.key(legal),
			"type": str(command.get("type", "")),
			"phase": str(state.phase),
			"target_type": str(definition.card_type) if definition != null else "",
			"printed_combat": int(definition.combat) if definition != null and definition.combat != null else 0,
			"printed_honor": int(definition.honor) if definition != null and definition.honor != null else 0,
			"printed_purchase_power": int(definition.purchase_power) if definition != null and definition.purchase_power != null else 0,
			"printed_cost": int(definition.cost) if definition != null and definition.cost != null else 0,
			"effective_cost": int(legal.get("effective_cost", 0)),
			"available_purchase_power": available_purchase,
			"recirculates_on_defeat": definition != null \
				and &"cycle_anchor" in definition.tags,
			"immediate_purchase_reward": _immediate_purchase_reward(definition),
			"boss_post_departure_cost_required": not boss_cost.is_empty(),
			"boss_post_departure_cost_available": int(boss_cost.get("available_count", 0)),
			"consumes_last_boss_cost_card": str(command.get("type", "")) == "PLAY_ADVENTURER" \
				and str(boss_cost.get("source_zone_key", "")) == "hand" \
				and str(definition.card_type) == str(boss_cost.get("card_type", "")) \
				and int(boss_cost.get("available_count", 0)) == 1 \
				if definition != null else false,
			"boss_gap_before": boss_gap,
			"boss_gap_after": boss_gap,
			"boss_gap_delta": 0,
			"combat_gain": 0,
			"boss_unlocked": false,
			"target_previews": targets.duplicate(true),
		}
		if legal.has("preview"):
			var preview := legal["preview"] as Dictionary
			feature["attack_requirement"] = int(preview.get("requirement", 0))
			feature["attack_total"] = int(preview.get("total_combat", 0))
			feature["participant_loss"] = (preview.get("participant_ids", []) as Array).size()
			feature["attack_target_type"] = str(preview.get("target_type", ""))
		if str(command.get("type", "")) in [
			"PLAY_ADVENTURER", "EQUIP_ITEM", "USE_ITEM", "ACTIVATE_EQUIPMENT_EFFECT"
		] and boss_gap >= 0 and not _can_reveal_hidden_future(definition):
			_project_combat_change(state, actor_id, definitions, command, boss_gap, feature)
		features.append(feature)
	features.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left["command_key"]) < str(right["command_key"]))
	return features


static func _active_boss_cost(
	state: GameStateData, actor_id: StringName, definitions: Dictionary
) -> Dictionary:
	var active := state.zones.get(BossService.BOSS_ACTIVE_ID) as ZoneData
	var player := state.players.get(actor_id) as PlayerStateData
	if active == null or active.card_instance_ids.is_empty() or player == null:
		return {}
	var definition := _definition(state, active.card_instance_ids[0], definitions)
	if definition == null:
		return {}
	for rule: Dictionary in definition.special_rules:
		if str(rule.get("op", "")) != "post_departure_cost":
			continue
		var source_key := StringName(rule.get("source_zone_key", "hand"))
		var required_type := StringName(rule.get("card_type", ""))
		var source := state.zones.get(player.zone_ids.get(source_key, &"")) as ZoneData
		if source == null or required_type.is_empty():
			return {}
		var available := 0
		for card_id: StringName in source.card_instance_ids:
			var candidate := _definition(state, card_id, definitions)
			if candidate != null and candidate.card_type == required_type:
				available += 1
		return {"card_type": str(required_type), "source_zone_key": str(source_key),
			"available_count": available}
	return {}


static func _immediate_purchase_reward(definition: CardDefinition) -> int:
	if definition == null:
		return 0
	var amount := 0
	for effect: Dictionary in definition.effects:
		if str(effect.get("timing", "")) == "on_defeat" \
				and str(effect.get("op", "")) == "grant_purchase_power":
			amount += int(effect.get("amount", 0))
	return amount


static func _target_previews(
	state: GameStateData, actor_id: StringName, definitions: Dictionary
) -> Array[Dictionary]:
	var previews: Array[Dictionary] = []
	for zone_id: StringName in [BossService.BOSS_ACTIVE_ID, SupplyService.MONSTER_ROW_ID]:
		var zone := state.zones.get(zone_id) as ZoneData
		if zone == null:
			continue
		for target_id: StringName in zone.card_instance_ids:
			var preview := CombatService.preview_attack(state, actor_id, target_id, definitions)
			previews.append({
				"target_card_id": str(target_id),
				"target_type": str(preview.get("target_type", "")),
				"requirement": int(preview.get("requirement", 0)),
				"total_combat": int(preview.get("total_combat", 0)),
				"gap": int(preview.get("gap", 0)),
				"legal": bool(preview.get("legal", false)),
			})
	return previews


static func _project_combat_change(
	state: GameStateData, actor_id: StringName, definitions: Dictionary,
	command: Dictionary, boss_gap: int, feature: Dictionary
) -> void:
	var outcome := RulesEngine.dispatch(state, {
		"protocol_version": 1, "game_id": str(state.game_id),
		"command_id": "feature-%d" % (state.revision + 1),
		"actor_id": str(actor_id), "expected_revision": state.revision,
		"command": command,
	}, definitions)
	if not bool(outcome.get("ok", false)):
		return
	var after := outcome["state"] as GameStateData
	var next := _target_previews(after, actor_id, definitions)
	for target: Dictionary in next:
		if target.get("target_type", "") != "boss":
			continue
		feature["boss_gap_after"] = int(target.get("gap", boss_gap))
		feature["boss_gap_delta"] = boss_gap - int(feature["boss_gap_after"])
		feature["combat_gain"] = maxi(0, int(feature["boss_gap_delta"]))
		feature["boss_unlocked"] = boss_gap > 0 and bool(target.get("legal", false))
		break


static func _definition(
	state: GameStateData, card_id: StringName, definitions: Dictionary
) -> CardDefinition:
	var value: Variant = state.cards.get(card_id)
	if not value is Dictionary:
		return null
	var card := value as Dictionary
	return definitions.get(StringName(card.get("definition_id", ""))) as CardDefinition


static func _can_reveal_hidden_future(definition: CardDefinition) -> bool:
	if definition == null:
		return false
	for effect: Dictionary in definition.effects:
		var operation := str(effect.get("op", ""))
		for hidden_keyword: String in ["draw", "deck", "shuffle", "roll", "reveal", "draft", "random"]:
			if operation.contains(hidden_keyword):
				return true
	return false
