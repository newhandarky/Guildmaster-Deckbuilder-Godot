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
	_test_automaton_archer_pending_choice()
	_test_automaton_warrior_discard_choice()
	_test_gargoyle_recruit_choice()
	_test_public_row_gain_monsters()
	_test_fire_elemental_hand_redraw()
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
	await _test_pending_choice_hud_integration()
	await _test_discard_choice_hud_integration()
	await _test_gargoyle_choice_hud_integration()
	await _test_shop_gain_choice_hud_integration()
	await _test_fire_elemental_hud_integration()
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
	_expect(registry.definitions.size() == 23, "vertical slice should load twenty-three base definitions")
	var arcane_slime := registry.definitions.get(&"base:monster/monster-04") as CardDefinition
	_expect(
		arcane_slime != null and arcane_slime.copies == 3 and arcane_slime.combat == 5 \
				and arcane_slime.purchase_power == 2 and arcane_slime.honor == 4,
		"arcane slime should use the confirmed 3 copies and 5/2/4 values"
	)
	var goblin_thief := registry.definitions.get(&"base:monster/monster-07") as CardDefinition
	_expect(
		goblin_thief != null and goblin_thief.copies == 2 and goblin_thief.combat == 5 \
				and goblin_thief.purchase_power == 2 and goblin_thief.honor == 4,
		"goblin thief should use the confirmed 2 copies and 5/2/4 values"
	)
	var ogre := registry.definitions.get(&"base:monster/monster-08") as CardDefinition
	_expect(
		ogre != null and ogre.copies == 2 and ogre.combat == 6 \
				and ogre.purchase_power == 2 and ogre.honor == 4,
		"ogre should use the confirmed 2 copies and 6/2/4 values"
	)
	var warrior := registry.definitions.get(&"base:monster/monster-11") as CardDefinition
	_expect(
		warrior != null and warrior.copies == 2 and warrior.combat == 4 \
				and warrior.purchase_power == 2 and warrior.honor == 3,
		"automaton warrior should use the confirmed 2 copies and 4/2/3 values"
	)
	var gargoyle := registry.definitions.get(&"base:monster/monster-12") as CardDefinition
	_expect(
		gargoyle != null and gargoyle.copies == 2 and gargoyle.combat == 6 \
				and gargoyle.purchase_power == 2 and gargoyle.honor == 4,
		"gargoyle should use the confirmed 2 copies and 6/2/4 values"
	)
	var fire_elemental := registry.definitions.get(&"base:monster/monster-13") as CardDefinition
	_expect(
		fire_elemental != null and fire_elemental.copies == 2 \
				and fire_elemental.combat == 4 and fire_elemental.purchase_power == 1 \
				and fire_elemental.honor == 3,
		"fire elemental should use the confirmed 2 copies and 4/1/3 values"
	)
	_expect(not registry.definitions.has(&"custom:adventurer/melee-01"), "custom adventurers must stay disabled")
	_expect(not registry.pack_fingerprint.is_empty(), "content pack should expose a deterministic fingerprint")


func _test_content_pack_reload() -> void:
	var registry := ContentRegistry.new()
	var first_errors := registry.load_pack("res://content/packs/base_vertical_slice.json")
	var first_fingerprint := registry.pack_fingerprint
	var second_errors := registry.load_pack("res://content/packs/base_vertical_slice.json")
	_expect(first_errors.is_empty() and second_errors.is_empty(), "content pack should be safely reloadable")
	_expect(registry.definitions.size() == 23, "content reload must not retain duplicate definitions")
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
	_expect(state.cards.size() == 56, "setup should create player cards, twenty-two monsters, and fourteen market cards")
	for player_id: StringName in state.turn_order:
		var player := state.players[player_id] as PlayerStateData
		var party := state.zones[player.zone_ids[&"party"]] as ZoneData
		var hand := state.zones[player.zone_ids[&"hand"]] as ZoneData
		var draw_pile := state.zones[player.zone_ids[&"draw_pile"]] as ZoneData
		var discard_pile := state.zones[player.zone_ids[&"discard_pile"]] as ZoneData
		var removed := state.zones[player.zone_ids[&"removed"]] as ZoneData
		_expect(party.card_instance_ids.size() == 5, "player %s should start with five adventurers in party" % player_id)
		_expect(hand.card_instance_ids.size() == 5, "player %s should start with five cards in hand" % player_id)
		_expect(draw_pile.card_instance_ids.is_empty(), "official setup should not shuffle starting hand into draw pile")
		_expect(discard_pile.card_instance_ids.is_empty(), "official setup should start with an empty discard pile")
		_expect(removed.card_instance_ids.is_empty(), "official setup should start with an empty removed zone")
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
	pending.effect_state = {
		"type": "pending_choice",
		"choice_id": "choice-test",
		"actor_id": "p1",
		"op": "choose_remove_card",
		"prompt": "test",
		"source_zone_id": "p1:hand",
		"source_zone_key": "hand",
		"destination_zone_id": "p1:removed",
		"eligible_card_ids": ["card-p1-summoning-stone-01"],
		"min_selections": 0,
		"max_selections": 1,
		"effect_index": 0,
		"source_card_instance_id": "test-source",
	}
	_expect(
		not _commands_contain(RulesEngine.get_legal_commands(pending, &"p1"), "END_PHASE"),
		"pending effect should expose no END_PHASE"
	)
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
	_expect(cycle.card_instance_ids.size() == 19, "vertical slice cycle should retain nineteen monsters")
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


func _test_automaton_archer_pending_choice() -> void:
	var definitions := _load_definitions()
	var state := GameStateData.create_vertical_slice(235)
	var archer_id := &"card-monster-automaton-archer-01"
	var expose_error := _expose_monster(
		state, archer_id, &"card-monster-rabbit-demon-01"
	)
	_expect(expose_error.is_empty(), "archer fixture should expose the target: %s" % expose_error)
	if not expose_error.is_empty():
		return
	var phase_result := RulesEngine.dispatch(
		state,
		_end_phase_envelope(state, "cmd-archer-combat-setup"),
		definitions
	)
	_expect(bool(phase_result.get("ok", false)), "archer fixture should enter combat")
	if not bool(phase_result.get("ok", false)):
		return
	state = phase_result["state"] as GameStateData
	var preview := CombatService.preview_attack(state, &"p1", archer_id, definitions)
	_expect(bool(preview.get("legal", false)), "automaton archer should be attackable")
	_expect(
		preview.get("reward_summary") == "可從手牌移除 1 張、取得此卡（購買力 2／榮譽 3）",
		"archer preview should describe its deferred removal reward"
	)
	_expect(
		bool(preview.get("deferred_choice", false)) and not bool(preview.get("optional_reward", true)),
		"archer removal should defer its optional decision instead of duplicating attack buttons"
	)
	var attack_result := RulesEngine.dispatch(
		state,
		_command_envelope(state, {
			"type": "ATTACK_TARGET",
			"target_card_id": str(archer_id),
			"claim_optional_reward": true,
		}, "cmd-attack-archer"),
		definitions
	)
	_expect(bool(attack_result.get("ok", false)), "archer attack should commit into a pending choice")
	if not bool(attack_result.get("ok", false)):
		return
	var pending := attack_result["state"] as GameStateData
	var player := pending.players[&"p1"] as PlayerStateData
	_expect(
		StringName(pending.effect_state.get("type", "")) == &"pending_choice",
		"archer reward should create a serializable pending choice"
	)
	_expect(
		ZoneService.find_card_zone(pending, archer_id) == player.zone_ids[&"discard_pile"],
		"archer should be claimed before its removal choice resolves"
	)
	var choice_commands := RulesEngine.get_legal_commands(pending, &"p1", definitions)
	_expect(choice_commands.size() == 6, "five hand choices plus one optional skip should be legal")
	var only_choice_commands := not choice_commands.is_empty()
	for command: Dictionary in choice_commands:
		only_choice_commands = only_choice_commands and command.get("type") == "RESOLVE_CHOICE"
	_expect(only_choice_commands, "pending choice should lock every unrelated command")
	_expect(
		not _commands_contain(choice_commands, "END_PHASE"),
		"pending choice must block phase advancement"
	)
	var pending_snapshot := SnapshotCodec.encode(pending, "content-test", "rules-test")
	var decoded := SnapshotCodec.decode(pending_snapshot, "content-test", "rules-test")
	_expect(bool(decoded.get("ok", false)), "snapshot should round-trip a pending choice")
	if bool(decoded.get("ok", false)):
		_expect(
			CanonicalJson.stringify((decoded["state"] as GameStateData).effect_state)
				== CanonicalJson.stringify(pending.effect_state),
			"pending choice snapshot should preserve every choice field"
		)

	var before_invalid := CanonicalJson.sha256(pending.to_dictionary())
	var invalid := RulesEngine.dispatch(
		pending,
		_command_envelope(pending, {
			"type": "RESOLVE_CHOICE",
			"choice_id": str(pending.effect_state.get("choice_id", "")),
			"card_instance_id": "card-p2-summoning-stone-01",
			"skip": false,
		}, "cmd-invalid-archer-choice"),
		definitions
	)
	_expect(
		str(invalid.get("error", "")) == "ineligible_choice_card",
		"choice must reject a card outside the captured hand"
	)
	_expect(
		CanonicalJson.sha256(pending.to_dictionary()) == before_invalid,
		"invalid removal choice must remain atomic"
	)
	var selected_card_id := StringName(
		(pending.effect_state.get("eligible_card_ids", []) as Array)[0]
	)
	var resolve_result := RulesEngine.dispatch(
		pending,
		_command_envelope(pending, {
			"type": "RESOLVE_CHOICE",
			"choice_id": str(pending.effect_state.get("choice_id", "")),
			"card_instance_id": str(selected_card_id),
			"skip": false,
		}, "cmd-resolve-archer-choice"),
		definitions
	)
	_expect(bool(resolve_result.get("ok", false)), "eligible hand card should resolve the choice")
	if bool(resolve_result.get("ok", false)):
		var resolved := resolve_result["state"] as GameStateData
		_expect(resolved.effect_state.is_empty(), "resolved choice should clear pending state")
		_expect(
			ZoneService.find_card_zone(resolved, selected_card_id) == player.zone_ids[&"removed"],
			"selected card should enter the permanent removed zone"
		)
		_expect(
			_commands_contain(RulesEngine.get_legal_commands(resolved, &"p1", definitions), "END_PHASE"),
			"normal combat commands should resume after resolving the choice"
		)
		_expect(InvariantService.validate(resolved).is_empty(), "resolved removal should preserve invariants")

	var skip_state := GameStateData.create_vertical_slice(236)
	_expose_monster(skip_state, archer_id, &"card-monster-rabbit-demon-01")
	phase_result = RulesEngine.dispatch(
		skip_state,
		_end_phase_envelope(skip_state, "cmd-archer-skip-combat-setup"),
		definitions
	)
	skip_state = phase_result["state"] as GameStateData
	attack_result = RulesEngine.dispatch(
		skip_state,
		_command_envelope(skip_state, {
			"type": "ATTACK_TARGET",
			"target_card_id": str(archer_id),
			"claim_optional_reward": true,
		}, "cmd-attack-archer-skip"),
		definitions
	)
	skip_state = attack_result["state"] as GameStateData
	var skip_command: Dictionary = {}
	for command: Dictionary in RulesEngine.get_legal_commands(skip_state, &"p1", definitions):
		if bool(command.get("skip", false)):
			skip_command = command
			break
	var hand_size := (skip_state.zones[&"p1:hand"] as ZoneData).card_instance_ids.size()
	var skip_result := RulesEngine.dispatch(
		skip_state,
		_command_envelope(skip_state, skip_command, "cmd-skip-archer-choice"),
		definitions
	)
	_expect(bool(skip_result.get("ok", false)), "optional archer removal should allow skipping")
	if bool(skip_result.get("ok", false)):
		var skipped := skip_result["state"] as GameStateData
		_expect(skipped.effect_state.is_empty(), "skipping should clear the pending choice")
		_expect(
			(skipped.zones[&"p1:hand"] as ZoneData).card_instance_ids.size() == hand_size,
			"skipping removal should preserve the hand"
		)
		_expect(
			(skipped.zones[&"p1:removed"] as ZoneData).card_instance_ids.is_empty(),
			"skipping removal should leave the removed zone empty"
		)


