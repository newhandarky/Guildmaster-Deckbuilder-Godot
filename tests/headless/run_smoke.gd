extends SceneTree

var _failures: PackedStringArray = []


func _init() -> void:
	_run()
	if _failures.is_empty():
		print("PASS: Guildmaster vertical-slice smoke suite")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("FAIL: %s" % failure)
		quit(1)


func _run() -> void:
	_test_content_pack()
	_test_content_pack_reload()
	_test_initial_invariants()
	_test_two_player_state()
	_test_official_starting_setup()
	_test_player_invariant_guards()
	_test_legal_command_and_dispatch()
	_test_command_legality_guards()
	_test_turn_rotation()
	_test_session_turn_integration()
	_test_zone_move_service()
	_test_rest_cleanup_and_draw()
	_test_draw_reshuffle_boundaries()
	_test_seeded_shuffle_order()
	_test_duplicate_command_guard()
	_test_twenty_blank_rounds()
	_test_twenty_round_determinism()
	_test_stale_command_rollback()
	_test_snapshot_round_trip()
	_test_snapshot_rejection_paths()
	_test_canonical_integer_numbers()
	_test_seeded_rng()
	_test_rng_state_restore()


func _test_content_pack() -> void:
	var registry := ContentRegistry.new()
	var errors := registry.load_pack("res://content/packs/base_vertical_slice.json")
	_expect(errors.is_empty(), "base content pack should validate: %s" % "; ".join(errors))
	_expect(registry.definitions.size() == 8, "vertical slice should load eight base definitions")
	_expect(not registry.definitions.has(&"custom:adventurer/melee-01"), "custom adventurers must stay disabled")
	_expect(not registry.pack_fingerprint.is_empty(), "content pack should expose a deterministic fingerprint")


func _test_content_pack_reload() -> void:
	var registry := ContentRegistry.new()
	var first_errors := registry.load_pack("res://content/packs/base_vertical_slice.json")
	var first_fingerprint := registry.pack_fingerprint
	var second_errors := registry.load_pack("res://content/packs/base_vertical_slice.json")
	_expect(first_errors.is_empty() and second_errors.is_empty(), "content pack should be safely reloadable")
	_expect(registry.definitions.size() == 8, "content reload must not retain duplicate definitions")
	_expect(registry.pack_fingerprint == first_fingerprint, "same content should keep the same fingerprint")


func _test_initial_invariants() -> void:
	var state := GameStateData.create_vertical_slice()
	var errors := InvariantService.validate(state)
	_expect(errors.is_empty(), "initial state should satisfy invariants: %s" % "; ".join(errors))


func _test_two_player_state() -> void:
	var state := GameStateData.create_vertical_slice()
	_expect(state.turn_order == [&"p1", &"p2"], "vertical slice should use a stable two-player turn order")
	_expect(state.players.size() == 2, "vertical slice should create two players")
	for player_id: StringName in state.turn_order:
		var player := state.players[player_id] as PlayerStateData
		_expect(player != null, "turn-order player %s should exist" % player_id)
		if player == null:
			continue
		for zone_key: StringName in PlayerStateData.REQUIRED_ZONE_KEYS:
			_expect(player.zone_ids.has(zone_key), "player %s should reference %s" % [player_id, zone_key])
			_expect(state.zones.has(player.zone_ids.get(zone_key)), "player %s zone %s should exist" % [player_id, zone_key])


func _test_official_starting_setup() -> void:
	var state := GameStateData.create_vertical_slice()
	_expect(state.cards.size() == 21, "two-player setup should create 20 player cards and one monster")
	for player_id: StringName in state.turn_order:
		var player := state.players[player_id] as PlayerStateData
		var party := state.zones[player.zone_ids[&"party"]] as ZoneData
		var hand := state.zones[player.zone_ids[&"hand"]] as ZoneData
		var draw_pile := state.zones[player.zone_ids[&"draw_pile"]] as ZoneData
		var discard_pile := state.zones[player.zone_ids[&"discard_pile"]] as ZoneData
		_expect(party.card_instance_ids.size() == 5, "player %s should start with five adventurers in party" % player_id)
		_expect(hand.card_instance_ids.size() == 5, "player %s should start with five cards in hand" % player_id)
		_expect(draw_pile.card_instance_ids.is_empty(), "official setup should not shuffle starting hand into draw pile")
		_expect(discard_pile.card_instance_ids.is_empty(), "official setup should start with an empty discard pile")
		var stone_count := 0
		var crystal_count := 0
		for card_instance_id: StringName in hand.card_instance_ids:
			var definition_id := str((state.cards[card_instance_id] as Dictionary).get("definition_id", ""))
			if definition_id == "base:starter/summoning-stone":
				stone_count += 1
			elif definition_id == "base:starter/spirit-crystal":
				crystal_count += 1
		_expect(stone_count == 4 and crystal_count == 1, "official starting hand should contain four stones and one crystal")


