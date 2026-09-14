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


static func refill_vertical_slice_rows(
	state: GameStateData, events: Array[Dictionary], definitions: Dictionary = {}
) -> String:
	for pair: Array in [
		[RECRUIT_DECK_ID, RECRUIT_ROW_ID],
		[SHOP_DECK_ID, SHOP_ROW_ID],
	]:
		var error := refill_row(state, pair[0], pair[1], ROW_SIZE, events)
		if not error.is_empty():
			return error
	var boss_error: String = BossServiceType.reveal_pending(state, events, definitions)
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
			and deck.card_instance_ids.is_empty():
		_announce_depletion(deck, row_zone_id, events)
	return ""


static func take_supply_cards(
	state: GameStateData,
	deck_zone_id: StringName,
	destination_zone_id: StringName,
	actor_id: StringName,
	amount: int,
	reason: StringName,
	events: Array[Dictionary]
) -> Dictionary:
	var deck := state.zones.get(deck_zone_id) as ZoneData
	var destination := state.zones.get(destination_zone_id) as ZoneData
	if deck_zone_id not in [RECRUIT_DECK_ID, SHOP_DECK_ID] \
			or deck == null or destination == null or deck.kind != &"ordered_deck" \
			or deck.visibility != &"hidden" or amount < 0:
		return {"ok": false, "error": "invalid_supply_gain"}
	var gained_ids: Array[String] = []
	for _draw_index in mini(amount, deck.card_instance_ids.size()):
		var gained_id: StringName = deck.card_instance_ids.back()
		var move_result := ZoneService.move_card(
			state, gained_id, deck_zone_id, destination_zone_id
		)
		if not bool(move_result.get("ok", false)):
			return {"ok": false, "error": str(move_result.get("error", "supply_gain_failed"))}
		(state.cards[gained_id] as Dictionary)["owner_id"] = str(
			ZoneService.actual_owner_after_move(state, move_result, actor_id)
		)
		var move_event := (move_result.get("event", {}) as Dictionary).duplicate(true)
		move_event["reason"] = str(reason)
		move_event["actor_id"] = str(actor_id)
		events.append(move_event)
		gained_ids.append(str(gained_id))
	if not gained_ids.is_empty() and deck.card_instance_ids.is_empty():
		var row_zone_id := RECRUIT_ROW_ID if deck_zone_id == RECRUIT_DECK_ID else SHOP_ROW_ID
		_announce_depletion(deck, row_zone_id, events)
	return {"ok": true, "gained_card_ids": gained_ids}


static func _announce_depletion(
	deck: ZoneData, row_zone_id: StringName, events: Array[Dictionary]
) -> void:
	if bool(deck.metadata.get("depletion_announced", false)):
		return
	deck.metadata["depletion_announced"] = true
	events.append({
		"type": "supply_deck_depleted",
		"deck_zone_id": str(deck.zone_id),
		"row_zone_id": str(row_zone_id),
	})


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