func _test_automaton_warrior_discard_choice() -> void:
	var definitions := _load_definitions()
	var no_candidate := GameStateData.create_vertical_slice(237)
	var no_candidate_events: Array[Dictionary] = []
	var no_candidate_error := EffectResolver.resolve(
		no_candidate,
		&"p1",
		[{
			"op": "choose_remove_card",
			"amount": 1,
			"source_zone_key": "discard_pile",
			"optional": true,
		}],
		no_candidate_events
	)
	_expect(no_candidate_error.is_empty(), "empty discard removal effect should resolve cleanly")
	_expect(
		no_candidate.effect_state.is_empty(),
		"empty discard pile must not create a pending choice"
	)
	_expect(
		no_candidate_events.size() == 1 \
				and no_candidate_events[0].get("reason") == "no_eligible_candidates",
		"empty discard effect should emit a deterministic no-candidate resolution"
	)
	_expect(
		not _events_contain(no_candidate_events, "choice_requested"),
		"empty discard effect must not request a choice"
	)

	var state := GameStateData.create_vertical_slice(239)
	var warrior_id := &"card-monster-automaton-warrior-01"
	var expose_error := _expose_monster(
		state, warrior_id, &"card-monster-rabbit-demon-01"
	)
	_expect(expose_error.is_empty(), "warrior fixture should expose the target: %s" % expose_error)
	if not expose_error.is_empty():
		return
	var phase_result := RulesEngine.dispatch(
		state,
		_end_phase_envelope(state, "cmd-warrior-combat-setup"),
		definitions
	)
	_expect(bool(phase_result.get("ok", false)), "warrior fixture should enter combat")
	if not bool(phase_result.get("ok", false)):
		return
	state = phase_result["state"] as GameStateData
	var preview := CombatService.preview_attack(state, &"p1", warrior_id, definitions)
	_expect(
		preview.get("reward_summary") \
				== "可從自己的棄牌堆移除 1 張、取得此卡（購買力 2／榮譽 3）",
		"warrior preview should show its exact source and printed values"
	)
	var attack_envelope := _command_envelope(state, {
		"type": "ATTACK_TARGET",
		"target_card_id": str(warrior_id),
		"claim_optional_reward": true,
	}, "cmd-attack-warrior")
	var attack_result := RulesEngine.dispatch(state, attack_envelope, definitions)
	var repeated_attack := RulesEngine.dispatch(state.clone_state(), attack_envelope, definitions)
	_expect(bool(attack_result.get("ok", false)), "warrior attack should commit")
	_expect(
		attack_result.get("after_hash") == repeated_attack.get("after_hash"),
		"identical warrior attacks should produce the same pending-state hash"
	)
	if not bool(attack_result.get("ok", false)):
		return
	var pending := attack_result["state"] as GameStateData
	var player := pending.players[&"p1"] as PlayerStateData
	var discard := pending.zones[player.zone_ids[&"discard_pile"]] as ZoneData
	_expect(
		StringName(pending.effect_state.get("source_zone_key", "")) == &"discard_pile" \
				and StringName(pending.effect_state.get("source_zone_id", "")) \
				== player.zone_ids[&"discard_pile"],
		"warrior choice source must be the active player's discard pile"
	)
	_expect(
		(pending.effect_state.get("eligible_card_ids", []) as Array).size() \
				== discard.card_instance_ids.size() - 1 \
				and str(warrior_id) not in (
					pending.effect_state.get("eligible_card_ids", []) as Array
				),
		"warrior should lock the discard pile before the defeated card is claimed"
	)
	var choice_commands := RulesEngine.get_legal_commands(pending, &"p1", definitions)
	_expect(
		choice_commands.size() \
				== (pending.effect_state.get("eligible_card_ids", []) as Array).size() + 1,
		"warrior legal commands should include each discard card and one skip"
	)
	for command: Dictionary in choice_commands:
		if bool(command.get("skip", false)):
			continue
		_expect(
			ZoneService.find_card_zone(
				pending, StringName(command.get("card_instance_id", ""))
			) == player.zone_ids[&"discard_pile"],
			"warrior legal choice must not leak cards from another zone"
		)

	var attack_events := attack_result.get("events", []) as Array
	var departure_index := -1
	var requested_index := -1
	var claim_index := -1
	var defeated_index := -1
	for index in attack_events.size():
		var event := attack_events[index] as Dictionary
		if event.get("reason") == "combat_departure" and departure_index < 0:
			departure_index = index
		elif event.get("type") == "choice_requested":
			requested_index = index
		elif event.get("reason") == "defeated_monster_claimed":
			claim_index = index
		elif event.get("type") == "enemy_defeated":
			defeated_index = index
	_expect(
		departure_index >= 0 and departure_index < requested_index \
				and requested_index < claim_index and claim_index < defeated_index,
		"warrior events should order departure, choice request, claim, then defeat"
	)

	var snapshot := SnapshotCodec.encode(pending, "content-warrior", "rules-warrior")
	var decoded := SnapshotCodec.decode(snapshot, "content-warrior", "rules-warrior")
	_expect(bool(decoded.get("ok", false)), "warrior pending choice should survive snapshot restore")
	if bool(decoded.get("ok", false)):
		_expect(
			CanonicalJson.stringify((decoded["state"] as GameStateData).effect_state)
				== CanonicalJson.stringify(pending.effect_state),
			"warrior snapshot should preserve its locked discard candidates"
		)

	var choice_id := str(pending.effect_state.get("choice_id", ""))
	for invalid_card_id: String in [
		"card-p1-summoning-stone-01",
		"card-p1-starter-adventurer-04",
		"card-p2-summoning-stone-01",
	]:
		var before_invalid := CanonicalJson.sha256(pending.to_dictionary())
		var invalid := RulesEngine.dispatch(
			pending,
			_command_envelope(pending, {
				"type": "RESOLVE_CHOICE",
				"choice_id": choice_id,
				"card_instance_id": invalid_card_id,
				"skip": false,
			}, "cmd-invalid-warrior-%s" % invalid_card_id),
			definitions
		)
		_expect(
			str(invalid.get("error", "")) == "ineligible_choice_card",
			"warrior must reject hand, party, and opponent cards"
		)
		_expect(
			CanonicalJson.sha256(pending.to_dictionary()) == before_invalid,
			"wrong-source warrior choice must remain atomic"
		)

	var selected_card_id := StringName(
		(pending.effect_state.get("eligible_card_ids", []) as Array)[0]
	)
	var tampered := pending.clone_state()
	var tamper_move := ZoneService.move_card(
		tampered,
		selected_card_id,
		player.zone_ids[&"discard_pile"],
		player.zone_ids[&"hand"]
	)
	_expect(bool(tamper_move.get("ok", false)), "tamper fixture should move a locked candidate")
	var tampered_hash := CanonicalJson.sha256(tampered.to_dictionary())
	var tampered_result := RulesEngine.dispatch(
		tampered,
		_command_envelope(tampered, {
			"type": "RESOLVE_CHOICE",
			"choice_id": choice_id,
			"card_instance_id": str(selected_card_id),
			"skip": false,
		}, "cmd-tampered-warrior-choice"),
		definitions
	)
	_expect(
		str(tampered_result.get("error", "")).begins_with("invalid_state:"),
		"dispatch should revalidate a stale locked discard candidate"
	)
	_expect(
		tampered_result.get("before_hash") == tampered_hash \
				and tampered_result.get("after_hash") == tampered_hash \
				and CanonicalJson.sha256(tampered.to_dictionary()) == tampered_hash,
		"tampered pending-choice rejection must remain atomic"
	)

	var resolve_envelope := _command_envelope(pending, {
		"type": "RESOLVE_CHOICE",
		"choice_id": choice_id,
		"card_instance_id": str(selected_card_id),
		"skip": false,
	}, "cmd-resolve-warrior-choice")
	var resolve_result := RulesEngine.dispatch(pending, resolve_envelope, definitions)
	var repeated_pending := repeated_attack["state"] as GameStateData
	var repeated_resolve := RulesEngine.dispatch(
		repeated_pending, resolve_envelope, definitions
	)
	_expect(bool(resolve_result.get("ok", false)), "warrior should remove a locked discard card")
	_expect(
		resolve_result.get("after_hash") == repeated_resolve.get("after_hash"),
		"identical warrior choices should produce the same committed hash"
	)
	if bool(resolve_result.get("ok", false)):
		var resolved := resolve_result["state"] as GameStateData
		_expect(
			ZoneService.find_card_zone(resolved, selected_card_id) == player.zone_ids[&"removed"],
			"warrior selection should move the discard card to the removed zone"
		)
		var resolved_events := resolve_result.get("events", []) as Array
		_expect(
			resolved_events.size() == 3 \
					and (resolved_events[0] as Dictionary).get("reason") == "card_removed" \
					and (resolved_events[1] as Dictionary).get("type") == "choice_resolved" \
					and (resolved_events[2] as Dictionary).get("type") == "effect_resolved",
			"warrior resolution events should order move, choice, then effect completion"
		)

	var skip_command: Dictionary = {}
	for command: Dictionary in choice_commands:
		if bool(command.get("skip", false)):
			skip_command = command
			break
	var discard_before_skip := discard.card_instance_ids.duplicate()
	var skip_result := RulesEngine.dispatch(
		pending,
		_command_envelope(pending, skip_command, "cmd-skip-warrior-choice"),
		definitions
	)
	_expect(bool(skip_result.get("ok", false)), "warrior discard removal should be optional")
	if bool(skip_result.get("ok", false)):
		var skipped := skip_result["state"] as GameStateData
		_expect(skipped.effect_state.is_empty(), "warrior skip should clear pending choice")
		_expect(
			(skipped.zones[player.zone_ids[&"discard_pile"]] as ZoneData).card_instance_ids \
				== discard_before_skip,
			"warrior skip should not alter the discard pile"
		)
		var skip_events := skip_result.get("events", []) as Array
		_expect(
			skip_events.size() == 2 \
					and (skip_events[0] as Dictionary).get("type") == "choice_resolved" \
					and bool((skip_events[0] as Dictionary).get("skipped", false)) \
					and (skip_events[1] as Dictionary).get("type") == "effect_resolved",
			"warrior skip events should order choice then effect completion"
		)


