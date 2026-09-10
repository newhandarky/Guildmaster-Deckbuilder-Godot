extends SceneTree

var _failures: PackedStringArray = []


func _init() -> void:
	await _run()
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
	_test_equip_item_legality_and_resources()
	_test_equip_item_rejection_is_atomic()
	_test_equipment_replacement()
	_test_effect_resolution_fifo()
	_test_equipment_survives_rest()
	_test_monster_supply_setup_and_anchor()
	_test_combat_preview_and_reward()
	_test_combat_optional_reward_skip()
	_test_standard_monster_claim_and_draw_rewards()
	_test_combat_rejection_is_atomic()
	_test_combat_equipment_departure()
	_test_supply_setup_and_determinism()
	_test_purchase_and_rest_refill()
	_test_purchase_rejection_is_atomic()
	_test_supply_depletion_event_once()
	_test_market_refresh_legality_and_commit()
	_test_market_refresh_rejection_is_atomic()
	_test_market_refresh_selection_order_is_deterministic()
	await _test_market_refresh_hud_integration()
	await _test_combat_hud_integration()
	_test_play_adventurer_capacity_and_equipment_departure()
	_test_use_item_draw_and_rest_cleanup()
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
	_expect(registry.definitions.size() == 16, "vertical slice should load sixteen base definitions")
	_expect(not registry.definitions.has(&"custom:adventurer/melee-01"), "custom adventurers must stay disabled")
	_expect(not registry.pack_fingerprint.is_empty(), "content pack should expose a deterministic fingerprint")


func _test_content_pack_reload() -> void:
	var registry := ContentRegistry.new()
	var first_errors := registry.load_pack("res://content/packs/base_vertical_slice.json")
	var first_fingerprint := registry.pack_fingerprint
	var second_errors := registry.load_pack("res://content/packs/base_vertical_slice.json")
	_expect(first_errors.is_empty() and second_errors.is_empty(), "content pack should be safely reloadable")
	_expect(registry.definitions.size() == 16, "content reload must not retain duplicate definitions")
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
	_expect(state.cards.size() == 41, "setup should create player cards, seven monsters, and fourteen market cards")
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

	var attachment_state := GameStateData.create_vertical_slice()
	var definitions := _load_definitions()
	var attachment_result := RulesEngine.dispatch(
		attachment_state,
		_equip_item_envelope(attachment_state, &"card-p1-spirit-crystal-01", &"card-p1-starter-adventurer-01", "cmd-attachment-invariant"),
		definitions
	)
	_expect(bool(attachment_result.get("ok", false)), "attachment invariant fixture should equip successfully")
	if bool(attachment_result.get("ok", false)):
		var broken_attachment := attachment_result["state"] as GameStateData
		var target := broken_attachment.cards[&"card-p1-starter-adventurer-01"] as Dictionary
		(target.get("state", {}) as Dictionary)["equipment_ids"] = []
		_expect(not InvariantService.validate(broken_attachment).is_empty(), "equipment attachments must remain bidirectional")


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


func _test_equip_item_legality_and_resources() -> void:
	var state := GameStateData.create_vertical_slice()
	var definitions := _load_definitions()
	var legal := RulesEngine.get_legal_commands(state, &"p1", definitions)
	var play_commands: Array[Dictionary] = []
	for command: Dictionary in legal:
		if command.get("type") == "EQUIP_ITEM":
			play_commands.append(command)
	_expect(play_commands.size() == 5, "spirit crystal should be equippable to each of five party members")
	for command: Dictionary in play_commands:
		_expect(command.get("card_instance_id") == "card-p1-spirit-crystal-01", "summoning stones must not be exposed as playable cards")

	var before_resources := ResourceService.evaluate_player(state, &"p1", definitions)
	_expect(int(before_resources.get("combat", 0)) == 6, "starter party should provide six printed combat")
	_expect(int(before_resources.get("purchase_power", 0)) == 4, "four stones in hand should provide four purchase power")
	var result := RulesEngine.dispatch(
		state,
		_equip_item_envelope(
			state,
			&"card-p1-spirit-crystal-01",
			&"card-p1-starter-adventurer-01",
			"cmd-equip-crystal"
		),
		definitions
	)
	_expect(bool(result.get("ok", false)), "legal equipment play should dispatch")
	var deterministic_result := RulesEngine.dispatch(
		state,
		_equip_item_envelope(
			state,
			&"card-p1-spirit-crystal-01",
			&"card-p1-starter-adventurer-01",
			"cmd-equip-crystal"
		),
		definitions
	)
	_expect(result.get("after_hash") == deterministic_result.get("after_hash"), "same equipment command should produce the same committed hash")
	if not bool(result.get("ok", false)):
		return
	var equipped := result["state"] as GameStateData
	_expect(ZoneService.find_card_zone(equipped, &"card-p1-spirit-crystal-01") == &"p1:equipment", "equipped card should move to the equipment zone")
	var crystal := equipped.cards[&"card-p1-spirit-crystal-01"] as Dictionary
	_expect((crystal.get("state", {}) as Dictionary).get("equipped_to") == "card-p1-starter-adventurer-01", "equipment should retain its target")
	var target := equipped.cards[&"card-p1-starter-adventurer-01"] as Dictionary
	_expect("card-p1-spirit-crystal-01" in (target.get("state", {}) as Dictionary).get("equipment_ids", []), "target should retain the reverse equipment attachment")
	var after_resources := ResourceService.evaluate_player(equipped, &"p1", definitions)
	_expect(int(after_resources.get("combat", 0)) == 7, "equipped spirit crystal should add one combat")
	_expect(int(after_resources.get("purchase_power", 0)) == 4, "equipping the crystal must not spend or add purchase power")
	_expect(InvariantService.validate(equipped).is_empty(), "equipped state should satisfy invariants")
	_expect(ZoneService.find_card_zone(state, &"card-p1-spirit-crystal-01") == &"p1:hand", "transaction must leave the original state unchanged")


func _test_equip_item_rejection_is_atomic() -> void:
	var definitions := _load_definitions()
	var wrong_phase := GameStateData.create_vertical_slice()
	wrong_phase.phase = &"combat"
	var before_hash := CanonicalJson.sha256(wrong_phase.to_dictionary())
	var wrong_phase_result := RulesEngine.dispatch(
		wrong_phase,
		_equip_item_envelope(wrong_phase, &"card-p1-spirit-crystal-01", &"card-p1-starter-adventurer-01", "cmd-wrong-phase"),
		definitions
	)
	_expect(str(wrong_phase_result.get("error", "")) == "wrong_phase", "equipment may only be played during an action phase")
	_expect(CanonicalJson.sha256(wrong_phase.to_dictionary()) == before_hash, "wrong-phase play must not mutate state")

	var stone_state := GameStateData.create_vertical_slice()
	var stone_hash := CanonicalJson.sha256(stone_state.to_dictionary())
	var stone_result := RulesEngine.dispatch(
		stone_state,
		_equip_item_envelope(stone_state, &"card-p1-summoning-stone-01", &"card-p1-starter-adventurer-01", "cmd-play-stone"),
		definitions
	)
	_expect(str(stone_result.get("error", "")) == "unsupported_card_type", "summoning stones must stay in hand as passive purchase power")
	_expect(CanonicalJson.sha256(stone_state.to_dictionary()) == stone_hash, "unsupported card play must be atomic")

	var invalid_target := GameStateData.create_vertical_slice()
	var target_hash := CanonicalJson.sha256(invalid_target.to_dictionary())
	var target_result := RulesEngine.dispatch(
		invalid_target,
		_equip_item_envelope(invalid_target, &"card-p1-spirit-crystal-01", &"card-monster-skeleton-01", "cmd-invalid-target"),
		definitions
	)
	_expect(str(target_result.get("error", "")) == "target_not_owned", "equipment target must belong to the acting player")
	_expect(CanonicalJson.sha256(invalid_target.to_dictionary()) == target_hash, "invalid target must leave state unchanged")