func _test_player_invariant_guards() -> void:
	var wrong_seat := GameStateData.create_vertical_slice()
	(wrong_seat.players[&"p2"] as PlayerStateData).seat_index = 0
	_expect(not InvariantService.validate(wrong_seat).is_empty(), "duplicate player seats must fail invariants")

	var shared_zone := GameStateData.create_vertical_slice()
	var player_one := shared_zone.players[&"p1"] as PlayerStateData
	player_one.zone_ids[&"hand"] = player_one.zone_ids[&"draw_pile"]
	_expect(not InvariantService.validate(shared_zone).is_empty(), "player zone references must be unique")

	var exposed_hand := GameStateData.create_vertical_slice()
	(exposed_hand.zones[&"p1:hand"] as ZoneData).visibility = &"public"
	_expect(not InvariantService.validate(exposed_hand).is_empty(), "private hand zone must not become public")
	_expect(RulesEngine.get_legal_commands(exposed_hand, &"p1").is_empty(), "invalid state must expose no legal commands")


func _test_legal_command_and_dispatch() -> void:
	var state := GameStateData.create_vertical_slice()
	var legal := RulesEngine.get_legal_commands(state, &"p1")
	_expect(legal.size() == 1, "active player should receive END_PHASE")
	var result := RulesEngine.dispatch(state, _end_phase_envelope(state))
	_expect(bool(result.get("ok", false)), "legal END_PHASE should dispatch")
	if bool(result.get("ok", false)):
		var next_state := result["state"] as GameStateData
		_expect(next_state.phase == &"combat", "END_PHASE should advance action1 to combat")
		_expect(next_state.revision == 1, "successful command should increment revision")
		_expect(state.phase == &"action1", "dispatch must not mutate the original state")


func _test_command_legality_guards() -> void:
	var inactive := GameStateData.create_vertical_slice()
	inactive.status = &"finished"
	_expect(RulesEngine.get_legal_commands(inactive, &"p1").is_empty(), "finished game should expose no commands")
	var inactive_result := RulesEngine.dispatch(inactive, _end_phase_envelope(inactive, "cmd-inactive"))
	_expect(str(inactive_result.get("error", "")) == "game_not_active", "dispatcher must reject commands after game end")

	var pending := GameStateData.create_vertical_slice()
	pending.effect_state = {"pending_choice": "test"}
	_expect(RulesEngine.get_legal_commands(pending, &"p1").is_empty(), "pending effect should expose no END_PHASE")
	var pending_result := RulesEngine.dispatch(pending, _end_phase_envelope(pending, "cmd-pending"))
	_expect(str(pending_result.get("error", "")) == "effects_pending", "dispatcher must enforce pending-effect legality")

	var wrong_actor := GameStateData.create_vertical_slice()
	var wrong_actor_envelope := _end_phase_envelope(wrong_actor, "cmd-wrong-actor")
	wrong_actor_envelope["actor_id"] = "p2"
	var wrong_actor_result := RulesEngine.dispatch(wrong_actor, wrong_actor_envelope)
	_expect(str(wrong_actor_result.get("error", "")) == "wrong_actor", "non-active player command must be rejected")


func _test_turn_rotation() -> void:
	var state := GameStateData.create_vertical_slice()
	var player_two := state.players[&"p2"] as PlayerStateData
	player_two.turn_resources["combat"] = 7
	player_two.turn_bonuses["test"] = true
	for index in 5:
		var result := RulesEngine.dispatch(state, _end_phase_envelope(state, "cmd-p1-%d" % index))
		_expect(bool(result.get("ok", false)), "player one phase %d should advance" % index)
		if not bool(result.get("ok", false)):
			return
		state = result["state"] as GameStateData
	_expect(state.active_player_id == &"p2", "rest should advance from player one to player two")
	_expect(state.phase == &"action1", "new player should begin at action1")
	_expect(state.round_number == 1, "round should not increase before returning to starting player")
	player_two = state.players[&"p2"] as PlayerStateData
	_expect(int(player_two.turn_resources.get("combat", -1)) == 0, "new active player's turn resources should reset")
	_expect(player_two.turn_bonuses.is_empty(), "new active player's turn bonuses should reset")

	for index in 5:
		var result := RulesEngine.dispatch(state, _end_phase_envelope(state, "cmd-p2-%d" % index))
		_expect(bool(result.get("ok", false)), "player two phase %d should advance" % index)
		if not bool(result.get("ok", false)):
			return
		state = result["state"] as GameStateData
	_expect(state.active_player_id == &"p1", "player two rest should return to starting player")
	_expect(state.round_number == 2, "round should increase only when starting player becomes active")