func _test_gargoyle_recruit_choice() -> void:
	var definitions := _load_definitions()
	var no_candidate := GameStateData.create_vertical_slice(251)
	var empty_row := no_candidate.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData
	for raw_card_id: Variant in empty_row.card_instance_ids.duplicate():
		var move_result := ZoneService.move_card(
			no_candidate,
			StringName(str(raw_card_id)),
			SupplyService.RECRUIT_ROW_ID,
			SupplyService.RECRUIT_DECK_ID
		)
		_expect(bool(move_result.get("ok", false)), "empty recruit fixture should move row cards")
	var no_candidate_events: Array[Dictionary] = []
	var no_candidate_error := EffectResolver.resolve(
		no_candidate,
		&"p1",
		[{
			"op": "choose_gain_card",
			"amount": 1,
			"source_zone_id": str(SupplyService.RECRUIT_ROW_ID),
			"allowed_card_types": ["adventurer"],
			"allowed_tags": ["adventurer"],
			"max_cost": 4,
		}],
		no_candidate_events,
		definitions
	)
	_expect(no_candidate_error.is_empty(), "empty recruit reward should resolve cleanly")
	_expect(no_candidate.effect_state.is_empty(), "empty recruit row must not create pending choice")
	_expect(
		no_candidate_events.size() == 1 \
				and no_candidate_events[0].get("reason") == "no_eligible_candidates",
		"empty recruit reward should emit a deterministic no-candidate resolution"
	)
	var filter_state := GameStateData.create_vertical_slice(252)
	var filter_row := filter_state.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData
	var expensive_id := filter_row.card_instance_ids[0]
	var expensive_card := filter_state.cards[expensive_id] as Dictionary
	var expensive_definition_id := StringName(expensive_card.get("definition_id", ""))
	var filtered_definitions := definitions.duplicate()
	var expensive_definition := (
		definitions[expensive_definition_id] as CardDefinition
	).duplicate(true) as CardDefinition
	expensive_definition.cost = 5
	filtered_definitions[expensive_definition_id] = expensive_definition
	var filter_events: Array[Dictionary] = []
	var filter_error := EffectResolver.resolve(
		filter_state,
		&"p1",
		[{
			"op": "choose_gain_card",
			"amount": 1,
			"source_zone_id": str(SupplyService.RECRUIT_ROW_ID),
			"allowed_card_types": ["adventurer"],
			"allowed_tags": ["adventurer"],
			"max_cost": 4,
		}],
		filter_events,
		filtered_definitions
	)
	_expect(filter_error.is_empty(), "gargoyle cost filter fixture should resolve")
	_expect(
		str(expensive_id) not in (filter_state.effect_state.get("eligible_card_ids", []) as Array),
		"gargoyle must exclude recruit definitions costing more than four"
	)

	var state := GameStateData.create_vertical_slice(253)
	var gargoyle_id := &"card-monster-gargoyle-01"
	var expose_error := _expose_monster(
		state, gargoyle_id, &"card-monster-rabbit-demon-01"
	)
	_expect(expose_error.is_empty(), "gargoyle fixture should expose the target: %s" % expose_error)
	if not expose_error.is_empty():
		return
	var phase_result := RulesEngine.dispatch(
		state,
		_end_phase_envelope(state, "cmd-gargoyle-combat-setup"),
		definitions
	)
	_expect(bool(phase_result.get("ok", false)), "gargoyle fixture should enter combat")
	if not bool(phase_result.get("ok", false)):
		return
	state = phase_result["state"] as GameStateData
	var preview := CombatService.preview_attack(state, &"p1", gargoyle_id, definitions)
	_expect(bool(preview.get("legal", false)), "gargoyle should be attackable by the full party")
	_expect(
		preview.get("reward_summary") \
				== "取得招募區 1 張費用不超過 4 的冒險者、取得此卡（購買力 2／榮譽 4）",
		"gargoyle preview should describe its exact recruit reward"
	)
	_expect(
		bool(preview.get("deferred_choice", false)) \
				and not bool(preview.get("optional_reward", true)),
		"gargoyle should defer a mandatory recruit choice"
	)
	var attack_envelope := _command_envelope(state, {
		"type": "ATTACK_TARGET",
		"target_card_id": str(gargoyle_id),
		"claim_optional_reward": true,
	}, "cmd-attack-gargoyle")
	var attack_result := RulesEngine.dispatch(state, attack_envelope, definitions)
	var repeated_attack := RulesEngine.dispatch(state.clone_state(), attack_envelope, definitions)
	_expect(bool(attack_result.get("ok", false)), "gargoyle attack should create a pending choice")
	_expect(
		attack_result.get("after_hash") == repeated_attack.get("after_hash"),
		"identical gargoyle attacks should produce the same pending-state hash"
	)
	if not bool(attack_result.get("ok", false)):
		return
	var pending := attack_result["state"] as GameStateData
	var player := pending.players[&"p1"] as PlayerStateData
	var recruit_row := pending.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData
	var eligible := pending.effect_state.get("eligible_card_ids", []) as Array
	_expect(
		StringName(pending.effect_state.get("op", "")) == &"choose_gain_card" \
				and StringName(pending.effect_state.get("source_zone_id", "")) \
				== SupplyService.RECRUIT_ROW_ID \
				and StringName(pending.effect_state.get("destination_zone_id", "")) \
				== player.zone_ids[&"discard_pile"],
		"gargoyle pending choice should lock recruit-row to own-discard movement"
	)
	_expect(
		eligible == _string_names_to_strings(recruit_row.card_instance_ids),
		"gargoyle should lock exactly the current legal recruit-row cards"
	)
	for raw_card_id: Variant in eligible:
		var card_id := StringName(str(raw_card_id))
		var card := pending.cards[card_id] as Dictionary
		var definition := definitions.get(
			StringName(card.get("definition_id", ""))
		) as CardDefinition
		_expect(
			definition != null and &"adventurer" in definition.tags \
					and int(definition.cost) <= 4,
			"gargoyle candidates must be adventurers costing at most four"
		)
	var choice_commands := RulesEngine.get_legal_commands(pending, &"p1", definitions)
	_expect(
		choice_commands.size() == eligible.size(),
		"gargoyle legal commands should contain one command per eligible recruit"
	)
	var has_skip := false
	for command: Dictionary in choice_commands:
		has_skip = has_skip or bool(command.get("skip", false))
	_expect(not has_skip, "mandatory gargoyle reward must not expose a skip command")

	var snapshot := SnapshotCodec.encode(pending, "content-gargoyle", "rules-gargoyle")
	var decoded := SnapshotCodec.decode(snapshot, "content-gargoyle", "rules-gargoyle")
	_expect(bool(decoded.get("ok", false)), "gargoyle pending choice should survive snapshot restore")
	if bool(decoded.get("ok", false)):
		_expect(
			CanonicalJson.stringify((decoded["state"] as GameStateData).effect_state) \
					== CanonicalJson.stringify(pending.effect_state),
			"gargoyle snapshot should preserve its locked candidates and filters"
		)

	var choice_id := str(pending.effect_state.get("choice_id", ""))
	var pending_hash := CanonicalJson.sha256(pending.to_dictionary())
	var wrong_source := RulesEngine.dispatch(
		pending,
		_command_envelope(pending, {
			"type": "RESOLVE_CHOICE",
			"choice_id": choice_id,
			"card_instance_id": "card-p1-summoning-stone-01",
			"skip": false,
		}, "cmd-gargoyle-wrong-source"),
		definitions
	)
	_expect(
		str(wrong_source.get("error", "")) == "ineligible_choice_card",
		"gargoyle choice must reject cards outside the locked recruit row"
	)
	_expect(
		CanonicalJson.sha256(pending.to_dictionary()) == pending_hash,
		"wrong-source gargoyle choice must remain atomic"
	)

	var selected_card_id := StringName(str(eligible[0]))
	var tampered := pending.clone_state()
	var tamper_move := ZoneService.move_card(
		tampered,
		selected_card_id,
		SupplyService.RECRUIT_ROW_ID,
		SupplyService.RECRUIT_DECK_ID
	)
	_expect(bool(tamper_move.get("ok", false)), "gargoyle tamper fixture should move a candidate")
	var tampered_hash := CanonicalJson.sha256(tampered.to_dictionary())
	var tampered_result := RulesEngine.dispatch(
		tampered,
		_command_envelope(tampered, {
			"type": "RESOLVE_CHOICE",
			"choice_id": choice_id,
			"card_instance_id": str(selected_card_id),
			"skip": false,
		}, "cmd-gargoyle-stale-candidate"),
		definitions
	)
	_expect(
		str(tampered_result.get("error", "")).begins_with("invalid_state:"),
		"dispatch should reject a recruit candidate moved after choice creation"
	)
	_expect(
		tampered_result.get("before_hash") == tampered_hash \
				and tampered_result.get("after_hash") == tampered_hash \
				and CanonicalJson.sha256(tampered.to_dictionary()) == tampered_hash,
		"stale gargoyle choice rejection must remain atomic"
	)

	var resolve_envelope := _command_envelope(pending, {
		"type": "RESOLVE_CHOICE",
		"choice_id": choice_id,
		"card_instance_id": str(selected_card_id),
		"skip": false,
	}, "cmd-resolve-gargoyle-choice")
	var resolve_result := RulesEngine.dispatch(pending, resolve_envelope, definitions)
	var repeated_pending := repeated_attack["state"] as GameStateData
	var repeated_resolve := RulesEngine.dispatch(
		repeated_pending, resolve_envelope, definitions
	)
	_expect(bool(resolve_result.get("ok", false)), "eligible recruit should resolve gargoyle reward")
	_expect(
		resolve_result.get("after_hash") == repeated_resolve.get("after_hash"),
		"identical gargoyle choices should produce the same committed hash"
	)
	if bool(resolve_result.get("ok", false)):
		var resolved := resolve_result["state"] as GameStateData
		_expect(resolved.effect_state.is_empty(), "gargoyle resolution should clear pending state")
		_expect(
			ZoneService.find_card_zone(resolved, selected_card_id) \
					== player.zone_ids[&"discard_pile"] \
					and StringName((resolved.cards[selected_card_id] as Dictionary).get("owner_id", "")) \
					== &"p1",
			"gargoyle reward should move the recruit to the winner discard and assign ownership"
		)
		_expect(
			(resolved.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData).card_instance_ids.size() == 2,
			"gargoyle reward should leave refill to the rest phase"
		)
		var resolved_events := resolve_result.get("events", []) as Array
		_expect(
			resolved_events.size() == 3 \
					and (resolved_events[0] as Dictionary).get("reason") == "reward_card_gained" \
					and (resolved_events[1] as Dictionary).get("type") == "choice_resolved" \
					and (resolved_events[2] as Dictionary).get("type") == "effect_resolved",
			"gargoyle events should order gain, choice, then effect completion"
		)
		_expect(InvariantService.validate(resolved).is_empty(), "gargoyle reward should preserve invariants")
		var after_reward := resolved
		for phase_index in 4:
			var phase_advance := RulesEngine.dispatch(
				after_reward,
				_end_phase_envelope(
					after_reward, "cmd-gargoyle-rest-refill-%d" % phase_index
				),
				definitions
			)
			_expect(bool(phase_advance.get("ok", false)), "gargoyle refill fixture should advance")
			if not bool(phase_advance.get("ok", false)):
				break
			after_reward = phase_advance["state"] as GameStateData
		_expect(
			(after_reward.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData) \
					.card_instance_ids.size() == SupplyService.ROW_SIZE,
			"rest phase should refill the recruit taken by gargoyle"
		)