func _test_equipment_replacement() -> void:
	var definitions := _load_definitions()
	var state := GameStateData.create_vertical_slice()
	var first := RulesEngine.dispatch(
		state,
		_equip_item_envelope(state, &"card-p1-spirit-crystal-01", &"card-p1-starter-adventurer-01", "cmd-first-equipment"),
		definitions
	)
	_expect(bool(first.get("ok", false)), "replacement fixture should equip the first card")
	if not bool(first.get("ok", false)):
		return
	state = first["state"] as GameStateData
	var replacement_definition := CardDefinition.from_dictionary({
		"definition_id": "test:equipment/replacement",
		"display_name": "測試裝備",
		"card_type": "equipment",
		"copies": 1,
		"combat": 2,
		"tags": ["equipment"],
		"effects": [],
		"presentation_id": "test:presentation/equipment",
	})
	definitions[replacement_definition.definition_id] = replacement_definition
	state.cards[&"card-p1-test-equipment"] = {
		"instance_id": "card-p1-test-equipment",
		"definition_id": "test:equipment/replacement",
		"owner_id": "p1",
		"state": {},
	}
	(state.zones[&"p1:hand"] as ZoneData).card_instance_ids.append(&"card-p1-test-equipment")
	var second := RulesEngine.dispatch(
		state,
		_equip_item_envelope(state, &"card-p1-test-equipment", &"card-p1-starter-adventurer-01", "cmd-replace-equipment"),
		definitions
	)
	_expect(bool(second.get("ok", false)), "new equipment should replace an occupied slot")
	if not bool(second.get("ok", false)):
		return
	var replaced := second["state"] as GameStateData
	_expect(ZoneService.find_card_zone(replaced, &"card-p1-spirit-crystal-01") == &"p1:discard-pile", "replaced equipment should enter discard")
	_expect(ZoneService.find_card_zone(replaced, &"card-p1-test-equipment") == &"p1:equipment", "new equipment should occupy the equipment zone")
	_expect(int(ResourceService.evaluate_player(replaced, &"p1", definitions).get("combat", 0)) == 8, "replacement combat should use only the new equipment")
	_expect(InvariantService.validate(replaced).is_empty(), "equipment replacement should preserve invariants")


func _test_effect_resolution_fifo() -> void:
	var state := GameStateData.create_vertical_slice()
	var events: Array[Dictionary] = []
	var effects: Array[Dictionary] = [
		{"op": "grant_purchase_power", "amount": 2},
		{"op": "grant_combat", "amount": 3},
	]
	var error := EffectResolver.resolve(state, &"p1", effects, events)
	_expect(error.is_empty(), "supported effects should resolve")
	var player := state.players[&"p1"] as PlayerStateData
	_expect(int(player.turn_resources.get("purchase_power", 0)) == 2, "purchase-power effect should update turn resources")
	_expect(int(player.turn_resources.get("combat", 0)) == 3, "combat effect should update turn resources")
	_expect(events.size() == 2 and events[0].get("op") == "grant_purchase_power" and events[1].get("op") == "grant_combat", "effects should emit events in FIFO content order")

	var invalid_state := GameStateData.create_vertical_slice()
	var invalid_hash := CanonicalJson.sha256(invalid_state.to_dictionary())
	var invalid_events: Array[Dictionary] = []
	var invalid_effects: Array[Dictionary] = [
		{"op": "grant_combat", "amount": 1},
		{"op": "unknown_operation", "amount": 1},
	]
	_expect(not EffectResolver.resolve(invalid_state, &"p1", invalid_effects, invalid_events).is_empty(), "unknown effects should be rejected")
	_expect(CanonicalJson.sha256(invalid_state.to_dictionary()) == invalid_hash and invalid_events.is_empty(), "effect validation must finish before any mutation")


func _test_equipment_survives_rest() -> void:
	var definitions := _load_definitions()
	var state := GameStateData.create_vertical_slice(211)
	var equip_result := RulesEngine.dispatch(
		state,
		_equip_item_envelope(state, &"card-p1-spirit-crystal-01", &"card-p1-starter-adventurer-01", "cmd-rest-equip"),
		definitions
	)
	_expect(bool(equip_result.get("ok", false)), "rest fixture should equip the crystal")
	if not bool(equip_result.get("ok", false)):
		return
	state = equip_result["state"] as GameStateData
	var player := state.players[&"p1"] as PlayerStateData
	player.turn_resources["combat"] = 3
	player.turn_resources["purchase_power"] = 2
	for index in 5:
		var result := RulesEngine.dispatch(state, _end_phase_envelope(state, "cmd-equipped-rest-%d" % index), definitions)
		_expect(bool(result.get("ok", false)), "equipped rest phase %d should dispatch" % index)
		if not bool(result.get("ok", false)):
			return
		state = result["state"] as GameStateData
	player = state.players[&"p1"] as PlayerStateData
	_expect(ZoneService.find_card_zone(state, &"card-p1-spirit-crystal-01") == &"p1:equipment", "equipped cards must remain attached through rest")
	_expect((state.zones[&"p1:hand"] as ZoneData).card_instance_ids.size() == 4, "rest should draw only the four physically available stones")
	_expect(int(player.turn_resources.get("combat", -1)) == 0 and int(player.turn_resources.get("purchase_power", -1)) == 0, "rest should clear outgoing player's temporary resources")
	var resources := ResourceService.evaluate_player(state, &"p1", definitions)
	_expect(int(resources.get("combat", 0)) == 7 and int(resources.get("purchase_power", 0)) == 4, "printed party, equipment, and hand resources should remain derivable after rest")
	_expect(InvariantService.validate(state).is_empty(), "rest with persistent equipment should satisfy invariants")