func _test_session_turn_integration() -> void:
	var session := GameSession.new()
	var errors := session.start_new_game(91)
	_expect(errors.is_empty(), "session should start a two-player game")
	if not errors.is_empty():
		return
	for index in 5:
		var result := session.end_phase()
		_expect(bool(result.get("ok", false)), "session should advance player-one phase %d" % index)
	_expect(session.state.active_player_id == &"p2", "session should expose player two after player one rests")
	var legal := session.get_legal_commands()
	_expect(legal.size() == 1 and legal[0].get("actor_id") == "p2", "session default legal query should follow active player")


func _test_zone_move_service() -> void:
	var state := GameStateData.create_vertical_slice()
	var before_hash := CanonicalJson.sha256(state.to_dictionary())
	var invalid := ZoneService.move_card(
		state,
		&"card-p1-starter-adventurer-01",
		&"p1:party",
		&"p1:discard-pile",
		9
	)
	_expect(str(invalid.get("error", "")) == "invalid_insert_index", "invalid zone move should fail before mutation")
	_expect(CanonicalJson.sha256(state.to_dictionary()) == before_hash, "invalid zone move must be atomic")

	var moved := ZoneService.move_card(
		state,
		&"card-p1-starter-adventurer-01",
		&"p1:party",
		&"p1:discard-pile"
	)
	_expect(bool(moved.get("ok", false)), "valid zone move should succeed")
	_expect(ZoneService.find_card_zone(state, &"card-p1-starter-adventurer-01") == &"p1:discard-pile", "zone lookup should reflect committed move")
	_expect(InvariantService.validate(state).is_empty(), "valid zone move should preserve invariants")


func _test_rest_cleanup_and_draw() -> void:
	var state := GameStateData.create_vertical_slice(113)
	var final_events: Array[Dictionary] = []
	for index in 5:
		var result := RulesEngine.dispatch(state, _end_phase_envelope(state, "cmd-rest-%d" % index))
		_expect(bool(result.get("ok", false)), "rest setup phase %d should dispatch" % index)
		if not bool(result.get("ok", false)):
			return
		state = result["state"] as GameStateData
		final_events = result["events"]
	var player_one := state.players[&"p1"] as PlayerStateData
	var hand := state.zones[player_one.zone_ids[&"hand"]] as ZoneData
	var draw_pile := state.zones[player_one.zone_ids[&"draw_pile"]] as ZoneData
	var discard_pile := state.zones[player_one.zone_ids[&"discard_pile"]] as ZoneData
	_expect(hand.card_instance_ids.size() == 5, "rest should draw five cards for the outgoing player")
	_expect(draw_pile.card_instance_ids.is_empty() and discard_pile.card_instance_ids.is_empty(), "five-card starting cycle should be fully drawn after reshuffle")
	_expect(_events_contain(final_events, "discard_reshuffled"), "first rest should reshuffle the discarded starting hand")
	_expect(_events_contain(final_events, "hand_restocked"), "rest should emit a hand_restocked event")
	_expect(InvariantService.validate(state).is_empty(), "rest cleanup and draw should preserve invariants")