func _test_public_row_gain_monsters() -> void:
	var base_definitions := _load_definitions()
	var monster_specs := [
		{
			"name": "arcane slime",
			"monster_id": &"card-monster-arcane-slime-01",
			"source_zone_id": SupplyService.RECRUIT_ROW_ID,
			"source_zone_key": &"recruit_row",
			"allowed_card_types": ["adventurer"],
			"allowed_tags": ["adventurer"],
			"max_cost": 3,
			"expected_eligible": [
				"card-supply-adventurer-09-01",
				"card-supply-adventurer-15-01",
			],
		},
		{
			"name": "goblin thief",
			"monster_id": &"card-monster-goblin-thief-01",
			"source_zone_id": SupplyService.SHOP_ROW_ID,
			"source_zone_key": &"shop_row",
			"allowed_card_types": ["item", "equipment"],
			"allowed_tags": ["item", "equipment"],
			"max_cost": 3,
			"expected_eligible": ["card-supply-resource-08-01"],
		},
		{
			"name": "ogre",
			"monster_id": &"card-monster-ogre-01",
			"source_zone_id": SupplyService.SHOP_ROW_ID,
			"source_zone_key": &"shop_row",
			"allowed_card_types": ["item", "equipment"],
			"allowed_tags": ["item", "equipment"],
			"max_cost": 4,
			"expected_eligible": [
				"card-supply-resource-08-01",
				"card-supply-resource-02-01",
			],
		},
	]
	for spec_index in monster_specs.size():
		var spec := monster_specs[spec_index] as Dictionary
		var fixture := _build_public_gain_fixture(
			270 + spec_index,
			StringName(spec["monster_id"]),
			StringName(spec["source_zone_id"]),
			base_definitions
		)
		var state := fixture["state"] as GameStateData
		var definitions := fixture["definitions"] as Dictionary
		var setup_error := str(fixture.get("error", ""))
		_expect(setup_error.is_empty(), "%s fixture should prepare: %s" % [spec.name, setup_error])
		if not setup_error.is_empty():
			continue
		var phase_result := RulesEngine.dispatch(
			state,
			_end_phase_envelope(state, "cmd-public-gain-phase-%d" % spec_index),
			definitions
		)
		_expect(bool(phase_result.get("ok", false)), "%s should enter combat" % spec.name)
		if not bool(phase_result.get("ok", false)):
			continue
		state = phase_result["state"] as GameStateData
		var preview := CombatService.preview_attack(
			state, &"p1", StringName(spec["monster_id"]), definitions
		)
		var expected_source_label := (
			"招募區" if StringName(spec["source_zone_key"]) == &"recruit_row" else "商店"
		)
		var expected_type_label := (
			"冒險者" if StringName(spec["source_zone_key"]) == &"recruit_row" else "道具或裝備"
		)
		_expect(
			bool(preview.get("legal", false)) \
					and bool(preview.get("deferred_choice", false)) \
					and not bool(preview.get("optional_reward", true)) \
					and "取得%s 1 張費用不超過 %d 的%s" % [
						expected_source_label, int(spec.max_cost), expected_type_label
					] in str(preview.get("reward_summary", "")),
			"%s preview should describe a mandatory filtered public-row gain" % spec.name
		)
		var attack_envelope := _command_envelope(state, {
			"type": "ATTACK_TARGET",
			"target_card_id": str(spec.monster_id),
			"claim_optional_reward": true,
		}, "cmd-public-gain-attack-%d" % spec_index)
		var attack_result := RulesEngine.dispatch(state, attack_envelope, definitions)
		var repeat_result := RulesEngine.dispatch(state.clone_state(), attack_envelope, definitions)
		_expect(bool(attack_result.get("ok", false)), "%s attack should create a choice" % spec.name)
		_expect(
			attack_result.get("after_hash") == repeat_result.get("after_hash"),
			"%s pending choice hash should be deterministic" % spec.name
		)
		if not bool(attack_result.get("ok", false)):
			continue
		var pending := attack_result["state"] as GameStateData
		var attack_events := attack_result.get("events", []) as Array
		var choice_requested_index := -1
		var monster_claimed_index := -1
		var defeated_index := -1
		for event_index in attack_events.size():
			var attack_event := attack_events[event_index] as Dictionary
			if attack_event.get("type") == "choice_requested":
				choice_requested_index = event_index
			elif attack_event.get("reason") == "defeated_monster_claimed":
				monster_claimed_index = event_index
			elif attack_event.get("type") == "enemy_defeated":
				defeated_index = event_index
		_expect(
			choice_requested_index >= 0 \
					and choice_requested_index < monster_claimed_index \
					and monster_claimed_index < defeated_index,
			"%s attack events should request choice before claim and defeat completion" % spec.name
		)
		var player := pending.players[&"p1"] as PlayerStateData
		var eligible := pending.effect_state.get("eligible_card_ids", []) as Array
		_expect(
			eligible == spec.expected_eligible \
					and StringName(pending.effect_state.get("source_zone_id", "")) \
					== StringName(spec.source_zone_id) \
					and StringName(pending.effect_state.get("source_zone_key", "")) \
					== StringName(spec.source_zone_key) \
					and int(pending.effect_state.get("max_cost", -1)) == int(spec.max_cost) \
					and pending.effect_state.get("allowed_card_types", []) == spec.allowed_card_types \
					and pending.effect_state.get("allowed_tags", []) == spec.allowed_tags,
			"%s should lock only creation-time candidates and complete filters" % spec.name
		)
		var legal_commands := RulesEngine.get_legal_commands(pending, &"p1", definitions)
		_expect(
			legal_commands.size() == eligible.size(),
			"%s should expose one legal command per locked candidate" % spec.name
		)
		for command: Dictionary in legal_commands:
			_expect(not bool(command.get("skip", false)), "%s gain must not be skippable" % spec.name)
		var skip_result := RulesEngine.dispatch(
			pending,
			_command_envelope(pending, {
				"type": "RESOLVE_CHOICE",
				"choice_id": str(pending.effect_state.get("choice_id", "")),
				"card_instance_id": "",
				"skip": true,
			}, "cmd-public-gain-skip-%d" % spec_index),
			definitions
		)
		_expect(str(skip_result.get("error", "")) == "choice_required", "%s must reject skip" % spec.name)
		var snapshot := SnapshotCodec.encode(pending, "content-public-gain", "rules-public-gain")
		var decoded := SnapshotCodec.decode(snapshot, "content-public-gain", "rules-public-gain")
		_expect(
			bool(decoded.get("ok", false)) \
					and CanonicalJson.stringify((decoded["state"] as GameStateData).effect_state) \
					== CanonicalJson.stringify(pending.effect_state),
			"%s pending choice should round-trip through snapshot" % spec.name
		)
		var selected_id := StringName(str(eligible[0]))
		var resolve_envelope := _command_envelope(pending, {
			"type": "RESOLVE_CHOICE",
			"choice_id": str(pending.effect_state.get("choice_id", "")),
			"card_instance_id": str(selected_id),
			"skip": false,
		}, "cmd-public-gain-resolve-%d" % spec_index)
		var resolved_result := RulesEngine.dispatch(pending, resolve_envelope, definitions)
		var repeat_pending := repeat_result["state"] as GameStateData
		var repeat_resolved := RulesEngine.dispatch(repeat_pending, resolve_envelope, definitions)
		_expect(bool(resolved_result.get("ok", false)), "%s choice should resolve" % spec.name)
		_expect(
			resolved_result.get("after_hash") == repeat_resolved.get("after_hash"),
			"%s resolved choice hash should be deterministic" % spec.name
		)
		if not bool(resolved_result.get("ok", false)):
			continue
		var resolved := resolved_result["state"] as GameStateData
		_expect(
			ZoneService.find_card_zone(resolved, selected_id) == player.zone_ids[&"discard_pile"] \
					and StringName((resolved.cards[selected_id] as Dictionary).get("owner_id", "")) == &"p1" \
					and (resolved.zones[StringName(spec.source_zone_id)] as ZoneData) \
					.card_instance_ids.size() == 2,
			"%s should assign ownership, use own discard, and leave a public gap" % spec.name
		)
		var events := resolved_result.get("events", []) as Array
		_expect(
			events.size() == 3 \
					and (events[0] as Dictionary).get("reason") == "reward_card_gained" \
					and (events[1] as Dictionary).get("type") == "choice_resolved" \
					and (events[2] as Dictionary).get("type") == "effect_resolved",
			"%s events should order gain, choice, then effect completion" % spec.name
		)

	# Shop candidates are locked and revalidated against source, owner, cost, and type.
	var atomic_fixture := _build_public_gain_fixture(
		281, &"card-monster-goblin-thief-01", SupplyService.SHOP_ROW_ID, base_definitions
	)
	var atomic_state := atomic_fixture["state"] as GameStateData
	var atomic_definitions := atomic_fixture["definitions"] as Dictionary
	var atomic_events: Array[Dictionary] = []
	var atomic_error := EffectResolver.resolve(
		atomic_state,
		&"p1",
		[(base_definitions[&"base:monster/monster-07"] as CardDefinition).effects[0]],
		atomic_events,
		atomic_definitions
	)
	_expect(atomic_error.is_empty(), "shop atomic fixture should create a pending choice")
	var atomic_id := StringName(
		str((atomic_state.effect_state.get("eligible_card_ids", []) as Array)[0])
	)
	var atomic_choice_id := str(atomic_state.effect_state.get("choice_id", ""))
	var wrong_zone_result := RulesEngine.dispatch(
		atomic_state,
		_command_envelope(atomic_state, {
			"type": "RESOLVE_CHOICE",
			"choice_id": atomic_choice_id,
			"card_instance_id": "card-supply-adventurer-09-01",
			"skip": false,
		}, "cmd-shop-wrong-public-row"),
		atomic_definitions
	)
	_expect(
		str(wrong_zone_result.get("error", "")) == "ineligible_choice_card",
		"shop gain must reject recruit row, hand, party, monster row, decks, and other unlocked cards"
	)
	var moved_state := atomic_state.clone_state()
	var moved := ZoneService.move_card(
		moved_state, atomic_id, SupplyService.SHOP_ROW_ID, SupplyService.SHOP_DECK_ID
	)
	_expect(bool(moved.get("ok", false)), "shop tamper fixture should move the candidate")
	var moved_hash := CanonicalJson.sha256(moved_state.to_dictionary())
	var moved_result := RulesEngine.dispatch(
		moved_state,
		_command_envelope(moved_state, {
			"type": "RESOLVE_CHOICE",
			"choice_id": atomic_choice_id,
			"card_instance_id": str(atomic_id),
			"skip": false,
		}, "cmd-shop-moved-candidate"),
		atomic_definitions
	)
	_expect(
		str(moved_result.get("error", "")).begins_with("invalid_state:") \
				and moved_result.get("before_hash") == moved_hash \
				and moved_result.get("after_hash") == moved_hash,
		"moved shop candidate must fail atomically"
	)
	var owned_state := atomic_state.clone_state()
	(owned_state.cards[atomic_id] as Dictionary)["owner_id"] = "p1"
	var owned_hash := CanonicalJson.sha256(owned_state.to_dictionary())
	var owned_result := RulesEngine.dispatch(
		owned_state,
		_command_envelope(owned_state, {
			"type": "RESOLVE_CHOICE",
			"choice_id": atomic_choice_id,
			"card_instance_id": str(atomic_id),
			"skip": false,
		}, "cmd-shop-owned-candidate"),
		atomic_definitions
	)
	_expect(
		str(owned_result.get("error", "")).begins_with("invalid_state:") \
				and owned_result.get("after_hash") == owned_hash,
		"already-owned public candidate must fail atomically"
	)
	var filter_hash := CanonicalJson.sha256(atomic_state.to_dictionary())
	var selected_definition_id := StringName(
		(atomic_state.cards[atomic_id] as Dictionary).get("definition_id", "")
	)
	var expensive_definitions := atomic_definitions.duplicate()
	var expensive_selected := (
		atomic_definitions[selected_definition_id] as CardDefinition
	).duplicate(true) as CardDefinition
	expensive_selected.cost = 4
	expensive_definitions[selected_definition_id] = expensive_selected
	var expensive_result := RulesEngine.dispatch(
		atomic_state,
		_command_envelope(atomic_state, {
			"type": "RESOLVE_CHOICE",
			"choice_id": atomic_choice_id,
			"card_instance_id": str(atomic_id),
			"skip": false,
		}, "cmd-shop-cost-tamper"),
		expensive_definitions
	)
	_expect(
		str(expensive_result.get("error", "")) == "choice_card_cost_exceeded" \
				and expensive_result.get("after_hash") == filter_hash,
		"dispatch must revalidate max cost and remain atomic"
	)
	var wrong_type_definitions := atomic_definitions.duplicate()
	var wrong_type_selected := (
		atomic_definitions[selected_definition_id] as CardDefinition
	).duplicate(true) as CardDefinition
	wrong_type_selected.card_type = &"adventurer"
	wrong_type_definitions[selected_definition_id] = wrong_type_selected
	var wrong_type_result := RulesEngine.dispatch(
		atomic_state,
		_command_envelope(atomic_state, {
			"type": "RESOLVE_CHOICE",
			"choice_id": atomic_choice_id,
			"card_instance_id": str(atomic_id),
			"skip": false,
		}, "cmd-shop-type-tamper"),
		wrong_type_definitions
	)
	_expect(
		str(wrong_type_result.get("error", "")) == "choice_card_wrong_type" \
				and wrong_type_result.get("after_hash") == filter_hash,
		"dispatch must revalidate card type and remain atomic"
	)
	var wrong_tag_definitions := atomic_definitions.duplicate()
	var wrong_tag_selected := (
		atomic_definitions[selected_definition_id] as CardDefinition
	).duplicate(true) as CardDefinition
	wrong_tag_selected.tags.assign([&"adventurer"])
	wrong_tag_definitions[selected_definition_id] = wrong_tag_selected
	var wrong_tag_result := RulesEngine.dispatch(
		atomic_state,
		_command_envelope(atomic_state, {
			"type": "RESOLVE_CHOICE",
			"choice_id": atomic_choice_id,
			"card_instance_id": str(atomic_id),
			"skip": false,
		}, "cmd-shop-tag-tamper"),
		wrong_tag_definitions
	)
	_expect(
		str(wrong_tag_result.get("error", "")) == "choice_card_wrong_type" \
				and wrong_tag_result.get("after_hash") == filter_hash,
		"dispatch must revalidate required tags and remain atomic"
	)

	# No legal public candidate completes immediately without a pending choice.
	var no_candidate := GameStateData.create_vertical_slice(282)
	var no_candidate_definitions := base_definitions.duplicate()
	for definition_id: StringName in [
		&"base:resource/resource-02",
		&"base:resource/resource-03",
		&"base:resource/resource-08",
	]:
		var expensive := (base_definitions[definition_id] as CardDefinition).duplicate(true) as CardDefinition
		expensive.cost = 5
		no_candidate_definitions[definition_id] = expensive
	var no_candidate_events: Array[Dictionary] = []
	var no_candidate_error := EffectResolver.resolve(
		no_candidate,
		&"p1",
		[(base_definitions[&"base:monster/monster-07"] as CardDefinition).effects[0]],
		no_candidate_events,
		no_candidate_definitions
	)
	_expect(
		no_candidate_error.is_empty() and no_candidate.effect_state.is_empty() \
				and no_candidate_events.size() == 1 \
				and no_candidate_events[0].get("reason") == "no_eligible_candidates",
		"gain effect with no legal candidate should complete without pending state"
	)

	# Refill happens only when leaving rest, never at choice resolution.
	var rest_fixture := _build_public_gain_fixture(
		283, &"card-monster-goblin-thief-01", SupplyService.SHOP_ROW_ID, base_definitions
	)
	var rest_state := rest_fixture["state"] as GameStateData
	var rest_definitions := rest_fixture["definitions"] as Dictionary
	var rest_events: Array[Dictionary] = []
	EffectResolver.resolve(
		rest_state,
		&"p1",
		[(base_definitions[&"base:monster/monster-07"] as CardDefinition).effects[0]],
		rest_events,
		rest_definitions
	)
	var rest_selected := str((rest_state.effect_state.get("eligible_card_ids", []) as Array)[0])
	var rest_resolve := RulesEngine.dispatch(
		rest_state,
		_command_envelope(rest_state, {
			"type": "RESOLVE_CHOICE",
			"choice_id": str(rest_state.effect_state.get("choice_id", "")),
			"card_instance_id": rest_selected,
			"skip": false,
		}, "cmd-shop-rest-resolve"),
		rest_definitions
	)
	rest_state = rest_resolve["state"] as GameStateData
	_expect(
		(rest_state.zones[SupplyService.SHOP_ROW_ID] as ZoneData).card_instance_ids.size() == 2,
		"public gain must not refill immediately"
	)
	for phase_index in 5:
		var rest_advance := RulesEngine.dispatch(
			rest_state,
			_end_phase_envelope(rest_state, "cmd-shop-rest-%d" % phase_index),
			rest_definitions
		)
		_expect(bool(rest_advance.get("ok", false)), "shop refill fixture should advance")
		if not bool(rest_advance.get("ok", false)):
			break
		rest_state = rest_advance["state"] as GameStateData
	_expect(
		(rest_state.zones[SupplyService.SHOP_ROW_ID] as ZoneData).card_instance_ids.size() == 3,
		"leaving rest should refill the shop gap"
	)