func _test_monster_supply_setup_and_anchor() -> void:
	var state := GameStateData.create_vertical_slice(219)
	var row := state.zones[SupplyService.MONSTER_ROW_ID] as ZoneData
	var cycle := state.zones[SupplyService.MONSTER_CYCLE_ID] as ZoneData
	_expect(row.card_instance_ids.size() == 3, "vertical slice should reveal three monsters")
	_expect(cycle.card_instance_ids.size() == 4, "vertical slice cycle should retain four monsters")
	_expect(
		row.card_instance_ids == [
			&"card-monster-skeleton-01",
			&"card-monster-rabbit-demon-01",
			&"card-monster-slime-01",
		],
		"opening row should expose skeleton, rabbit demon, and slime"
	)
	_expect(
		&"card-monster-skeleton-01" in row.card_instance_ids,
		"monster cycle anchor should begin in the public row"
	)
	_expect(InvariantService.validate(state).is_empty(), "monster supply should satisfy continuity invariants")
	var same_seed := GameStateData.create_vertical_slice(219)
	_expect(
		cycle.card_instance_ids
			== (same_seed.zones[SupplyService.MONSTER_CYCLE_ID] as ZoneData).card_instance_ids,
		"monster cycle order should be deterministic for the same seed"
	)
	var broken := state.clone_state()
	(broken.zones[SupplyService.MONSTER_ROW_ID] as ZoneData).card_instance_ids.erase(
		&"card-monster-skeleton-01"
	)
	(broken.zones[&"p1:discard-pile"] as ZoneData).card_instance_ids.append(
		&"card-monster-skeleton-01"
	)
	_expect(
		not InvariantService.validate(broken).is_empty(),
		"moving the cycle anchor outside its supply should fail invariants"
	)


func _test_combat_preview_and_reward() -> void:
	var definitions := _load_definitions()
	var state := GameStateData.create_vertical_slice(221)
	var phase_result := RulesEngine.dispatch(
		state, _end_phase_envelope(state, "cmd-combat-setup"), definitions
	)
	_expect(bool(phase_result.get("ok", false)), "combat fixture should enter combat phase")
	if not bool(phase_result.get("ok", false)):
		return
	state = phase_result["state"] as GameStateData
	var preview := CombatService.preview_attack(
		state, &"p1", &"card-monster-skeleton-01", definitions
	)
	_expect(bool(preview.get("legal", false)), "starter party should be able to defeat a skeleton")
	_expect(int(preview.get("requirement", 0)) == 5, "skeleton should require five combat")
	_expect(int(preview.get("total_combat", 0)) == 5, "combat preview should stop at exact threshold")
	_expect(
		preview.get("participant_ids", []) == [
			"card-p1-starter-adventurer-01",
			"card-p1-starter-adventurer-02",
			"card-p1-starter-adventurer-03",
			"card-p1-starter-adventurer-04",
		],
		"participants should be the shortest left-to-right prefix that reaches five"
	)
	var legal := RulesEngine.get_legal_commands(state, &"p1", definitions)
	var attack_count := 0
	for legal_command: Dictionary in legal:
		if legal_command.get("type") == "ATTACK_TARGET":
			attack_count += 1
	_expect(attack_count == 4, "opening monsters should expose two skeleton choices and one per mandatory reward")
	var command := {
		"type": "ATTACK_TARGET",
		"target_card_id": "card-monster-skeleton-01",
		"claim_optional_reward": true,
	}
	var envelope := _command_envelope(state, command, "cmd-attack-skeleton")
	var result := RulesEngine.dispatch(state, envelope, definitions)
	var deterministic := RulesEngine.dispatch(state, envelope, definitions)
	_expect(bool(result.get("ok", false)), "legal skeleton attack should commit")
	_expect(result.get("after_hash") == deterministic.get("after_hash"), "combat should be deterministic")
	if not bool(result.get("ok", false)):
		return
	var defeated := result["state"] as GameStateData
	var player := defeated.players[&"p1"] as PlayerStateData
	var party := defeated.zones[player.zone_ids[&"party"]] as ZoneData
	_expect(
		party.card_instance_ids == [&"card-p1-starter-adventurer-05"],
		"only non-participating party members should remain"
	)
	_expect(
		int(player.turn_resources.get("purchase_power", 0)) == 4,
		"claiming the skeleton reward should grant four temporary purchase power"
	)
	_expect(
		int(ResourceService.evaluate_player(defeated, &"p1", definitions).get("purchase_power", 0)) == 8,
		"reward should combine with four summoning stones"
	)
	_expect(
		(defeated.zones[SupplyService.MONSTER_ROW_ID] as ZoneData).card_instance_ids.size() == 3,
		"defeated skeleton should return through the cycle and refill the row"
	)
	_expect(
		ZoneService.find_card_zone(defeated, &"card-monster-skeleton-01") == SupplyService.MONSTER_CYCLE_ID,
		"cycle skeleton must never enter a player discard pile"
	)
	_expect(int(player.turn_facts.get(&"defeated_monster_count", 0)) == 1, "combat should update turn facts")
	_expect(_events_contain(result["events"], "combat_declared"), "combat should emit its locked context")
	_expect(_events_contain(result["events"], "enemy_defeated"), "combat should emit enemy defeat")
	_expect(InvariantService.validate(defeated).is_empty(), "combat should preserve all invariants")
	var decoded := SnapshotCodec.decode(
		SnapshotCodec.encode(defeated, "content:combat", "rules:combat")
	)
	_expect(bool(decoded.get("ok", false)), "post-combat snapshot should round trip")
	if bool(decoded.get("ok", false)):
		var restored := decoded["state"] as GameStateData
		_expect(
			InvariantService.validate(restored).is_empty(),
			"restored combat snapshot should preserve monster continuity"
		)
		_expect(
			CanonicalJson.sha256(restored.to_dictionary())
				== CanonicalJson.sha256(defeated.to_dictionary()),
			"post-combat snapshot should preserve the exact state hash"
		)
	_expect(
		not _commands_contain(RulesEngine.get_legal_commands(defeated, &"p1", definitions), "ATTACK_TARGET"),
		"remaining combat one should not expose another attack"
	)
	defeated.phase = &"action2"
	var departed_starter := &"card-p1-starter-adventurer-01"
	ZoneService.move_card(
		defeated,
		departed_starter,
		&"p1:discard-pile",
		&"p1:hand"
	)
	var starter_can_return := false
	for legal_command: Dictionary in RulesEngine.get_legal_commands(defeated, &"p1", definitions):
		if legal_command.get("type") == "PLAY_ADVENTURER" \
				and legal_command.get("card_instance_id") == str(departed_starter):
			starter_can_return = true
	_expect(starter_can_return, "departed starter adventurers should be playable again from hand")


func _test_combat_optional_reward_skip() -> void:
	var definitions := _load_definitions()
	var state := GameStateData.create_vertical_slice(225)
	var phase_result := RulesEngine.dispatch(
		state, _end_phase_envelope(state, "cmd-combat-skip-setup"), definitions
	)
	if not bool(phase_result.get("ok", false)):
		_expect(false, "skip reward fixture should enter combat")
		return
	state = phase_result["state"] as GameStateData
	var result := RulesEngine.dispatch(
		state,
		_command_envelope(state, {
			"type": "ATTACK_TARGET",
			"target_card_id": "card-monster-skeleton-01",
			"claim_optional_reward": false,
		}, "cmd-attack-skip-reward"),
		definitions
	)
	_expect(bool(result.get("ok", false)), "optional skeleton reward should be skippable")
	if bool(result.get("ok", false)):
		var skipped := result["state"] as GameStateData
		var player := skipped.players[&"p1"] as PlayerStateData
		_expect(
			int(player.turn_resources.get("purchase_power", 0)) == 0,
			"skipping reward should not grant temporary purchase power"
		)


