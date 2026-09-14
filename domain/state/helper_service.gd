class_name HelperService
extends RefCounted

const DECK_ID := &"shared:helper-deck"
const ACTIVE_ID := &"shared:helper-active"
const RESERVE_ID := &"shared:helper-reserve"
const REMOVED_ID := &"shared:helper-removed"
const DRAFT_ROW_ID := &"shared:helper-draft-row"


static func setup(state: GameStateData, definitions: Dictionary) -> void:
	var deck := ZoneData.new(DECK_ID, &"ordered_deck", &"hidden")
	var active := ZoneData.new(ACTIVE_ID, &"face_up_row", &"public")
	var reserve := ZoneData.new(RESERVE_ID, &"ordered_deck", &"hidden")
	var removed := ZoneData.new(REMOVED_ID, &"removed", &"public")
	var draft := ZoneData.new(DRAFT_ROW_ID, &"face_up_row", &"public")
	draft.metadata = {"temporary_choice_zone": true}
	for number in range(1, 13):
		var suffix := "%02d" % number
		var card_id := StringName("card-helper-%s" % suffix)
		state.cards[card_id] = {
			"instance_id": str(card_id),
			"definition_id": "base:helper/helper-%s" % suffix,
			"owner_id": "",
			"state": {},
		}
		reserve.card_instance_ids.append(card_id)
	var rng := DeterministicRng.new(state.seed_value, state.rng_state)
	rng.shuffle(reserve.card_instance_ids)
	var boss_deck := state.zones[BossService.BOSS_DECK_ID] as ZoneData
	var boss_active := state.zones[BossService.BOSS_ACTIVE_ID] as ZoneData
	var selected_count := boss_deck.card_instance_ids.size() + boss_active.card_instance_ids.size()
	for _index in selected_count:
		deck.card_instance_ids.append(reserve.card_instance_ids.pop_back())
	state.rng_state = rng.get_state()
	for zone: ZoneData in [deck, active, reserve, removed, draft]:
		state.zones[zone.zone_id] = zone
	var setup_events: Array[Dictionary] = []
	_reveal_next(state, state.starting_player_id, setup_events, definitions)
	if state.effect_state.is_empty() and not definitions.is_empty():
		trigger(state, state.starting_player_id, &"on_turn_start", setup_events, definitions)


static func active_card_id(state: GameStateData) -> StringName:
	var active := state.zones.get(ACTIVE_ID) as ZoneData
	return active.card_instance_ids[0] if active != null and not active.card_instance_ids.is_empty() else &""


static func active_effects(state: GameStateData, definitions: Dictionary) -> Array[Dictionary]:
	var card_id := active_card_id(state)
	if card_id.is_empty():
		return []
	var card := state.cards.get(card_id) as Dictionary
	var definition := definitions.get(StringName(card.get("definition_id", ""))) as CardDefinition if card != null else null
	return definition.effects if definition != null else []


static func rule_amount(state: GameStateData, definitions: Dictionary, operation: StringName, fallback: int) -> int:
	for effect: Dictionary in active_effects(state, definitions):
		if StringName(effect.get("op", "")) == operation and StringName(effect.get("timing", "")) == &"continuous":
			return int(effect.get("amount", fallback))
	return fallback


static func trigger(
	state: GameStateData, actor_id: StringName, timing: StringName,
	events: Array[Dictionary], definitions: Dictionary
) -> String:
	var card_id := active_card_id(state)
	if card_id.is_empty():
		return ""
	return _trigger_for_card(state, actor_id, card_id, timing, events, definitions)