func _build_public_gain_fixture(
	seed: int,
	monster_id: StringName,
	source_zone_id: StringName,
	base_definitions: Dictionary
) -> Dictionary:
	var state := GameStateData.create_vertical_slice(seed)
	var expose_error := _expose_monster(
		state, monster_id, &"card-monster-rabbit-demon-01"
	)
	if not expose_error.is_empty():
		return {"state": state, "definitions": base_definitions, "error": expose_error}
	var definitions := base_definitions.duplicate()
	var row_ids: Array[StringName] = []
	var deck_zone_id: StringName
	if source_zone_id == SupplyService.RECRUIT_ROW_ID:
		deck_zone_id = SupplyService.RECRUIT_DECK_ID
		row_ids.assign([
			&"card-supply-adventurer-09-01",
			&"card-supply-adventurer-10-01",
			&"card-supply-adventurer-15-01",
		])
	else:
		deck_zone_id = SupplyService.SHOP_DECK_ID
		row_ids.assign([
			&"card-supply-resource-08-01",
			&"card-supply-resource-02-01",
			&"card-supply-resource-03-01",
		])
		for cost_spec: Array in [
			[&"base:resource/resource-08", 3],
			[&"base:resource/resource-02", 4],
			[&"base:resource/resource-03", 5],
		]:
			var definition := (
				base_definitions[StringName(cost_spec[0])] as CardDefinition
			).duplicate(true) as CardDefinition
			definition.cost = int(cost_spec[1])
			definitions[StringName(cost_spec[0])] = definition
	var row := state.zones[source_zone_id] as ZoneData
	for current_id: StringName in row.card_instance_ids.duplicate():
		var move_out := ZoneService.move_card(state, current_id, source_zone_id, deck_zone_id)
		if not bool(move_out.get("ok", false)):
			return {"state": state, "definitions": definitions, "error": "fixture_row_clear"}
	for card_id: StringName in row_ids:
		var current_zone_id := ZoneService.find_card_zone(state, card_id)
		var move_in := ZoneService.move_card(state, card_id, current_zone_id, source_zone_id)
		if not bool(move_in.get("ok", false)):
			return {"state": state, "definitions": definitions, "error": "fixture_row_fill"}
	return {"state": state, "definitions": definitions, "error": ""}