func _test_standard_monster_claim_and_draw_rewards() -> void:
	var definitions := _load_definitions()
	var rabbit_state := GameStateData.create_vertical_slice(226)
	var phase_result := RulesEngine.dispatch(
		rabbit_state,
		_end_phase_envelope(rabbit_state, "cmd-rabbit-combat-setup"),
		definitions
	)
	if not bool(phase_result.get("ok", false)):
		_expect(false, "rabbit fixture should enter combat")
		return
	rabbit_state = phase_result["state"] as GameStateData
	var rabbit_preview := CombatService.preview_attack(
		rabbit_state, &"p1", &"card-monster-rabbit-demon-01", definitions
	)
	_expect(
		rabbit_preview.get("participant_ids", []) == [
			"card-p1-starter-adventurer-01",
			"card-p1-starter-adventurer-02",
		],
		"rabbit should use the first two participants"
	)
	_expect(
		rabbit_preview.get("reward_summary")
			== "抽 2 張、取得此卡（購買力 1／榮譽 1）",
		"rabbit preview should describe draw and printed acquisition values"
	)
	var invalid_skip_hash := CanonicalJson.sha256(rabbit_state.to_dictionary())
	var invalid_skip := RulesEngine.dispatch(
		rabbit_state,
		_command_envelope(rabbit_state, {
			"type": "ATTACK_TARGET",
			"target_card_id": "card-monster-rabbit-demon-01",
			"claim_optional_reward": false,
		}, "cmd-skip-mandatory-rabbit-reward"),
		definitions
	)
	_expect(
		str(invalid_skip.get("error", "")) == "reward_not_optional",
		"mandatory rabbit reward must not accept a skip command"
	)
	_expect(
		CanonicalJson.sha256(rabbit_state.to_dictionary()) == invalid_skip_hash,
		"invalid mandatory reward choice must be atomic"
	)
	var rabbit_result := RulesEngine.dispatch(
		rabbit_state,
		_command_envelope(rabbit_state, {
			"type": "ATTACK_TARGET",
			"target_card_id": "card-monster-rabbit-demon-01",
			"claim_optional_reward": true,
		}, "cmd-attack-rabbit"),
		definitions
	)
	_expect(bool(rabbit_result.get("ok", false)), "rabbit attack should commit")
	if not bool(rabbit_result.get("ok", false)):
		return
	var departure_index := -1
	var reward_index := -1
	var claim_index := -1
	var rabbit_events := rabbit_result["events"] as Array
	for index in rabbit_events.size():
		var event := rabbit_events[index] as Dictionary
		if event.get("reason") == "combat_departure" and departure_index < 0:
			departure_index = index
		elif event.get("type") == "effect_resolved" and event.get("op") == "draw":
			reward_index = index
		elif event.get("reason") == "defeated_monster_claimed":
			claim_index = index
	_expect(
		departure_index >= 0 and departure_index < reward_index and reward_index < claim_index,
		"combat events should order departure, reward, then monster acquisition"
	)
	var rabbit_defeated := rabbit_result["state"] as GameStateData
	var rabbit_player := rabbit_defeated.players[&"p1"] as PlayerStateData
	_expect(
		(rabbit_defeated.zones[rabbit_player.zone_ids[&"hand"]] as ZoneData)
			.card_instance_ids.size() == 7,
		"rabbit reward should draw two departed adventurers after combat departure"
	)
	_expect(
		ZoneService.find_card_zone(rabbit_defeated, &"card-monster-rabbit-demon-01")
			== rabbit_player.zone_ids[&"discard_pile"],
		"defeated rabbit should enter the winner discard pile"
	)
	_expect(
		StringName(
			(rabbit_defeated.cards[&"card-monster-rabbit-demon-01"] as Dictionary)
				.get("owner_id", "")
		) == &"p1",
		"claimed rabbit should become owned by the winner"
	)
	ZoneService.move_card(
		rabbit_defeated,
		&"card-monster-rabbit-demon-01",
		rabbit_player.zone_ids[&"discard_pile"],
		rabbit_player.zone_ids[&"hand"]
	)
	_expect(
		int(
			ResourceService.evaluate_player(rabbit_defeated, &"p1", definitions)
				.get("purchase_power", 0)
		) == 5,
		"claimed rabbit should provide its printed purchase power while in hand"
	)
	_expect(InvariantService.validate(rabbit_defeated).is_empty(), "rabbit claim should preserve invariants")

	var slime_state := GameStateData.create_vertical_slice(232)
	phase_result = RulesEngine.dispatch(
		slime_state,
		_end_phase_envelope(slime_state, "cmd-slime-combat-setup"),
		definitions
	)
	if not bool(phase_result.get("ok", false)):
		_expect(false, "slime fixture should enter combat")
		return
	slime_state = phase_result["state"] as GameStateData
	var slime_result := RulesEngine.dispatch(
		slime_state,
		_command_envelope(slime_state, {
			"type": "ATTACK_TARGET",
			"target_card_id": "card-monster-slime-01",
			"claim_optional_reward": true,
		}, "cmd-attack-slime"),
		definitions
	)
	_expect(bool(slime_result.get("ok", false)), "slime attack should commit")
	if bool(slime_result.get("ok", false)):
		var slime_defeated := slime_result["state"] as GameStateData
		var slime_player := slime_defeated.players[&"p1"] as PlayerStateData
		_expect(
			(slime_defeated.zones[slime_player.zone_ids[&"hand"]] as ZoneData)
				.card_instance_ids.size() == 6,
			"slime reward should draw one card after participants depart"
		)
		_expect(
			ZoneService.find_card_zone(slime_defeated, &"card-monster-slime-01")
				== slime_player.zone_ids[&"discard_pile"],
			"defeated slime should enter the winner discard pile"
		)
		_expect(InvariantService.validate(slime_defeated).is_empty(), "slime claim should preserve invariants")


