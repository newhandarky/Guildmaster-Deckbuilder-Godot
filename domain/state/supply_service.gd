class_name SupplyService
extends RefCounted

const BossServiceType = preload("res://domain/state/boss_service.gd")

const RECRUIT_DECK_ID := &"shared:adventurer-supply"
const RECRUIT_ROW_ID := &"shared:recruit-row"
const SHOP_DECK_ID := &"shared:resource-supply"
const SHOP_ROW_ID := &"shared:shop-row"
const RESOURCE_DRAFT_ROW_ID := &"shared:resource-draft-row"
const MONSTER_CYCLE_ID := &"shared:monster-cycle"
const MONSTER_ROW_ID := &"shared:monster-row"
const ROW_SIZE := 3
const MONSTER_ROW_SIZE := 3


static func refill_vertical_slice_rows(state: GameStateData, events: Array[Dictionary]) -> String:
	for pair: Array in [
		[RECRUIT_DECK_ID, RECRUIT_ROW_ID],
		[SHOP_DECK_ID, SHOP_ROW_ID],
	]:
		var error := refill_row(state, pair[0], pair[1], ROW_SIZE, events)
		if not error.is_empty():
			return error
	var boss_error: String = BossServiceType.reveal_pending(state, events)
	if not boss_error.is_empty():
		return boss_error
	return ""


static func refill_row(
	state: GameStateData,
	deck_zone_id: StringName,
	row_zone_id: StringName,
	target_size: int,
	events: Array[Dictionary],
	announce_depletion: bool = true
) -> String:
	var deck := state.zones.get(deck_zone_id) as ZoneData
	var row := state.zones.get(row_zone_id) as ZoneData
	if deck == null or row == null:
		return "missing_supply_zone"
	var moved_count := 0
	while row.card_instance_ids.size() < target_size and not deck.card_instance_ids.is_empty():
		var card_instance_id: StringName = deck.card_instance_ids.back()
		var move_result := ZoneService.move_card(state, card_instance_id, deck_zone_id, row_zone_id)
		if not bool(move_result.get("ok", false)):
			return str(move_result.get("error", "supply_move_failed"))
		var event: Dictionary = (move_result.get("event", {}) as Dictionary).duplicate(true)
		event["reason"] = "supply_refill"
		events.append(event)
		moved_count += 1
	if announce_depletion and moved_count > 0 \
			and deck.card_instance_ids.is_empty() \
			and not bool(deck.metadata.get("depletion_announced", false)):
		deck.metadata["depletion_announced"] = true
		events.append({
			"type": "supply_deck_depleted",
			"deck_zone_id": str(deck_zone_id),
			"row_zone_id": str(row_zone_id),
		})
	return ""


static func cycle_defeated_monster(
	state: GameStateData,
	card_instance_id: StringName,
	events: Array[Dictionary]
) -> String:
	if ZoneService.find_card_zone(state, card_instance_id) != MONSTER_ROW_ID:
		return "monster_not_in_row"
	var move_result := ZoneService.move_card(
		state,
		card_instance_id,
		MONSTER_ROW_ID,
		MONSTER_CYCLE_ID,
		0
	)
	if not bool(move_result.get("ok", false)):
		return str(move_result.get("error", "monster_cycle_failed"))
	var move_event: Dictionary = (move_result.get("event", {}) as Dictionary).duplicate(true)
	move_event["reason"] = "monster_cycle_bottom"
	events.append(move_event)
	return refill_row(
		state,
		MONSTER_CYCLE_ID,
		MONSTER_ROW_ID,
		MONSTER_ROW_SIZE,
		events,
		false
	)


static func claim_defeated_monster(
	state: GameStateData,
	card_instance_id: StringName,
	player: PlayerStateData,
	events: Array[Dictionary]
) -> String:
	if ZoneService.find_card_zone(state, card_instance_id) != MONSTER_ROW_ID:
		return "monster_not_in_row"
	var move_result := ZoneService.move_card(
		state,
		card_instance_id,
		MONSTER_ROW_ID,
		StringName(player.zone_ids[&"discard_pile"])
	)
	if not bool(move_result.get("ok", false)):
		return str(move_result.get("error", "monster_claim_failed"))
	var card := state.cards[card_instance_id] as Dictionary
	card["owner_id"] = str(player.player_id)
	var move_event: Dictionary = (move_result.get("event", {}) as Dictionary).duplicate(true)
	move_event["reason"] = "defeated_monster_claimed"
	events.append(move_event)
	return refill_row(
		state,
		MONSTER_CYCLE_ID,
		MONSTER_ROW_ID,
		MONSTER_ROW_SIZE,
		events,
		false
	)