func _test_fire_elemental_hand_redraw() -> void:
	var definitions := _load_definitions()
	var fire_id := &"card-monster-fire-elemental-01"
	var state := GameStateData.create_vertical_slice(259)
	var expose_error := _expose_monster(
		state, fire_id, &"card-monster-rabbit-demon-01"
	)
	_expect(expose_error.is_empty(), "fire elemental fixture should expose the target")
	if not expose_error.is_empty():
		return
	var phase_result := RulesEngine.dispatch(
		state,
		_end_phase_envelope(state, "cmd-fire-elemental-combat-setup"),
		definitions
	)
	_expect(bool(phase_result.get("ok", false)), "fire elemental fixture should enter combat")
	if not bool(phase_result.get("ok", false)):
		return
	state = phase_result["state"] as GameStateData
	var player := state.players[&"p1"] as PlayerStateData
	var hand := state.zones[player.zone_ids[&"hand"]] as ZoneData
	var original_hand := hand.card_instance_ids.duplicate()
	var original_rng_state := state.rng_state
	var preview := CombatService.preview_attack(state, &"p1", fire_id, definitions)
	_expect(bool(preview.get("legal", false)), "fire elemental should be attackable")
	_expect(
		preview.get("reward_summary") \
				== "可棄掉全部手牌，再抽相同張數、取得此卡（購買力 1／榮譽 3）",
		"fire elemental preview should show the complete optional redraw reward"
	)
	_expect(
		bool(preview.get("optional_reward", false)) \
				and not bool(preview.get("deferred_choice", true)),
		"fire elemental should use the immediate ATTACK_TARGET optional reward flow"
	)
	var fire_commands: Array[Dictionary] = []
	for command: Dictionary in RulesEngine.get_legal_commands(state, &"p1", definitions):
		if StringName(command.get("target_card_id", "")) == fire_id:
			fire_commands.append(command)
	_expect(fire_commands.size() == 2, "fire elemental should expose execute and skip attacks")
	var has_execute := false
	var has_skip := false
	for command: Dictionary in fire_commands:
		has_execute = has_execute or bool(command.get("claim_optional_reward", false))
		has_skip = has_skip or not bool(command.get("claim_optional_reward", true))
	_expect(has_execute and has_skip, "fire elemental legal commands should include both reward choices")

	var attack_envelope := _command_envelope(state, {
		"type": "ATTACK_TARGET",
		"target_card_id": str(fire_id),
		"claim_optional_reward": true,
	}, "cmd-attack-fire-elemental")
	var attack_result := RulesEngine.dispatch(state, attack_envelope, definitions)
	var repeated_attack := RulesEngine.dispatch(state.clone_state(), attack_envelope, definitions)
	_expect(bool(attack_result.get("ok", false)), "fire elemental redraw attack should commit")
	_expect(
		attack_result.get("after_hash") == repeated_attack.get("after_hash"),
		"identical fire elemental redraws should produce the same committed hash"
	)
	if not bool(attack_result.get("ok", false)):
		return
	var redrawn := attack_result["state"] as GameStateData
	player = redrawn.players[&"p1"] as PlayerStateData
	_expect(redrawn.effect_state.is_empty(), "fire elemental must not create pending state")
	_expect(
		(redrawn.zones[player.zone_ids[&"hand"]] as ZoneData).card_instance_ids.size() \
				== original_hand.size(),
		"fire elemental should redraw exactly the locked hand count"
	)
	var events := attack_result.get("events", []) as Array
	var start_index := -1
	var first_discard_index := -1
	var last_discard_index := -1
	var reshuffle_index := -1
	var first_draw_index := -1
	var last_draw_index := -1
	var effect_index := -1
	var claim_index := -1
	var locked_ids: Array = []
	var redraw_discard_count := 0
	var redraw_draw_count := 0
	for index in events.size():
		var event := events[index] as Dictionary
		if event.get("type") == "hand_redraw_started":
			start_index = index
			locked_ids = event.get("locked_card_ids", []) as Array
		elif event.get("reason") == "hand_redraw_discard":
			if first_discard_index < 0:
				first_discard_index = index
			last_discard_index = index
			redraw_discard_count += 1
		elif event.get("type") == "discard_reshuffled":
			reshuffle_index = index
		elif event.get("reason") == "draw":
			if first_draw_index < 0:
				first_draw_index = index
			last_draw_index = index
			redraw_draw_count += 1
		elif event.get("type") == "effect_resolved" \
				and event.get("op") == "discard_hand_and_draw":
			effect_index = index
		elif event.get("reason") == "defeated_monster_claimed":
			claim_index = index
	_expect(
		locked_ids == _string_names_to_strings(original_hand),
		"fire elemental should lock the complete current hand before moving cards"
	)
	_expect(
		redraw_discard_count == original_hand.size() \
				and redraw_draw_count == original_hand.size(),
		"fire elemental must discard and draw the full locked count"
	)
	_expect(
		start_index >= 0 and start_index < first_discard_index \
				and last_discard_index < reshuffle_index \
				and reshuffle_index < first_draw_index \
				and last_draw_index < effect_index and effect_index < claim_index,
		"fire elemental events should order lock, all discards, reshuffle, draws, effect, and claim"
	)
	_expect(redrawn.rng_state != original_rng_state, "fire elemental reshuffle should advance seeded RNG")
	_expect(InvariantService.validate(redrawn).is_empty(), "fire elemental redraw should preserve invariants")
	var snapshot := SnapshotCodec.encode(redrawn, "content-fire", "rules-fire")
	var decoded := SnapshotCodec.decode(snapshot, "content-fire", "rules-fire")
	_expect(bool(decoded.get("ok", false)), "fire elemental result should survive snapshot restore")
	if bool(decoded.get("ok", false)):
		_expect(
			CanonicalJson.sha256((decoded["state"] as GameStateData).to_dictionary()) \
					== CanonicalJson.sha256(redrawn.to_dictionary()),
			"fire elemental snapshot should preserve its deterministic state hash"
		)

	var skip_result := RulesEngine.dispatch(
		state,
		_command_envelope(state, {
			"type": "ATTACK_TARGET",
			"target_card_id": str(fire_id),
			"claim_optional_reward": false,
		}, "cmd-skip-fire-elemental-reward"),
		definitions
	)
	_expect(bool(skip_result.get("ok", false)), "fire elemental redraw should be skippable")
	if bool(skip_result.get("ok", false)):
		var skipped := skip_result["state"] as GameStateData
		_expect(
			(skipped.zones[&"p1:hand"] as ZoneData).card_instance_ids == original_hand,
			"skipping fire elemental should preserve the complete hand"
		)
		_expect(skipped.rng_state == original_rng_state, "skipping redraw must not consume RNG")
		_expect(
			not _events_contain(skip_result.get("events", []) as Array, "hand_redraw_started"),
			"skipping fire elemental should not begin the redraw operation"
		)

	var empty_hand_state := GameStateData.create_vertical_slice(261)
	_expose_monster(empty_hand_state, fire_id, &"card-monster-rabbit-demon-01")
	var empty_player := empty_hand_state.players[&"p1"] as PlayerStateData
	var empty_hand := empty_hand_state.zones[empty_player.zone_ids[&"hand"]] as ZoneData
	for card_id: StringName in empty_hand.card_instance_ids.duplicate():
		var move_result := ZoneService.move_card(
			empty_hand_state,
			card_id,
			empty_player.zone_ids[&"hand"],
			empty_player.zone_ids[&"draw_pile"]
		)
		_expect(bool(move_result.get("ok", false)), "empty-hand fixture should move each hand card")
	phase_result = RulesEngine.dispatch(
		empty_hand_state,
		_end_phase_envelope(empty_hand_state, "cmd-fire-empty-combat-setup"),
		definitions
	)
	if not bool(phase_result.get("ok", false)):
		_expect(false, "empty-hand fire fixture should enter combat")
		return
	empty_hand_state = phase_result["state"] as GameStateData
	var empty_result := RulesEngine.dispatch(
		empty_hand_state,
		_command_envelope(empty_hand_state, {
			"type": "ATTACK_TARGET",
			"target_card_id": str(fire_id),
			"claim_optional_reward": true,
		}, "cmd-fire-empty-redraw"),
		definitions
	)
	_expect(bool(empty_result.get("ok", false)), "zero-card fire redraw should complete stably")
	if bool(empty_result.get("ok", false)):
		var empty_redrawn := empty_result["state"] as GameStateData
		_expect(empty_redrawn.effect_state.is_empty(), "zero-card redraw must not create pending state")
		_expect(
			(empty_redrawn.zones[&"p1:hand"] as ZoneData).card_instance_ids.is_empty(),
			"zero-card redraw should keep the hand empty"
		)
		var empty_events := empty_result.get("events", []) as Array
		var empty_started := false
		var empty_resolved := false
		for event: Dictionary in empty_events:
			if event.get("type") == "hand_redraw_started":
				empty_started = int(event.get("locked_count", -1)) == 0
			elif event.get("type") == "effect_resolved" \
					and event.get("op") == "discard_hand_and_draw":
				empty_resolved = int(event.get("discarded_count", -1)) == 0 \
						and int(event.get("drawn_count", -1)) == 0
		_expect(empty_started and empty_resolved, "zero-card redraw should emit stable zero counts")
		_expect(
			not _events_contain(empty_events, "discard_reshuffled"),
			"zero-card redraw should not trigger an unnecessary reshuffle"
		)

	var boundary := GameStateData.create_vertical_slice(263)
	var boundary_player := boundary.players[&"p1"] as PlayerStateData
	var boundary_hand := boundary.zones[boundary_player.zone_ids[&"hand"]] as ZoneData
	for index in 2:
		var boundary_card_id := boundary_hand.card_instance_ids[0]
		ZoneService.move_card(
			boundary,
			boundary_card_id,
			boundary_player.zone_ids[&"hand"],
			boundary_player.zone_ids[&"draw_pile"]
		)
	var repeated_boundary := boundary.clone_state()
	var boundary_effects: Array[Dictionary] = [{"op": "discard_hand_and_draw"}]
	var boundary_events: Array[Dictionary] = []
	var repeated_boundary_events: Array[Dictionary] = []
	var boundary_error := EffectResolver.resolve(
		boundary, &"p1", boundary_effects, boundary_events, definitions
	)
	var repeated_boundary_error := EffectResolver.resolve(
		repeated_boundary, &"p1", boundary_effects, repeated_boundary_events, definitions
	)
	_expect(
		boundary_error.is_empty() and repeated_boundary_error.is_empty(),
		"fire redraw should cross a partially depleted draw-pile boundary"
	)
	_expect(
		CanonicalJson.sha256(boundary.to_dictionary()) \
				== CanonicalJson.sha256(repeated_boundary.to_dictionary()),
		"partial draw-pile redraw should use deterministic reshuffle order"
	)
	var boundary_reshuffles := 0
	for event: Dictionary in boundary_events:
		if event.get("type") == "discard_reshuffled":
			boundary_reshuffles += 1
	_expect(boundary_reshuffles == 1, "partial draw pile should reshuffle exactly once when exhausted")
	_expect(
		(boundary.zones[boundary_player.zone_ids[&"hand"]] as ZoneData).card_instance_ids.size() == 3,
		"partial-boundary redraw should restore the locked three-card hand"
	)

	var failing_state := GameStateData.create_vertical_slice(265)
	_expose_monster(failing_state, fire_id, &"card-monster-rabbit-demon-01")
	phase_result = RulesEngine.dispatch(
		failing_state,
		_end_phase_envelope(failing_state, "cmd-fire-failure-combat-setup"),
		definitions
	)
	if not bool(phase_result.get("ok", false)):
		_expect(false, "fire failure fixture should enter combat")
		return
	failing_state = phase_result["state"] as GameStateData
	var invalid_definitions := definitions.duplicate()
	var invalid_fire := (
		definitions[&"base:monster/monster-13"] as CardDefinition
	).duplicate(true) as CardDefinition
	invalid_fire.effects = [{
		"op": "unsupported_fire_reward",
		"timing": "on_defeat",
		"optional": true,
	}]
	invalid_definitions[&"base:monster/monster-13"] = invalid_fire
	var failing_hash := CanonicalJson.sha256(failing_state.to_dictionary())
	var failure_result := RulesEngine.dispatch(
		failing_state,
		_command_envelope(failing_state, {
			"type": "ATTACK_TARGET",
			"target_card_id": str(fire_id),
			"claim_optional_reward": true,
		}, "cmd-fire-invalid-effect"),
		invalid_definitions
	)
	_expect(
		str(failure_result.get("error", "")).begins_with("invalid_effect:"),
		"invalid fire operation should reject dispatch after draft combat work"
	)
	_expect(
		failure_result.get("before_hash") == failing_hash \
				and failure_result.get("after_hash") == failing_hash \
				and CanonicalJson.sha256(failing_state.to_dictionary()) == failing_hash,
		"failed fire elemental dispatch must remain atomic"
	)


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