func _test_combat_rejection_is_atomic() -> void:
	var definitions := _load_definitions()
	var wrong_phase := GameStateData.create_vertical_slice(227)
	var command := {
		"type": "ATTACK_TARGET",
		"target_card_id": "card-monster-skeleton-01",
		"claim_optional_reward": true,
	}
	var wrong_hash := CanonicalJson.sha256(wrong_phase.to_dictionary())
	var wrong_result := RulesEngine.dispatch(
		wrong_phase,
		_command_envelope(wrong_phase, command, "cmd-attack-wrong-phase"),
		definitions
	)
	_expect(str(wrong_result.get("error", "")) == "wrong_phase", "attack must be combat-phase only")
	_expect(CanonicalJson.sha256(wrong_phase.to_dictionary()) == wrong_hash, "wrong-phase attack must be atomic")

	var insufficient := GameStateData.create_vertical_slice(228)
	for starter_number in range(1, 5):
		ZoneService.move_card(
			insufficient,
			StringName("card-p1-starter-adventurer-%02d" % starter_number),
			&"p1:party",
			&"p1:discard-pile"
		)
	var phase_result := RulesEngine.dispatch(
		insufficient,
		_end_phase_envelope(insufficient, "cmd-insufficient-combat-setup"),
		definitions
	)
	if not bool(phase_result.get("ok", false)):
		_expect(false, "insufficient fixture should enter combat")
		return
	insufficient = phase_result["state"] as GameStateData
	var before_hash := CanonicalJson.sha256(insufficient.to_dictionary())
	var result := RulesEngine.dispatch(
		insufficient,
		_command_envelope(insufficient, command, "cmd-insufficient-combat"),
		definitions
	)
	_expect(str(result.get("error", "")) == "insufficient_combat", "insufficient attack should be rejected")
	_expect(CanonicalJson.sha256(insufficient.to_dictionary()) == before_hash, "failed attack must preserve state and RNG")


func _test_combat_equipment_departure() -> void:
	var definitions := _load_definitions()
	var state := GameStateData.create_vertical_slice(230)
	var equip_result := RulesEngine.dispatch(
		state,
		_equip_item_envelope(
			state,
			&"card-p1-spirit-crystal-01",
			&"card-p1-starter-adventurer-01",
			"cmd-combat-equip"
		),
		definitions
	)
	if not bool(equip_result.get("ok", false)):
		_expect(false, "combat equipment fixture should equip")
		return
	state = equip_result["state"] as GameStateData
	var phase_result := RulesEngine.dispatch(
		state, _end_phase_envelope(state, "cmd-combat-equip-setup"), definitions
	)
	if not bool(phase_result.get("ok", false)):
		_expect(false, "combat equipment fixture should enter combat")
		return
	state = phase_result["state"] as GameStateData
	var preview := CombatService.preview_attack(
		state, &"p1", &"card-monster-skeleton-01", definitions
	)
	_expect(
		(preview.get("participant_ids", []) as Array).size() == 3,
		"equipped combat should reach five with the first three participants"
	)
	var result := RulesEngine.dispatch(
		state,
		_command_envelope(state, {
			"type": "ATTACK_TARGET",
			"target_card_id": "card-monster-skeleton-01",
			"claim_optional_reward": true,
		}, "cmd-combat-equipped-attack"),
		definitions
	)
	_expect(bool(result.get("ok", false)), "equipped skeleton attack should commit")
	if not bool(result.get("ok", false)):
		return
	var defeated := result["state"] as GameStateData
	_expect(
		ZoneService.find_card_zone(defeated, &"card-p1-spirit-crystal-01") == &"p1:discard-pile",
		"equipment should depart with its combat participant"
	)
	var crystal := defeated.cards[&"card-p1-spirit-crystal-01"] as Dictionary
	_expect(
		not (crystal.get("state", {}) as Dictionary).has("equipped_to"),
		"combat departure should clear equipment attachment"
	)
	_expect(InvariantService.validate(defeated).is_empty(), "equipped combat should preserve invariants")


func _test_supply_setup_and_determinism() -> void:
	var first := GameStateData.create_vertical_slice(223)
	var second := GameStateData.create_vertical_slice(223)
	for row_id: StringName in [SupplyService.RECRUIT_ROW_ID, SupplyService.SHOP_ROW_ID]:
		var first_row := first.zones[row_id] as ZoneData
		var second_row := second.zones[row_id] as ZoneData
		_expect(first_row.card_instance_ids.size() == 3, "supply row %s should start with three cards" % row_id)
		_expect(first_row.card_instance_ids == second_row.card_instance_ids, "same seed should produce the same %s order" % row_id)
	_expect((first.zones[SupplyService.RECRUIT_DECK_ID] as ZoneData).card_instance_ids.size() == 3, "recruit deck should retain three vertical-slice cards")
	_expect((first.zones[SupplyService.SHOP_DECK_ID] as ZoneData).card_instance_ids.size() == 5, "shop deck should retain five vertical-slice cards")
	_expect(InvariantService.validate(first).is_empty(), "initial supply should satisfy invariants")


func _test_purchase_and_rest_refill() -> void:
	var definitions := _load_definitions()
	var state := _advance_to_purchase(GameStateData.create_vertical_slice(227), definitions, "cmd-buy-setup")
	if state == null:
		return
	var legal := RulesEngine.get_legal_commands(state, &"p1", definitions)
	var buy_command: Dictionary = {}
	for command: Dictionary in legal:
		if command.get("type") == "BUY_CARD" and command.get("source_row_id") == str(SupplyService.RECRUIT_ROW_ID):
			buy_command = command
			break
	_expect(not buy_command.is_empty(), "purchase phase should expose an affordable recruit")
	if buy_command.is_empty():
		return
	var purchased_id := StringName(buy_command.get("card_instance_id", ""))
	var row_before := (state.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData).card_instance_ids.size()
	var result := RulesEngine.dispatch(state, _command_envelope(state, buy_command, "cmd-buy-card"), definitions)
	_expect(bool(result.get("ok", false)), "legal BUY_CARD should dispatch")
	if not bool(result.get("ok", false)):
		return
	state = result["state"] as GameStateData
	var purchased_card := state.cards[purchased_id] as Dictionary
	var player := state.players[&"p1"] as PlayerStateData
	_expect(StringName(purchased_card.get("owner_id", "")) == &"p1", "purchased card should gain the buyer as owner")
	_expect(ZoneService.find_card_zone(state, purchased_id) == &"p1:discard-pile", "purchased card should enter buyer discard")
	_expect((state.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData).card_instance_ids.size() == row_before - 1, "purchase must not refill the public row immediately")
	_expect(player.spent_purchase_power == int(buy_command.get("effective_cost", 0)), "purchase should track spent power separately")

	var to_rest := RulesEngine.dispatch(state, _end_phase_envelope(state, "cmd-enter-rest"), definitions)
	_expect(bool(to_rest.get("ok", false)), "purchase phase should advance to rest")
	if not bool(to_rest.get("ok", false)):
		return
	state = to_rest["state"] as GameStateData
	var rest_result := RulesEngine.dispatch(state, _end_phase_envelope(state, "cmd-finish-rest"), definitions)
	_expect(bool(rest_result.get("ok", false)), "rest should refill supplies")
	if not bool(rest_result.get("ok", false)):
		return
	state = rest_result["state"] as GameStateData
	_expect((state.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData).card_instance_ids.size() == 3, "rest should refill recruit row to three")
	_expect((state.players[&"p1"] as PlayerStateData).spent_purchase_power == 0, "rest should clear spent purchase power")
	_expect(InvariantService.validate(state).is_empty(), "purchase and refill should preserve invariants")


