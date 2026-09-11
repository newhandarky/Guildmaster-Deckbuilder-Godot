class_name BossService
extends RefCounted

const BOSS_DECK_ID := &"shared:boss-deck"
const BOSS_ACTIVE_ID := &"shared:boss-active"
const BOSS_RESERVE_ID := &"shared:boss-reserve"
const BOSS_ATTACHMENT_ID := &"shared:boss-attachments"
const BOSS_REMOVED_ID := &"shared:boss-removed"


static func setup(state: GameStateData, definitions: Dictionary = {}) -> void:
	var deck := ZoneData.new(BOSS_DECK_ID, &"ordered_deck", &"hidden")
	var active := ZoneData.new(BOSS_ACTIVE_ID, &"face_up_row", &"public")
	var reserve := ZoneData.new(BOSS_RESERVE_ID, &"ordered_deck", &"hidden")
	var attachments := ZoneData.new(BOSS_ATTACHMENT_ID, &"attachment", &"public")
	var removed := ZoneData.new(BOSS_REMOVED_ID, &"removed", &"public")
	for number in range(1, 12):
		var suffix := "%02d" % number
		var card_id := StringName("card-boss-%s" % suffix)
		state.cards[card_id] = {
			"instance_id": str(card_id),
			"definition_id": "base:boss/boss-%s" % suffix,
			"owner_id": "",
			"state": {"target_id": "target-boss-%s" % suffix},
		}
		reserve.card_instance_ids.append(card_id)
	var rng := DeterministicRng.new(state.seed_value, state.rng_state)
	rng.shuffle(reserve.card_instance_ids)
	var selected_count := mini(state.players.size() + 2, reserve.card_instance_ids.size())
	for _index in selected_count:
		deck.card_instance_ids.append(reserve.card_instance_ids.pop_back())
	state.rng_state = rng.get_state()
	state.zones[deck.zone_id] = deck
	state.zones[active.zone_id] = active
	state.zones[reserve.zone_id] = reserve
	state.zones[attachments.zone_id] = attachments
	state.zones[removed.zone_id] = removed
	var setup_events: Array[Dictionary] = []
	_reveal_next(state, definitions, setup_events)


static func claim_defeated_boss(
	state: GameStateData,
	card_instance_id: StringName,
	player: PlayerStateData,
	events: Array[Dictionary]
) -> String:
	if ZoneService.find_card_zone(state, card_instance_id) != BOSS_ACTIVE_ID:
		return "boss_not_active"
	var move_result := ZoneService.move_card(
		state, card_instance_id, BOSS_ACTIVE_ID, StringName(player.zone_ids[&"discard_pile"])
	)
	if not bool(move_result.get("ok", false)):
		return str(move_result.get("error", "boss_claim_failed"))
	var card := state.cards[card_instance_id] as Dictionary
	card["owner_id"] = str(player.player_id)
	var event := (move_result.get("event", {}) as Dictionary).duplicate(true)
	event["reason"] = "defeated_boss_claimed"
	events.append(event)
	var deck := state.zones[BOSS_DECK_ID] as ZoneData
	if deck.card_instance_ids.is_empty():
		(state.zones[BOSS_ACTIVE_ID] as ZoneData).metadata["all_bosses_defeated"] = true
	else:
		(state.zones[BOSS_ACTIVE_ID] as ZoneData).metadata["pending_reveal"] = true
	return ""