func _test_pending_choice_hud_integration() -> void:
	var packed := load("res://scenes/boot/main.tscn") as PackedScene
	var app := packed.instantiate() as GameApp
	root.add_child(app)
	await process_frame
	var expose_error := _expose_monster(
		app.session.state,
		&"card-monster-automaton-archer-01",
		&"card-monster-rabbit-demon-01"
	)
	_expect(expose_error.is_empty(), "choice HUD fixture should expose the archer")
	var phase_result := app.session.end_phase()
	_expect(bool(phase_result.get("ok", false)), "choice HUD fixture should enter combat")
	var attack_result := app.session.attack_target(&"card-monster-automaton-archer-01", true)
	_expect(bool(attack_result.get("ok", false)), "choice HUD fixture should attack the archer")
	await process_frame
	var remove_buttons: Array[Button] = []
	var skip_choice_buttons := 0
	var skip_choice_button: Button
	for child: Node in app.hud.hand_actions.get_children():
		if child is Button and (child as Button).text == "從自己的手牌移除此牌":
			remove_buttons.append(child as Button)
		elif child is Button and (child as Button).text == "略過移除":
			skip_choice_buttons += 1
			skip_choice_button = child as Button
	_expect(remove_buttons.size() == 5, "choice HUD should expose one removal button per hand card")
	_expect(skip_choice_buttons == 1, "choice HUD should expose the optional skip action")
	_expect(app.hud.end_phase_button.disabled, "choice HUD should disable phase advancement")
	_expect(
		app.hud.hand_summary.text.begins_with("待選擇："),
		"choice HUD should replace the hand summary with an explicit prompt"
	)
	if not remove_buttons.is_empty() and skip_choice_button != null:
		_expect(
			remove_buttons[0].focus_neighbor_top == skip_choice_button.get_path(),
			"pending choice focus should wrap within the choice controls"
		)
		_expect(
			skip_choice_button.focus_neighbor_bottom == remove_buttons[0].get_path(),
			"pending choice focus should not escape to disabled phase controls"
		)
	if not remove_buttons.is_empty():
		remove_buttons[0].pressed.emit()
		await process_frame
		_expect(app.session.state.effect_state.is_empty(), "choice button should resolve through GameApp")
		_expect(
			(app.session.state.zones[&"p1:removed"] as ZoneData).card_instance_ids.size() == 1,
			"choice button should move exactly one card into the removed zone"
		)
		_expect(not app.hud.end_phase_button.disabled, "phase control should re-enable after choice")
	app.queue_free()