func _test_purchase_rejection_is_atomic() -> void:
	var definitions := _load_definitions()
	var wrong_phase := GameStateData.create_vertical_slice(229)
	var row := wrong_phase.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData
	var command := {
		"type": "BUY_CARD",
		"card_instance_id": str(row.card_instance_ids[0]),
		"source_row_id": str(SupplyService.RECRUIT_ROW_ID),
	}
	var wrong_hash := CanonicalJson.sha256(wrong_phase.to_dictionary())
	var wrong_result := RulesEngine.dispatch(wrong_phase, _command_envelope(wrong_phase, command, "cmd-buy-wrong-phase"), definitions)
	_expect(str(wrong_result.get("error", "")) == "wrong_phase", "BUY_CARD should be purchase-phase only")
	_expect(CanonicalJson.sha256(wrong_phase.to_dictionary()) == wrong_hash, "wrong-phase purchase must be atomic")

	var poor_state := _advance_to_purchase(GameStateData.create_vertical_slice(233), definitions, "cmd-poor-setup")
	if poor_state == null:
		return
	(poor_state.players[&"p1"] as PlayerStateData).spent_purchase_power = 4
	var poor_row := poor_state.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData
	var poor_command := {
		"type": "BUY_CARD",
		"card_instance_id": str(poor_row.card_instance_ids[0]),
		"source_row_id": str(SupplyService.RECRUIT_ROW_ID),
	}
	var poor_hash := CanonicalJson.sha256(poor_state.to_dictionary())
	var poor_result := RulesEngine.dispatch(poor_state, _command_envelope(poor_state, poor_command, "cmd-too-expensive"), definitions)
	_expect(str(poor_result.get("error", "")) == "insufficient_purchase_power", "unaffordable card should be rejected")
	_expect(CanonicalJson.sha256(poor_state.to_dictionary()) == poor_hash, "failed purchase must preserve the state hash")


func _test_supply_depletion_event_once() -> void:
	var state := GameStateData.create_vertical_slice(239)
	var row := state.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData
	for card_instance_id: StringName in row.card_instance_ids.duplicate():
		ZoneService.move_card(state, card_instance_id, SupplyService.RECRUIT_ROW_ID, &"p1:discard-pile")
	var events: Array[Dictionary] = []
	var error := SupplyService.refill_row(state, SupplyService.RECRUIT_DECK_ID, SupplyService.RECRUIT_ROW_ID, 3, events)
	_expect(error.is_empty(), "supply depletion fixture should refill")
	_expect(_events_contain(events, "supply_deck_depleted"), "drawing the final public supply card should announce depletion")
	var second_events: Array[Dictionary] = []
	SupplyService.refill_row(state, SupplyService.RECRUIT_DECK_ID, SupplyService.RECRUIT_ROW_ID, 3, second_events)
	_expect(not _events_contain(second_events, "supply_deck_depleted"), "depletion should not be announced repeatedly")


func _test_market_refresh_legality_and_commit() -> void:
	var definitions := _load_definitions()
	var state := _advance_to_purchase(
		GameStateData.create_vertical_slice(240), definitions, "cmd-refresh-setup"
	)
	if state == null:
		return
	var legal := RulesEngine.get_legal_commands(state, &"p1", definitions)
	var refresh_legal: Dictionary = {}
	for command: Dictionary in legal:
		if command.get("type") == "REFRESH_MARKET":
			refresh_legal = command
			break
	_expect(not refresh_legal.is_empty(), "purchase phase should expose one market refresh intent")
	_expect(
		(refresh_legal.get("discard_card_ids", []) as Array).size() == 5,
		"refresh intent should expose every owned hand card as a cost choice"
	)
	var player := state.players[&"p1"] as PlayerStateData
	var hand := state.zones[player.zone_ids[&"hand"]] as ZoneData
	var discard_card_id := hand.card_instance_ids[0]
	var row := state.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData
	var selected_ids: Array[StringName] = [row.card_instance_ids[0], row.card_instance_ids[1]]
	var original_row_size := row.card_instance_ids.size()
	var command := {
		"type": "REFRESH_MARKET",
		"discard_card_id": str(discard_card_id),
		"row_id": str(SupplyService.RECRUIT_ROW_ID),
		"card_instance_ids": _string_names_to_strings(selected_ids),
	}
	var result := RulesEngine.dispatch(
		state,
		_command_envelope(state, command, "cmd-refresh-market"),
		definitions
	)
	_expect(bool(result.get("ok", false)), "valid market refresh should commit")
	if not bool(result.get("ok", false)):
		return
	var refreshed := result["state"] as GameStateData
	player = refreshed.players[&"p1"] as PlayerStateData
	_expect(
		ZoneService.find_card_zone(refreshed, discard_card_id) == player.zone_ids[&"discard_pile"],
		"refresh should discard exactly one hand card as its cost"
	)
	_expect(
		(refreshed.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData).card_instance_ids.size()
			== original_row_size,
		"refresh should replace exactly the number removed from the row"
	)
	_expect(bool(player.turn_facts.get(&"market_refreshed", false)), "refresh should record its once-per-turn fact")
	_expect(_events_contain(result["events"], "market_refreshed"), "refresh should emit a committed event")
	_expect(InvariantService.validate(refreshed).is_empty(), "market refresh should preserve invariants")
	var post_legal := RulesEngine.get_legal_commands(refreshed, &"p1", definitions)
	_expect(not _commands_contain(post_legal, "REFRESH_MARKET"), "second refresh should not remain legal this turn")
	var refreshed_hand := refreshed.zones[player.zone_ids[&"hand"]] as ZoneData
	var refreshed_row := refreshed.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData
	var repeat_command := {
		"type": "REFRESH_MARKET",
		"discard_card_id": str(refreshed_hand.card_instance_ids[0]),
		"row_id": str(SupplyService.RECRUIT_ROW_ID),
		"card_instance_ids": [str(refreshed_row.card_instance_ids[0])],
	}
	var refreshed_hash := CanonicalJson.sha256(refreshed.to_dictionary())
	var repeat_result := RulesEngine.dispatch(
		refreshed,
		_command_envelope(refreshed, repeat_command, "cmd-refresh-market-again"),
		definitions
	)
	_expect(
		str(repeat_result.get("error", "")) == "market_refresh_already_used",
		"refresh should be rejected after its once-per-turn use"
	)
	_expect(
		CanonicalJson.sha256(refreshed.to_dictionary()) == refreshed_hash,
		"rejected repeat refresh must be atomic"
	)