static func complete_defeat(
	state: GameStateData,
	actor_id: StringName,
	completion: Dictionary,
	events: Array[Dictionary],
	definitions: Dictionary
) -> String:
	if StringName(completion.get("actor_id", "")) != actor_id:
		return "boss_completion_actor_mismatch"
	var target_card_id := StringName(completion.get("target_card_id", ""))
	if ZoneService.find_card_zone(state, target_card_id) != BOSS_ACTIVE_ID:
		return "boss_not_active"
	var player := state.players.get(actor_id) as PlayerStateData
	var target_card := state.cards.get(target_card_id) as Dictionary
	var definition := definitions.get(
		StringName(target_card.get("definition_id", "")) if target_card != null else &""
	) as CardDefinition
	if player == null or target_card == null or definition == null:
		return "missing_boss_completion_data"
	var attachment_error := _resolve_defeated_attachments(
		state, actor_id, target_card_id, definition, events, definitions
	)
	if not attachment_error.is_empty():
		return attachment_error
	var claim_error := claim_defeated_boss(state, target_card_id, player, events)
	if not claim_error.is_empty():
		return claim_error
	player.turn_facts[&"defeated_enemy"] = true
	player.turn_facts[&"defeated_boss_count"] = int(
		player.turn_facts.get(&"defeated_boss_count", 0)
	) + 1
	player.counters[&"defeated_boss_count"] = int(
		player.counters.get(&"defeated_boss_count", 0)
	) + 1
	var participant_ids := (completion.get("participant_ids", []) as Array).duplicate()
	events.append({
		"type": "boss_defeated", "actor_id": str(actor_id),
		"target_card_id": str(target_card_id), "participant_ids": participant_ids,
		"defeated_boss_count": int(player.counters[&"defeated_boss_count"]),
	})
	var active := state.zones[BOSS_ACTIVE_ID] as ZoneData
	if bool(active.metadata.get("all_bosses_defeated", false)):
		events.append({"type": "all_bosses_defeated", "actor_id": str(actor_id)})
	else:
		events.append({"type": "boss_reveal_deferred", "phase": "rest"})
	events.append({
		"type": "enemy_defeated", "actor_id": str(actor_id),
		"target_card_id": str(target_card_id), "target_type": "boss",
		"participant_ids": participant_ids,
		"claimed_optional_reward": bool(completion.get("claim_optional_reward", true)),
		"destination": str(player.zone_ids[&"discard_pile"]),
		"defeated_count": int(player.turn_facts[&"defeated_boss_count"]),
		"defeated_monster_count": int(player.turn_facts.get(&"defeated_monster_count", 0)),
	})
	return ""


static func continue_defeat_after_choice(
	state: GameStateData,
	actor_id: StringName,
	completion: Dictionary,
	events: Array[Dictionary],
	definitions: Dictionary
) -> String:
	var remaining_effects: Array[Dictionary] = []
	for raw_effect: Variant in completion.get("remaining_effects", []):
		if raw_effect is Dictionary:
			remaining_effects.append((raw_effect as Dictionary).duplicate(true))
	completion["remaining_effects"] = []
	if not remaining_effects.is_empty():
		var effect_error := EffectResolver.resolve(
			state, actor_id, remaining_effects, events, definitions
		)
		if not effect_error.is_empty():
			return effect_error
		if not state.effect_state.is_empty():
			state.effect_state["boss_completion"] = completion.duplicate(true)
			return ""
	return complete_defeat(state, actor_id, completion, events, definitions)


static func reveal_pending(
	state: GameStateData, events: Array[Dictionary], definitions: Dictionary = {}
) -> String:
	var active := state.zones.get(BOSS_ACTIVE_ID) as ZoneData
	if active == null:
		return "missing_boss_active_zone"
	if not active.card_instance_ids.is_empty() or not bool(active.metadata.get("pending_reveal", false)):
		return ""
	var deck := state.zones.get(BOSS_DECK_ID) as ZoneData
	if deck == null or deck.card_instance_ids.is_empty():
		return "boss_deck_empty_during_pending_reveal"
	active.metadata.erase("pending_reveal")
	var card_id := _reveal_next(state, definitions, events)
	if card_id.is_empty():
		return "boss_reveal_failed"
	return ""


static func _reveal_next(
	state: GameStateData,
	definitions: Dictionary = {},
	events: Array[Dictionary] = []
) -> StringName:
	var deck := state.zones.get(BOSS_DECK_ID) as ZoneData
	var active := state.zones.get(BOSS_ACTIVE_ID) as ZoneData
	if deck == null or active == null or deck.card_instance_ids.is_empty():
		return &""
	var card_id: StringName = deck.card_instance_ids.back()
	var move_result := ZoneService.move_card(state, card_id, BOSS_DECK_ID, BOSS_ACTIVE_ID)
	if not bool(move_result.get("ok", false)):
		return &""
	events.append({
		"type": "boss_revealed", "card_instance_id": str(card_id),
		"remaining_in_deck": deck.card_instance_ids.size(),
	})
	if not definitions.is_empty():
		var reveal_error := _apply_reveal_rules(state, card_id, definitions, events)
		if not reveal_error.is_empty():
			return &""
	return card_id