func _test_discard_choice_hud_integration() -> void:
	var packed := load("res://scenes/boot/main.tscn") as PackedScene
	var app := packed.instantiate() as GameApp
	root.add_child(app)
	await process_frame
	var expose_error := _expose_monster(
		app.session.state,
		&"card-monster-automaton-warrior-01",
		&"card-monster-rabbit-demon-01"
	)
	_expect(expose_error.is_empty(), "discard-choice HUD fixture should expose the warrior")
	var phase_result := app.session.end_phase()
	_expect(bool(phase_result.get("ok", false)), "discard-choice HUD should enter combat")
	var attack_result := app.session.attack_target(&"card-monster-automaton-warrior-01", true)
	_expect(bool(attack_result.get("ok", false)), "discard-choice HUD should attack the warrior")
	await process_frame
	var remove_buttons: Array[Button] = []
	var skip_choice_button: Button
	for child: Node in app.hud.hand_actions.get_children():
		if child is Button and (child as Button).text == "從自己的棄牌堆移除此牌":
			remove_buttons.append(child as Button)
		elif child is Button and (child as Button).text == "略過移除":
			skip_choice_button = child as Button
	_expect(remove_buttons.size() == 3, "discard-choice HUD should show three departed candidates")
	_expect(skip_choice_button != null, "discard-choice HUD should retain the optional skip")
	_expect(app.hud.hand_title.text == "待處理選擇", "discard choice should replace the panel title")
	_expect(
		"可以從自己的棄牌堆移除 1 張牌" in app.hud.hand_summary.text \
				and "來源：自己的棄牌堆（3 張）" in app.hud.hand_summary.text,
		"discard-choice HUD should show the complete prompt and source zone"
	)
	if not remove_buttons.is_empty() and skip_choice_button != null:
		_expect(
			remove_buttons[0].focus_neighbor_top == skip_choice_button.get_path() \
				and skip_choice_button.focus_neighbor_bottom == remove_buttons[0].get_path(),
			"discard choice should reuse the trapped keyboard focus loop"
		)
		remove_buttons[0].pressed.emit()
		await process_frame
		_expect(app.session.state.effect_state.is_empty(), "discard choice HUD should submit selection")
		_expect(
			(app.session.state.zones[&"p1:removed"] as ZoneData).card_instance_ids.size() == 1,
			"discard choice HUD should remove exactly one selected card"
		)
	app.queue_free()


func _test_gargoyle_choice_hud_integration() -> void:
	var packed := load("res://scenes/boot/main.tscn") as PackedScene
	var app := packed.instantiate() as GameApp
	root.add_child(app)
	await process_frame
	var expose_error := _expose_monster(
		app.session.state,
		&"card-monster-gargoyle-01",
		&"card-monster-rabbit-demon-01"
	)
	_expect(expose_error.is_empty(), "gargoyle HUD fixture should expose the target")
	var phase_result := app.session.end_phase()
	_expect(bool(phase_result.get("ok", false)), "gargoyle HUD should enter combat")
	var attack_result := app.session.attack_target(&"card-monster-gargoyle-01", true)
	_expect(bool(attack_result.get("ok", false)), "gargoyle HUD should create recruit choice")
	await process_frame
	var gain_buttons: Array[Button] = []
	var cost_labels := 0
	var skip_buttons := 0
	for child: Node in app.hud.hand_actions.get_children():
		if child is Button and (child as Button).text == "從招募區取得此牌":
			gain_buttons.append(child as Button)
		elif child is Label and "｜費用 " in (child as Label).text:
			cost_labels += 1
		elif child is Button and (child as Button).text.begins_with("略過"):
			skip_buttons += 1
	_expect(gain_buttons.size() == 3, "gargoyle HUD should show each eligible recruit")
	_expect(cost_labels == 3, "recruit choice HUD should show each card name and cost")
	_expect(skip_buttons == 0, "mandatory gargoyle HUD must not show a skip action")
	_expect(app.hud.hand_title.text == "待處理選擇", "gargoyle choice should use pending title")
	_expect(
		"從招募區取得 1 張費用不超過 4 的冒險者" in app.hud.hand_summary.text \
				and "來源：招募區（3 張）" in app.hud.hand_summary.text,
		"gargoyle HUD should show the complete prompt and public source"
	)
	if gain_buttons.size() == 3:
		_expect(
			gain_buttons[0].focus_neighbor_top == gain_buttons[2].get_path() \
					and gain_buttons[2].focus_neighbor_bottom == gain_buttons[0].get_path(),
			"gargoyle choice should trap and wrap keyboard focus"
		)
		var selected_id := StringName(
			(app.session.state.effect_state.get("eligible_card_ids", []) as Array)[0]
		)
		gain_buttons[0].pressed.emit()
		await process_frame
		_expect(app.session.state.effect_state.is_empty(), "gargoyle HUD should submit selection")
		_expect(
			ZoneService.find_card_zone(app.session.state, selected_id) == &"p1:discard-pile",
			"gargoyle HUD should move the chosen recruit into own discard"
		)
		_expect(
			app.hud.event_label.text.begins_with("已從招募區取得："),
			"gargoyle HUD should announce the committed recruit gain"
		)
	app.queue_free()


func _test_shop_gain_choice_hud_integration() -> void:
	var packed := load("res://scenes/boot/main.tscn") as PackedScene
	var app := packed.instantiate() as GameApp
	root.add_child(app)
	await process_frame
	var definitions := _load_definitions()
	var fixture := _build_public_gain_fixture(
		291, &"card-monster-ogre-01", SupplyService.SHOP_ROW_ID, definitions
	)
	app.session.state = fixture["state"] as GameStateData
	app.session.content_registry.definitions = fixture["definitions"] as Dictionary
	app.session._emit_state_changed()
	var phase_result := app.session.end_phase()
	_expect(bool(phase_result.get("ok", false)), "shop gain HUD should enter combat")
	var attack_result := app.session.attack_target(&"card-monster-ogre-01", true)
	_expect(bool(attack_result.get("ok", false)), "shop gain HUD should create a shop choice")
	await process_frame
	var gain_buttons: Array[Button] = []
	var cost_labels := 0
	var skip_buttons := 0
	for child: Node in app.hud.hand_actions.get_children():
		if child is Button and (child as Button).text == "從商店取得此牌":
			gain_buttons.append(child as Button)
		elif child is Label and "｜費用 " in (child as Label).text:
			cost_labels += 1
		elif child is Button and (child as Button).text.begins_with("略過"):
			skip_buttons += 1
	_expect(gain_buttons.size() == 2, "shop gain HUD should show cost-three and cost-four candidates")
	_expect(cost_labels == 2, "shop gain HUD should show each candidate card name and cost")
	_expect(skip_buttons == 0, "mandatory shop gain HUD must not show a skip action")
	_expect(
		"從商店取得 1 張費用不超過 4 的道具或裝備" in app.hud.hand_summary.text \
				and "來源：商店（2 張）" in app.hud.hand_summary.text,
		"shop gain HUD should show the complete prompt and source"
	)
	if gain_buttons.size() == 2:
		_expect(
			gain_buttons[0].focus_neighbor_top == gain_buttons[1].get_path() \
					and gain_buttons[1].focus_neighbor_bottom == gain_buttons[0].get_path(),
			"shop gain HUD should trap and wrap keyboard focus"
		)
		var selected_id := StringName(
			(app.session.state.effect_state.get("eligible_card_ids", []) as Array)[0]
		)
		gain_buttons[0].pressed.emit()
		await process_frame
		_expect(app.session.state.effect_state.is_empty(), "shop gain HUD should submit selection")
		_expect(
			ZoneService.find_card_zone(app.session.state, selected_id) == &"p1:discard-pile",
			"shop gain HUD should move the selected card into own discard"
		)
		_expect(
			app.hud.event_label.text.begins_with("已從商店取得："),
			"shop gain HUD should announce the correct public source"
		)
	app.queue_free()


func _test_fire_elemental_hud_integration() -> void:
	var packed := load("res://scenes/boot/main.tscn") as PackedScene
	var app := packed.instantiate() as GameApp
	root.add_child(app)
	await process_frame
	var expose_error := _expose_monster(
		app.session.state,
		&"card-monster-fire-elemental-01",
		&"card-monster-rabbit-demon-01"
	)
	_expect(expose_error.is_empty(), "fire elemental HUD fixture should expose the target")
	var phase_result := app.session.end_phase()
	_expect(bool(phase_result.get("ok", false)), "fire elemental HUD should enter combat")
	await process_frame
	var reward_button: Button
	var skip_reward_button: Button
	var inside_fire_actions := false
	for child: Node in app.hud.market_actions.get_children():
		if child is Label:
			var label_text := (child as Label).text
			if label_text.begins_with("火元素｜"):
				inside_fire_actions = true
			elif inside_fire_actions:
				break
		elif inside_fire_actions and child is Button:
			var button := child as Button
			if "棄掉全部手牌，再抽相同張數" in button.text:
				reward_button = button
			elif button.text == "討伐並略過獎勵":
				skip_reward_button = button
	_expect(reward_button != null, "fire elemental HUD should expose the redraw action")
	_expect(skip_reward_button != null, "fire elemental HUD should expose the skip action")
	if reward_button != null:
		_expect(
			"取得此卡（購買力 1／榮譽 3）" in reward_button.text,
			"fire elemental execute action should display the complete reward"
		)
	if reward_button != null and skip_reward_button != null:
		_expect(
			reward_button.focus_neighbor_bottom == skip_reward_button.get_path() \
					and skip_reward_button.focus_neighbor_top == reward_button.get_path(),
			"fire elemental execute and skip actions should remain in keyboard focus order"
		)
		reward_button.pressed.emit()
		await process_frame
		_expect(app.session.state.effect_state.is_empty(), "fire elemental HUD action should commit directly")
		_expect(
			(app.session.state.zones[&"p1:hand"] as ZoneData).card_instance_ids.size() == 5,
			"fire elemental HUD execution should restore the locked hand size"
		)
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


func _expose_monster(
	state: GameStateData,
	target_card_id: StringName,
	replaced_card_id: StringName
) -> String:
	var target_zone_id := ZoneService.find_card_zone(state, target_card_id)
	if target_zone_id == SupplyService.MONSTER_ROW_ID:
		return ""
	var move_result := ZoneService.move_card(
		state,
		replaced_card_id,
		SupplyService.MONSTER_ROW_ID,
		SupplyService.MONSTER_CYCLE_ID
	)
	if not bool(move_result.get("ok", false)):
		return str(move_result.get("error", "fixture_replacement_failed"))
	move_result = ZoneService.move_card(
		state,
		target_card_id,
		target_zone_id,
		SupplyService.MONSTER_ROW_ID
	)
	return "" if bool(move_result.get("ok", false)) else str(
		move_result.get("error", "fixture_target_failed")
	)


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