func _test_market_refresh_rejection_is_atomic() -> void:
	var definitions := _load_definitions()
	var wrong_phase := GameStateData.create_vertical_slice(242)
	var hand := wrong_phase.zones[&"p1:hand"] as ZoneData
	var row := wrong_phase.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData
	var command := {
		"type": "REFRESH_MARKET",
		"discard_card_id": str(hand.card_instance_ids[0]),
		"row_id": str(SupplyService.RECRUIT_ROW_ID),
		"card_instance_ids": [str(row.card_instance_ids[0])],
	}
	var wrong_phase_hash := CanonicalJson.sha256(wrong_phase.to_dictionary())
	var wrong_phase_result := RulesEngine.dispatch(
		wrong_phase,
		_command_envelope(wrong_phase, command, "cmd-refresh-wrong-phase"),
		definitions
	)
	_expect(str(wrong_phase_result.get("error", "")) == "wrong_phase", "refresh must be purchase-phase only")
	_expect(
		CanonicalJson.sha256(wrong_phase.to_dictionary()) == wrong_phase_hash,
		"wrong-phase refresh must be atomic"
	)

	var invalid := _advance_to_purchase(
		GameStateData.create_vertical_slice(244), definitions, "cmd-refresh-invalid-setup"
	)
	if invalid == null:
		return
	hand = invalid.zones[&"p1:hand"] as ZoneData
	row = invalid.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData
	var repeated_id := str(row.card_instance_ids[0])
	command = {
		"type": "REFRESH_MARKET",
		"discard_card_id": str(hand.card_instance_ids[0]),
		"row_id": str(SupplyService.RECRUIT_ROW_ID),
		"card_instance_ids": [repeated_id, repeated_id],
	}
	var invalid_hash := CanonicalJson.sha256(invalid.to_dictionary())
	var invalid_result := RulesEngine.dispatch(
		invalid,
		_command_envelope(invalid, command, "cmd-refresh-duplicate-card"),
		definitions
	)
	_expect(
		str(invalid_result.get("error", "")) == "duplicate_refresh_card",
		"refresh selection must not contain duplicate cards"
	)
	_expect(CanonicalJson.sha256(invalid.to_dictionary()) == invalid_hash, "invalid refresh must preserve state")


func _test_market_refresh_selection_order_is_deterministic() -> void:
	var definitions := _load_definitions()
	var state := _advance_to_purchase(
		GameStateData.create_vertical_slice(246), definitions, "cmd-refresh-order-setup"
	)
	if state == null:
		return
	var hand := state.zones[&"p1:hand"] as ZoneData
	var row := state.zones[SupplyService.SHOP_ROW_ID] as ZoneData
	var first_id := str(row.card_instance_ids[0])
	var second_id := str(row.card_instance_ids[1])
	var base_command := {
		"type": "REFRESH_MARKET",
		"discard_card_id": str(hand.card_instance_ids[0]),
		"row_id": str(SupplyService.SHOP_ROW_ID),
		"card_instance_ids": [first_id, second_id],
	}
	var reversed_command := base_command.duplicate(true)
	reversed_command["card_instance_ids"] = [second_id, first_id]
	var first := RulesEngine.dispatch(
		state,
		_command_envelope(state, base_command, "cmd-refresh-order"),
		definitions
	)
	var reversed := RulesEngine.dispatch(
		state,
		_command_envelope(state, reversed_command, "cmd-refresh-order"),
		definitions
	)
	_expect(bool(first.get("ok", false)) and bool(reversed.get("ok", false)), "both selection orders should refresh")
	_expect(
		first.get("after_hash") == reversed.get("after_hash"),
		"selection click order must not alter deterministic refresh results"
	)


func _test_market_refresh_hud_integration() -> void:
	var packed := load("res://scenes/boot/main.tscn") as PackedScene
	var app := packed.instantiate() as GameApp
	root.add_child(app)
	await process_frame
	for index in 3:
		var result := app.session.end_phase()
		_expect(bool(result.get("ok", false)), "HUD fixture phase %d should advance" % index)
	_expect(app.session.state.phase == &"purchase", "HUD fixture should reach purchase phase")
	var refresh_cost_buttons := 0
	for child: Node in app.hud.hand_actions.get_children():
		if child is Button and "刷新代價" in (child as Button).text:
			refresh_cost_buttons += 1
	var refresh_selectors := 0
	var refresh_confirm_buttons := 0
	for child: Node in app.hud.market_actions.get_children():
		if child is HBoxContainer:
			for row_child: Node in child.get_children():
				if row_child is CheckBox and (row_child as CheckBox).text == "刷新":
					refresh_selectors += 1
		elif child is Button and (child as Button).text.begins_with("確認刷新"):
			refresh_confirm_buttons += 1
	_expect(refresh_cost_buttons == 5, "purchase HUD should expose each hand card as refresh cost")
	_expect(refresh_selectors == 6, "purchase HUD should expose all six public cards for refresh")
	_expect(refresh_confirm_buttons == 2, "purchase HUD should expose one confirmation per row")
	app.queue_free()


func _test_combat_hud_integration() -> void:
	var packed := load("res://scenes/boot/main.tscn") as PackedScene
	var app := packed.instantiate() as GameApp
	root.add_child(app)
	await process_frame
	var result := app.session.end_phase()
	_expect(bool(result.get("ok", false)), "combat HUD fixture should enter combat phase")
	var attack_buttons := 0
	var preview_labels := 0
	for child: Node in app.hud.market_actions.get_children():
		if child is Button and (child as Button).text.begins_with("討伐"):
			attack_buttons += 1
		elif child is Label and "參戰：" in (child as Label).text:
			preview_labels += 1
	_expect(attack_buttons == 4, "combat HUD should show optional skeleton and mandatory draw rewards")
	_expect(preview_labels == 3, "combat HUD should preview participants for each target")
	app.queue_free()


func _test_play_adventurer_capacity_and_equipment_departure() -> void:
	var definitions := _load_definitions()
	var state := GameStateData.create_vertical_slice(241)
	var equip_result := RulesEngine.dispatch(
		state,
		_equip_item_envelope(
			state,
			&"card-p1-spirit-crystal-01",
			&"card-p1-starter-adventurer-01",
			"cmd-party-fixture-equip"
		),
		definitions
	)
	_expect(bool(equip_result.get("ok", false)), "party fixture should equip the outgoing adventurer")
	if not bool(equip_result.get("ok", false)):
		return
	state = equip_result["state"] as GameStateData
	var recruit_id := _find_instance_by_definition(state, &"base:adventurer/adventurer-09")
	_expect(not recruit_id.is_empty(), "party fixture should find an official recruit")
	if recruit_id.is_empty():
		return
	var source_zone := ZoneService.find_card_zone(state, recruit_id)
	var move_result := ZoneService.move_card(state, recruit_id, source_zone, &"p1:hand")
	_expect(bool(move_result.get("ok", false)), "party fixture should move the recruit into hand")
	(state.cards[recruit_id] as Dictionary)["owner_id"] = "p1"
	var result := RulesEngine.dispatch(
		state,
		_command_envelope(state, {
			"type": "PLAY_ADVENTURER",
			"card_instance_id": str(recruit_id),
		}, "cmd-play-adventurer"),
		definitions
	)
	_expect(bool(result.get("ok", false)), "official adventurer should join during an action phase")
	if not bool(result.get("ok", false)):
		return
	var played := result["state"] as GameStateData
	var party := played.zones[&"p1:party"] as ZoneData
	_expect(party.card_instance_ids.size() == 5, "party capacity should remain five")
	_expect(party.card_instance_ids.back() == recruit_id, "new adventurer should enter at the right edge")
	_expect(
		ZoneService.find_card_zone(played, &"card-p1-starter-adventurer-01") == &"p1:discard-pile",
		"full party should remove its leftmost adventurer"
	)
	_expect(
		ZoneService.find_card_zone(played, &"card-p1-spirit-crystal-01") == &"p1:discard-pile",
		"equipment should leave with its outgoing adventurer"
	)
	var crystal := played.cards[&"card-p1-spirit-crystal-01"] as Dictionary
	_expect(
		not (crystal.get("state", {}) as Dictionary).has("equipped_to"),
		"departing equipment should clear its target link"
	)
	_expect(InvariantService.validate(played).is_empty(), "party replacement should preserve invariants")