static func _apply_reveal_rules(
	state: GameStateData,
	boss_card_id: StringName,
	definitions: Dictionary,
	events: Array[Dictionary]
) -> String:
	var boss_card := state.cards[boss_card_id] as Dictionary
	var definition := definitions.get(StringName(boss_card.get("definition_id", ""))) as CardDefinition
	if definition == null:
		return "missing_boss_definition"
	for rule: Dictionary in definition.special_rules:
		if StringName(rule.get("op", "")) != &"attach_on_reveal":
			continue
		var source_zone_id := StringName(rule.get("source_zone_id", ""))
		var source := state.zones.get(source_zone_id) as ZoneData
		var attachment_zone := state.zones.get(BOSS_ATTACHMENT_ID) as ZoneData
		if source == null or attachment_zone == null:
			return "missing_boss_attachment_zone"
		if source.card_instance_ids.is_empty():
			events.append({"type": "boss_attachment_skipped", "boss_card_id": str(boss_card_id), "source_zone_id": str(source_zone_id)})
			continue
		var attachment_id: StringName = source.card_instance_ids.back()
		var move_result := ZoneService.move_card(
			state, attachment_id, source_zone_id, BOSS_ATTACHMENT_ID
		)
		if not bool(move_result.get("ok", false)):
			return str(move_result.get("error", "boss_attachment_failed"))
		var boss_state := boss_card.get("state", {}) as Dictionary
		var attachment_ids := boss_state.get("attachment_ids", []) as Array
		attachment_ids.append(str(attachment_id))
		boss_state["attachment_ids"] = attachment_ids
		boss_card["state"] = boss_state
		var attachment_card := state.cards[attachment_id] as Dictionary
		var attachment_state := attachment_card.get("state", {}) as Dictionary
		attachment_state["attached_to"] = str(boss_card_id)
		attachment_card["state"] = attachment_state
		var event := (move_result.get("event", {}) as Dictionary).duplicate(true)
		event["reason"] = "boss_attachment_revealed"
		event["boss_card_id"] = str(boss_card_id)
		events.append(event)
	return ""


static func _resolve_defeated_attachments(
	state: GameStateData,
	actor_id: StringName,
	boss_card_id: StringName,
	definition: CardDefinition,
	events: Array[Dictionary],
	definitions: Dictionary
) -> String:
	var boss_card := state.cards[boss_card_id] as Dictionary
	var boss_state := boss_card.get("state", {}) as Dictionary
	var attachment_ids := boss_state.get("attachment_ids", []) as Array
	var destination_rule := &"removed"
	for rule: Dictionary in definition.special_rules:
		if StringName(rule.get("op", "")) == &"attach_on_reveal":
			destination_rule = StringName(rule.get("defeat_destination", "removed"))
	for raw_attachment_id: Variant in attachment_ids.duplicate():
		var attachment_id := StringName(str(raw_attachment_id))
		if ZoneService.find_card_zone(state, attachment_id) != BOSS_ATTACHMENT_ID:
			return "boss_attachment_moved"
		var attachment_card := state.cards[attachment_id] as Dictionary
		var attachment_state := attachment_card.get("state", {}) as Dictionary
		if StringName(attachment_state.get("attached_to", "")) != boss_card_id:
			return "boss_attachment_link_broken"
		attachment_state.erase("attached_to")
		attachment_card["state"] = attachment_state
		var attachment_definition := definitions.get(
			StringName(attachment_card.get("definition_id", ""))
		) as CardDefinition
		var destination_zone_id := BOSS_REMOVED_ID
		var insertion_index := -1
		if destination_rule == &"owner_discard":
			destination_zone_id = StringName((state.players[actor_id] as PlayerStateData).zone_ids[&"discard_pile"])
			attachment_card["owner_id"] = str(actor_id)
		elif attachment_definition != null and &"cycle_anchor" in attachment_definition.tags:
			destination_zone_id = SupplyService.MONSTER_CYCLE_ID
			insertion_index = 0
		var move_result := ZoneService.move_card(
			state, attachment_id, BOSS_ATTACHMENT_ID, destination_zone_id, insertion_index
		)
		if not bool(move_result.get("ok", false)):
			return str(move_result.get("error", "boss_attachment_departure_failed"))
		var event := (move_result.get("event", {}) as Dictionary).duplicate(true)
		event["reason"] = "boss_attachment_departure"
		event["boss_card_id"] = str(boss_card_id)
		events.append(event)
	boss_state["attachment_ids"] = []
	boss_card["state"] = boss_state
	return ""
