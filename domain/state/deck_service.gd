class_name DeckService
extends RefCounted


static func discard_hand_and_play_area(
	state: GameStateData,
	player_id: StringName,
	events: Array[Dictionary]
) -> String:
	var player := state.players.get(player_id) as PlayerStateData
	if player == null:
		return "missing_player"
	var discard_zone_id := StringName(player.zone_ids.get(&"discard_pile", &""))
	for zone_key: StringName in [&"hand", &"play_area"]:
		var source_zone_id := StringName(player.zone_ids.get(zone_key, &""))
		var source := state.zones.get(source_zone_id) as ZoneData
		if source == null:
			return "missing_%s_zone" % zone_key
		for card_instance_id: StringName in source.card_instance_ids.duplicate():
			var move_result := ZoneService.move_card(
				state,
				card_instance_id,
				source_zone_id,
				discard_zone_id
			)
			if not bool(move_result.get("ok", false)):
				return str(move_result.get("error", "zone_move_failed"))
			var event: Dictionary = (move_result.get("event", {}) as Dictionary).duplicate(true)
			event["reason"] = "rest_cleanup"
			events.append(event)
	return ""


static func draw_cards(
	state: GameStateData,
	player_id: StringName,
	count: int,
	events: Array[Dictionary]
) -> Dictionary:
	if count < 0:
		return {"ok": false, "error": "invalid_draw_count", "drawn_count": 0}
	var player := state.players.get(player_id) as PlayerStateData
	if player == null:
		return {"ok": false, "error": "missing_player", "drawn_count": 0}
	var draw_zone_id := StringName(player.zone_ids.get(&"draw_pile", &""))
	var hand_zone_id := StringName(player.zone_ids.get(&"hand", &""))
	var discard_zone_id := StringName(player.zone_ids.get(&"discard_pile", &""))
	var draw_zone := state.zones.get(draw_zone_id) as ZoneData
	var hand_zone := state.zones.get(hand_zone_id) as ZoneData
	var discard_zone := state.zones.get(discard_zone_id) as ZoneData
	if draw_zone == null or hand_zone == null or discard_zone == null:
		return {"ok": false, "error": "missing_player_card_zone", "drawn_count": 0}

	var rng := DeterministicRng.new(state.seed_value, state.rng_state)
	var drawn_count := 0
	while drawn_count < count:
		if draw_zone.card_instance_ids.is_empty():
			if discard_zone.card_instance_ids.is_empty():
				break
			var rebuild_error := _rebuild_draw_pile(
				state,
				player_id,
				discard_zone_id,
				draw_zone_id,
				rng,
				events
			)
			if not rebuild_error.is_empty():
				return {"ok": false, "error": rebuild_error, "drawn_count": drawn_count}
		var card_instance_id: StringName = draw_zone.card_instance_ids.back()
		var move_result := ZoneService.move_card(
			state,
			card_instance_id,
			draw_zone_id,
			hand_zone_id
		)
		if not bool(move_result.get("ok", false)):
			return {
				"ok": false,
				"error": str(move_result.get("error", "zone_move_failed")),
				"drawn_count": drawn_count,
			}
		var event: Dictionary = (move_result.get("event", {}) as Dictionary).duplicate(true)
		event["reason"] = "draw"
		event["player_id"] = str(player_id)
		events.append(event)
		drawn_count += 1
	state.rng_state = rng.get_state()
	return {"ok": true, "drawn_count": drawn_count}


static func restock_hand(
	state: GameStateData,
	player_id: StringName,
	hand_size: int,
	events: Array[Dictionary]
) -> String:
	var cleanup_error := discard_hand_and_play_area(state, player_id, events)
	if not cleanup_error.is_empty():
		return cleanup_error
	var draw_result := draw_cards(state, player_id, hand_size, events)
	if not bool(draw_result.get("ok", false)):
		return str(draw_result.get("error", "draw_failed"))
	events.append({
		"type": "hand_restocked",
		"player_id": str(player_id),
		"requested_count": hand_size,
		"drawn_count": int(draw_result.get("drawn_count", 0)),
	})
	return ""


static func _rebuild_draw_pile(
	state: GameStateData,
	player_id: StringName,
	discard_zone_id: StringName,
	draw_zone_id: StringName,
	rng: DeterministicRng,
	events: Array[Dictionary]
) -> String:
	var discard_zone := state.zones[discard_zone_id] as ZoneData
	var draw_zone := state.zones[draw_zone_id] as ZoneData
	var rebuilt_count := discard_zone.card_instance_ids.size()
	for card_instance_id: StringName in discard_zone.card_instance_ids.duplicate():
		var move_result := ZoneService.move_card(
			state,
			card_instance_id,
			discard_zone_id,
			draw_zone_id
		)
		if not bool(move_result.get("ok", false)):
			return str(move_result.get("error", "zone_move_failed"))
	rng.shuffle(draw_zone.card_instance_ids)
	events.append({
		"type": "discard_reshuffled",
		"player_id": str(player_id),
		"card_count": rebuilt_count,
	})
	return ""