func _test_draw_reshuffle_boundaries() -> void:
	var exact_draw := GameStateData.create_vertical_slice(127)
	var player := exact_draw.players[&"p1"] as PlayerStateData
	var hand := exact_draw.zones[player.zone_ids[&"hand"]] as ZoneData
	var original_hand := hand.card_instance_ids.duplicate()
	for card_instance_id: StringName in original_hand:
		ZoneService.move_card(exact_draw, card_instance_id, player.zone_ids[&"hand"], player.zone_ids[&"discard_pile"])
	var top_card := StringName(original_hand[0])
	ZoneService.move_card(exact_draw, top_card, player.zone_ids[&"discard_pile"], player.zone_ids[&"draw_pile"])
	var rng_before := exact_draw.rng_state
	var exact_events: Array[Dictionary] = []
	var exact_result := DeckService.draw_cards(exact_draw, &"p1", 1, exact_events)
	_expect(int(exact_result.get("drawn_count", 0)) == 1, "draw should take the final draw-pile card")
	_expect(not _events_contain(exact_events, "discard_reshuffled"), "drawing the final available card must not reshuffle early")
	_expect(exact_draw.rng_state == rng_before, "draw without shuffle must not consume RNG")

	var shortage := GameStateData.create_vertical_slice(131)
	var shortage_events: Array[Dictionary] = []
	var cleanup_error := DeckService.discard_hand_and_play_area(shortage, &"p1", shortage_events)
	_expect(cleanup_error.is_empty(), "shortage fixture cleanup should succeed")
	var shortage_result := DeckService.draw_cards(shortage, &"p1", 9, shortage_events)
	_expect(bool(shortage_result.get("ok", false)), "short draw should finish without fabricating cards")
	_expect(int(shortage_result.get("drawn_count", 0)) == 5, "draw should return only physically available cards")
	_expect(InvariantService.validate(shortage).is_empty(), "short draw should preserve invariants")


func _test_seeded_shuffle_order() -> void:
	var first := GameStateData.create_vertical_slice(149)
	var second := GameStateData.create_vertical_slice(149)
	var first_events: Array[Dictionary] = []
	var second_events: Array[Dictionary] = []
	DeckService.discard_hand_and_play_area(first, &"p1", first_events)
	DeckService.discard_hand_and_play_area(second, &"p1", second_events)
	DeckService.draw_cards(first, &"p1", 5, first_events)
	DeckService.draw_cards(second, &"p1", 5, second_events)
	var first_player := first.players[&"p1"] as PlayerStateData
	var second_player := second.players[&"p1"] as PlayerStateData
	var first_hand := first.zones[first_player.zone_ids[&"hand"]] as ZoneData
	var second_hand := second.zones[second_player.zone_ids[&"hand"]] as ZoneData
	_expect(first_hand.card_instance_ids == second_hand.card_instance_ids, "same seed should produce the same shuffled hand order")
	_expect(first.rng_state == second.rng_state, "same shuffle should preserve identical RNG state")


func _test_duplicate_command_guard() -> void:
	var state := GameStateData.create_vertical_slice()
	var first := RulesEngine.dispatch(state, _end_phase_envelope(state, "cmd-duplicate"))
	_expect(bool(first.get("ok", false)), "first command submission should succeed")
	if bool(first.get("ok", false)):
		var next_state := first["state"] as GameStateData
		var duplicate_envelope := _end_phase_envelope(next_state, "cmd-duplicate")
		var duplicate := RulesEngine.dispatch(next_state, duplicate_envelope)
		_expect(str(duplicate.get("error", "")) == "duplicate_command", "duplicate command ID must be rejected")


func _test_twenty_blank_rounds() -> void:
	var state := GameStateData.create_vertical_slice()
	for index in 200:
		var result := RulesEngine.dispatch(state, _end_phase_envelope(state, "cmd-round-%03d" % index))
		_expect(bool(result.get("ok", false)), "blank-round command %d should succeed" % index)
		if not bool(result.get("ok", false)):
			return
		state = result["state"] as GameStateData
	_expect(state.round_number == 21, "200 phase transitions should complete 20 two-player rounds")
	_expect(state.revision == 200, "each blank phase transition should commit one revision")
	_expect(state.active_player_id == &"p1" and state.phase == &"action1", "20 rounds should end at the starting-player boundary")


func _test_twenty_round_determinism() -> void:
	var first := GameStateData.create_vertical_slice(301)
	var second := GameStateData.create_vertical_slice(301)
	for index in 200:
		var command_id := "cmd-deterministic-%03d" % index
		var first_result := RulesEngine.dispatch(first, _end_phase_envelope(first, command_id))
		var second_result := RulesEngine.dispatch(second, _end_phase_envelope(second, command_id))
		if not bool(first_result.get("ok", false)) or not bool(second_result.get("ok", false)):
			_expect(false, "deterministic run should dispatch command %d" % index)
			return
		first = first_result["state"] as GameStateData
		second = second_result["state"] as GameStateData
	_expect(CanonicalJson.sha256(first.to_dictionary()) == CanonicalJson.sha256(second.to_dictionary()), "same seed and commands should produce the same 20-round hash")


