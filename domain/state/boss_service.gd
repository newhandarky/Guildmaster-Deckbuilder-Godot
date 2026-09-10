class_name BossService
extends RefCounted

const BOSS_DECK_ID := &"shared:boss-deck"
const BOSS_ACTIVE_ID := &"shared:boss-active"
const BOSS_RESERVE_ID := &"shared:boss-reserve"


static func setup(state: GameStateData) -> void:
	var deck := ZoneData.new(BOSS_DECK_ID, &"ordered_deck", &"hidden")
	var active := ZoneData.new(BOSS_ACTIVE_ID, &"face_up_row", &"public")
	var reserve := ZoneData.new(BOSS_RESERVE_ID, &"ordered_deck", &"hidden")
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
	_reveal_without_event(state)


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


static func reveal_pending(state: GameStateData, events: Array[Dictionary]) -> String:
	var active := state.zones.get(BOSS_ACTIVE_ID) as ZoneData
	if active == null:
		return "missing_boss_active_zone"
	if not active.card_instance_ids.is_empty() or not bool(active.metadata.get("pending_reveal", false)):
		return ""
	var deck := state.zones.get(BOSS_DECK_ID) as ZoneData
	if deck == null or deck.card_instance_ids.is_empty():
		return "boss_deck_empty_during_pending_reveal"
	active.metadata.erase("pending_reveal")
	var card_id := _reveal_without_event(state)
	if card_id.is_empty():
		return "boss_reveal_failed"
	events.append({
		"type": "boss_revealed",
		"card_instance_id": str(card_id),
		"remaining_in_deck": deck.card_instance_ids.size(),
	})
	return ""


static func _reveal_without_event(state: GameStateData) -> StringName:
	var deck := state.zones.get(BOSS_DECK_ID) as ZoneData
	var active := state.zones.get(BOSS_ACTIVE_ID) as ZoneData
	if deck == null or active == null or deck.card_instance_ids.is_empty():
		return &""
	var card_id: StringName = deck.card_instance_ids.back()
	var move_result := ZoneService.move_card(state, card_id, BOSS_DECK_ID, BOSS_ACTIVE_ID)
	return card_id if bool(move_result.get("ok", false)) else &""