func _test_use_item_draw_and_rest_cleanup() -> void:
	var definitions := _load_definitions()
	var state := GameStateData.create_vertical_slice(251)
	var player := state.players[&"p1"] as PlayerStateData
	var hand := state.zones[player.zone_ids[&"hand"]] as ZoneData
	for raw_card_id: Variant in hand.card_instance_ids.duplicate().slice(0, 2):
		ZoneService.move_card(state, StringName(str(raw_card_id)), &"p1:hand", &"p1:draw-pile")
	var item_id := _find_instance_by_definition(state, &"base:resource/resource-08")
	_expect(not item_id.is_empty(), "item fixture should find Sakura Fruit")
	if item_id.is_empty():
		return
	var source_zone := ZoneService.find_card_zone(state, item_id)
	var move_result := ZoneService.move_card(state, item_id, source_zone, &"p1:hand")
	_expect(bool(move_result.get("ok", false)), "item fixture should move Sakura Fruit into hand")
	(state.cards[item_id] as Dictionary)["owner_id"] = "p1"
	var result := RulesEngine.dispatch(
		state,
		_command_envelope(state, {
			"type": "USE_ITEM",
			"card_instance_id": str(item_id),
		}, "cmd-use-item"),
		definitions
	)
	_expect(bool(result.get("ok", false)), "Sakura Fruit should be usable during an action phase")
	if not bool(result.get("ok", false)):
		return
	state = result["state"] as GameStateData
	_expect(ZoneService.find_card_zone(state, item_id) == &"p1:play-area", "used item should remain in play area until rest")
	_expect((state.zones[&"p1:hand"] as ZoneData).card_instance_ids.size() == 5, "Sakura Fruit should draw two cards")
	var resolved_draw := false
	for event: Dictionary in result["events"]:
		if event.get("type") == "effect_resolved" and event.get("op") == "draw":
			resolved_draw = int(event.get("drawn_count", 0)) == 2
	_expect(resolved_draw, "item draw should use the shared effect resolver")
	for index in 5:
		var phase_result := RulesEngine.dispatch(
			state,
			_end_phase_envelope(state, "cmd-item-rest-%d" % index),
			definitions
		)
		_expect(bool(phase_result.get("ok", false)), "item rest phase %d should dispatch" % index)
		if not bool(phase_result.get("ok", false)):
			return
		state = phase_result["state"] as GameStateData
	_expect(ZoneService.find_card_zone(state, item_id) != &"p1:play-area", "rest should clean used items from play area")
	_expect(InvariantService.validate(state).is_empty(), "item use and rest should preserve invariants")


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
	var equip_result := session.equip_item(&"card-p1-spirit-crystal-01", &"card-p1-starter-adventurer-01")
	_expect(bool(equip_result.get("ok", false)), "session should submit an equipment command")
	for index in 5:
		var result := session.end_phase()
		_expect(bool(result.get("ok", false)), "session should advance player-one phase %d" % index)
	_expect(session.state.active_player_id == &"p2", "session should expose player two after player one rests")
	var legal := session.get_legal_commands()
	var all_for_player_two := not legal.is_empty()
	for command: Dictionary in legal:
		all_for_player_two = all_for_player_two and command.get("actor_id") == "p2"
	_expect(all_for_player_two, "session default legal query should follow active player")


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
	var definitions := _load_definitions()
	var equip_result := RulesEngine.dispatch(
		state,
		_equip_item_envelope(state, &"card-p1-spirit-crystal-01", &"card-p1-starter-adventurer-01", "cmd-snapshot-equipment"),
		definitions
	)
	_expect(bool(equip_result.get("ok", false)), "snapshot fixture should equip the crystal")
	if bool(equip_result.get("ok", false)):
		state = equip_result["state"] as GameStateData
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
		_expect(ZoneService.find_card_zone(restored, &"card-p1-spirit-crystal-01") == &"p1:equipment", "snapshot should preserve the equipment zone")
		var restored_crystal := restored.cards[&"card-p1-spirit-crystal-01"] as Dictionary
		_expect((restored_crystal.get("state", {}) as Dictionary).get("equipped_to") == "card-p1-starter-adventurer-01", "snapshot should preserve equipment attachment")
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


func _equip_item_envelope(
	state: GameStateData,
	card_instance_id: StringName,
	target_card_id: StringName,
	command_id: String
) -> Dictionary:
	return {
		"protocol_version": 1,
		"game_id": str(state.game_id),
		"command_id": command_id,
		"actor_id": str(state.active_player_id),
		"expected_revision": state.revision,
		"command": {
			"type": "EQUIP_ITEM",
			"card_instance_id": str(card_instance_id),
			"target_card_id": str(target_card_id),
		},
	}


func _load_definitions() -> Dictionary:
	var registry := ContentRegistry.new()
	var errors := registry.load_pack("res://content/packs/base_vertical_slice.json")
	_expect(errors.is_empty(), "test content definitions should load: %s" % "; ".join(errors))
	return registry.definitions.duplicate()


func _command_envelope(state: GameStateData, command: Dictionary, command_id: String) -> Dictionary:
	return {
		"protocol_version": 1,
		"game_id": str(state.game_id),
		"command_id": command_id,
		"actor_id": str(state.active_player_id),
		"expected_revision": state.revision,
		"command": command.duplicate(true),
	}


func _find_instance_by_definition(state: GameStateData, definition_id: StringName) -> StringName:
	for card_instance_id: StringName in state.cards:
		var card := state.cards[card_instance_id] as Dictionary
		if StringName(card.get("definition_id", "")) == definition_id:
			return card_instance_id
	return &""


func _string_names_to_strings(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value: StringName in values:
		result.append(str(value))
	return result


func _advance_to_purchase(
	state: GameStateData,
	definitions: Dictionary,
	command_prefix: String
) -> GameStateData:
	for index in 3:
		var result := RulesEngine.dispatch(
			state,
			_end_phase_envelope(state, "%s-%d" % [command_prefix, index]),
			definitions
		)
		_expect(bool(result.get("ok", false)), "purchase setup phase %d should dispatch" % index)
		if not bool(result.get("ok", false)):
			return null
		state = result["state"] as GameStateData
	return state


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _events_contain(events: Array[Dictionary], event_type: String) -> bool:
	for event: Dictionary in events:
		if str(event.get("type", "")) == event_type:
			return true
	return false


func _commands_contain(commands: Array[Dictionary], command_type: String) -> bool:
	for command: Dictionary in commands:
		if str(command.get("type", "")) == command_type:
			return true
	return false