func _test_stale_command_rollback() -> void:
	var state := GameStateData.create_vertical_slice()
	var before_hash := CanonicalJson.sha256(state.to_dictionary())
	var envelope := _end_phase_envelope(state)
	envelope["expected_revision"] = 99
	var result := RulesEngine.dispatch(state, envelope)
	_expect(not bool(result.get("ok", true)), "stale command should fail")
	_expect(str(result.get("error", "")) == "stale_revision", "stale command should return stable error code")
	_expect(CanonicalJson.sha256(state.to_dictionary()) == before_hash, "failed command must not mutate state")
	_expect(result.get("before_hash") == result.get("after_hash"), "failed command must preserve hash")


func _test_snapshot_round_trip() -> void:
	var state := GameStateData.create_vertical_slice()
	var encoded := SnapshotCodec.encode(state, "content:test", "rules:test")
	var decoded := SnapshotCodec.decode(encoded)
	_expect(bool(decoded.get("ok", false)), "snapshot should decode: %s" % decoded)
	if bool(decoded.get("ok", false)):
		var restored := decoded.get("state") as GameStateData
		_expect(restored != null and restored.rng_state == state.rng_state, "snapshot should preserve exact RNG state")
	if bool(decoded.get("ok", false)):
		var restored := decoded["state"] as GameStateData
		_expect(restored.players.size() == 2, "snapshot should preserve both players")
		_expect(restored.turn_order == state.turn_order, "snapshot should preserve turn order")
		_expect(
			CanonicalJson.sha256(restored.to_dictionary()) == CanonicalJson.sha256(state.to_dictionary()),
			"snapshot round trip should preserve state hash"
		)


func _test_snapshot_rejection_paths() -> void:
	var state := GameStateData.create_vertical_slice()
	var encoded := SnapshotCodec.encode(state, "content:test", "rules:test")
	var wrong_content := SnapshotCodec.decode(encoded, "content:other", "rules:test")
	_expect(str(wrong_content.get("error", "")) == "content_fingerprint_mismatch", "snapshot must reject wrong content fingerprint")

	var tampered := JSON.parse_string(encoded) as Dictionary
	(tampered["state"] as Dictionary)["round"] = 99
	var tampered_result := SnapshotCodec.decode(CanonicalJson.stringify(tampered))
	_expect(str(tampered_result.get("error", "")) == "state_hash_mismatch", "snapshot must reject tampered state")

	var malformed := JSON.parse_string(encoded) as Dictionary
	var malformed_state := malformed["state"] as Dictionary
	(malformed_state["cards"] as Dictionary)["card-starter-melee-01"] = 7
	malformed["state_hash"] = CanonicalJson.sha256(malformed_state)
	var malformed_result := SnapshotCodec.decode(CanonicalJson.stringify(malformed))
	_expect(str(malformed_result.get("error", "")) == "invalid_state", "snapshot must reject malformed nested data safely")


func _test_canonical_integer_numbers() -> void:
	_expect(
		CanonicalJson.sha256({"value": 7}) == CanonicalJson.sha256({"value": 7.0}),
		"canonical JSON should normalize integral numbers parsed from JSON"
	)
	_expect(
		CanonicalJson.sha256({"value": 7.5}) != CanonicalJson.sha256({"value": 7}),
		"canonical JSON should preserve non-integral numbers"
	)


func _test_seeded_rng() -> void:
	var first := DeterministicRng.new(42)
	var second := DeterministicRng.new(42)
	var first_rolls: Array[int] = []
	var second_rolls: Array[int] = []
	for index in 8:
		first_rolls.append(first.roll_die())
		second_rolls.append(second.roll_die())
	_expect(first_rolls == second_rolls, "same seed should produce the same die rolls")


func _test_rng_state_restore() -> void:
	var original := DeterministicRng.new(73)
	for index in 5:
		original.roll_die()
	var restored := DeterministicRng.new(73, original.get_state())
	var expected: Array[int] = []
	var actual: Array[int] = []
	for index in 8:
		expected.append(original.roll_die())
		actual.append(restored.roll_die())
	_expect(actual == expected, "restored RNG state should continue the same sequence")


func _end_phase_envelope(state: GameStateData, command_id: String = "cmd-test") -> Dictionary:
	return {
		"protocol_version": 1,
		"game_id": str(state.game_id),
		"command_id": command_id,
		"actor_id": str(state.active_player_id),
		"expected_revision": state.revision,
		"command": {"type": "END_PHASE"},
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _events_contain(events: Array[Dictionary], event_type: String) -> bool:
	for event: Dictionary in events:
		if str(event.get("type", "")) == event_type:
			return true
	return false