static func rotate(
	state: GameStateData, actor_id: StringName,
	events: Array[Dictionary], definitions: Dictionary
) -> String:
	if not state.effect_state.is_empty():
		return "effects_pending"
	var outgoing_id := active_card_id(state)
	if outgoing_id.is_empty():
		return "helper_not_active"
	var move_result := ZoneService.move_card(state, outgoing_id, ACTIVE_ID, REMOVED_ID)
	if not bool(move_result.get("ok", false)):
		return str(move_result.get("error", "helper_departure_failed"))
	var leave_move := (move_result.get("event", {}) as Dictionary).duplicate(true)
	leave_move["reason"] = "helper_departure"
	events.append(leave_move)
	events.append({"type":"helper_left","actor_id":str(actor_id),"card_instance_id":str(outgoing_id)})
	for player_id: StringName in state.turn_order:
		var player := state.players[player_id] as PlayerStateData
		var party := state.zones[StringName(player.zone_ids[&"party"])] as ZoneData
		while party.card_instance_ids.size() > party_capacity(state, definitions):
			var rightmost_id: StringName = party.card_instance_ids.back()
			var error := PartyService.discard_party_member_with_equipment(
				state, player, rightmost_id, &"helper_capacity_shrink", events, definitions
			)
			if not error.is_empty():
				return error
	var leave_error := _trigger_for_card(state, actor_id, outgoing_id, &"on_leave_helper", events, definitions)
	if not leave_error.is_empty():
		return leave_error
	if not state.effect_state.is_empty():
		state.effect_state["helper_reveal_after_choice"] = true
		return ""
	return reveal_after_choice(state, actor_id, events, definitions)


static func reveal_after_choice(
	state: GameStateData, actor_id: StringName,
	events: Array[Dictionary], definitions: Dictionary
) -> String:
	var boss_deck := state.zones[BossService.BOSS_DECK_ID] as ZoneData
	var helper_deck := state.zones[DECK_ID] as ZoneData
	if boss_deck.card_instance_ids.is_empty() or helper_deck.card_instance_ids.is_empty():
		events.append({"type":"helper_rotation_completed","actor_id":str(actor_id),"next_helper_id":""})
		return ""
	var error := _reveal_next(state, actor_id, events, definitions)
	if error.is_empty():
		events.append({"type":"helper_rotation_completed","actor_id":str(actor_id),"next_helper_id":str(active_card_id(state))})
	return error


static func party_capacity(state: GameStateData, definitions: Dictionary) -> int:
	return rule_amount(state, definitions, &"party_capacity", PartyService.BASE_PARTY_CAPACITY)


static func _reveal_next(
	state: GameStateData, actor_id: StringName,
	events: Array[Dictionary], definitions: Dictionary
) -> String:
	var deck := state.zones[DECK_ID] as ZoneData
	if deck.card_instance_ids.is_empty():
		return "helper_deck_empty"
	var card_id: StringName = deck.card_instance_ids.back()
	var move_result := ZoneService.move_card(state, card_id, DECK_ID, ACTIVE_ID)
	if not bool(move_result.get("ok", false)):
		return str(move_result.get("error", "helper_reveal_failed"))
	var reveal_move := (move_result.get("event", {}) as Dictionary).duplicate(true)
	reveal_move["reason"] = "helper_reveal"
	events.append(reveal_move)
	events.append({"type":"helper_revealed","actor_id":str(actor_id),"card_instance_id":str(card_id),"remaining_in_deck":deck.card_instance_ids.size()})
	return _trigger_for_card(state, actor_id, card_id, &"on_enter_helper", events, definitions) \
		if not definitions.is_empty() else ""


static func _trigger_for_card(
	state: GameStateData, actor_id: StringName, card_id: StringName,
	timing: StringName, events: Array[Dictionary], definitions: Dictionary
) -> String:
	var card := state.cards.get(card_id) as Dictionary
	var definition := definitions.get(StringName(card.get("definition_id", ""))) as CardDefinition if card != null else null
	if definition == null:
		return "missing_helper_definition"
	var triggered: Array[Dictionary] = []
	var player := state.players.get(actor_id) as PlayerStateData
	for effect: Dictionary in definition.effects:
		if StringName(effect.get("timing", "")) == timing:
			var use_key := "helper_triggered:%s:%s" % [card_id, timing]
			if bool(effect.get("once_per_turn", false)):
				if player == null or bool(player.turn_facts.get(use_key, false)):
					continue
				player.turn_facts[use_key] = true
			var instance := effect.duplicate(true)
			instance["source_card_instance_id"] = str(card_id)
			triggered.append(instance)
	if triggered.is_empty():
		return ""
	events.append({"type":"helper_triggered","actor_id":str(actor_id),"card_instance_id":str(card_id),"timing":str(timing)})
	return EffectResolver.resolve(state, actor_id, triggered, events, definitions)
