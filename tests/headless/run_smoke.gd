extends SceneTree

const BossService = preload("res://domain/state/boss_service.gd")
const BossRuleEvaluator = preload("res://domain/rules/boss_rule_evaluator.gd")
const BondSuite = preload("res://tests/headless/bond_suite.gd")

var _failures: PackedStringArray = []


func _baseline_state(seed: int = 20260909, definitions: Dictionary = {}) -> GameStateData:
	# Legacy regression fixtures isolate their earlier card mechanics from the new global helper.
	return GameStateData.create_vertical_slice(seed, definitions, false, false)


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
	_test_official_resource_content_and_supply()
	_test_official_resource_core_effects()
	_test_official_resource_lifecycle_and_pending()
	_test_official_adventurer_content_and_supply()
	_test_official_adventurer_shared_operations()
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
	_test_boss_content_and_supply()
	_test_boss_combat_and_rest_reveal()
	_test_boss_multi_gain_and_atomicity()
	_test_boss_departure_replacement()
	_test_boss_attachment_transitions()
	_test_lich_success_and_failure()
	_test_combat_preview_and_reward()
	_test_combat_optional_reward_skip()
	_test_standard_monster_claim_and_draw_rewards()
	_test_mimic_dice_reward()
	_test_lamia_resource_draft()
	_test_automaton_archer_pending_choice()
	_test_automaton_warrior_discard_choice()
	_test_multi_zone_removal_monsters()
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
	await _test_official_adventurer_hud_integration()
	await _test_official_resource_hud_integration()
	await _test_combat_hud_integration()
	await _test_boss_hud_integration()
	await _test_boss_choice_hud_integration()
	await _test_pending_choice_hud_integration()
	await _test_discard_choice_hud_integration()
	await _test_multi_zone_removal_hud_integration()
	await _test_gargoyle_choice_hud_integration()
	await _test_shop_gain_choice_hud_integration()
	await _test_fire_elemental_hud_integration()
	await _test_mimic_and_lamia_hud_integration()
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
	_test_official_helper_content_and_setup()
	_test_official_helper_continuous_and_lifecycle()
	_test_official_helper_choices_and_rotation()
	await _test_official_helper_hud()
	_failures.append_array(BondSuite.new().run(_load_definitions()))
	await _test_bond_hud()


func _helper_state(number: int, seed: int = 1900) -> GameStateData:
	var definitions := _load_definitions()
	var state := GameStateData.create_vertical_slice(seed, definitions, true, false)
	state.effect_state.clear()
	for player_id: StringName in state.turn_order:
		(state.players[player_id] as PlayerStateData).reset_turn_scope()
	var active_id := HelperService.active_card_id(state)
	var target_id := StringName("card-helper-%02d" % number)
	if active_id != target_id:
		var source_id := ZoneService.find_card_zone(state, target_id)
		var out := ZoneService.move_card(state, active_id, HelperService.ACTIVE_ID, source_id)
		_expect(bool(out.get("ok", false)), "helper fixture should move the initial active card")
		var into := ZoneService.move_card(state, target_id, source_id, HelperService.ACTIVE_ID)
		_expect(bool(into.get("ok", false)), "helper fixture should reveal the target card")
	return state


func _test_official_helper_content_and_setup() -> void:
	var definitions := _load_definitions()
	var expected_names := ["流浪道具商人", "流浪道具商人", "公會櫃台小姐", "公會櫃台小姐", "酒吧老闆", "酒吧老闆", "謎之少女", "謎之少女", "武器舖店主", "武器舖店主", "情報商", "情報商"]
	for index in 12:
		var definition := definitions.get(StringName("base:helper/helper-%02d" % (index + 1))) as CardDefinition
		_expect(definition != null and definition.card_type == &"helper" and definition.copies == 1 and definition.display_name == expected_names[index] and not definition.rules_text.is_empty() and not definition.effects.is_empty(), "helper %02d should have formal content" % (index + 1))
	var first := GameStateData.create_vertical_slice(1911, definitions, true, false)
	var second := GameStateData.create_vertical_slice(1911, definitions, true, false)
	_expect(CanonicalJson.sha256(first.to_dictionary()) == CanonicalJson.sha256(second.to_dictionary()), "helper setup should be deterministic")
	_expect(InvariantService.validate(first).is_empty(), "helper setup should satisfy invariants")
	var total := 0
	for zone_id in [HelperService.DECK_ID, HelperService.ACTIVE_ID, HelperService.RESERVE_ID, HelperService.REMOVED_ID]:
		total += (first.zones[zone_id] as ZoneData).card_instance_ids.size()
	_expect(total == 12 and (first.zones[HelperService.ACTIVE_ID] as ZoneData).card_instance_ids.size() == 1 and (first.zones[HelperService.DECK_ID] as ZoneData).card_instance_ids.size() == 3, "helper setup should select one per boss and reveal exactly one")
	var snapshot := SnapshotCodec.encode(first, "helper-content", "helper-rules")
	var restored := SnapshotCodec.decode(snapshot, "helper-content", "helper-rules")
	_expect(bool(restored.get("ok", false)) and CanonicalJson.sha256((restored.get("state") as GameStateData).to_dictionary()) == CanonicalJson.sha256(first.to_dictionary()), "initial helper state should round-trip")


func _test_official_helper_continuous_and_lifecycle() -> void:
	var definitions := _load_definitions()
	for spec in [[1, SupplyService.SHOP_ROW_ID, &"item"], [6, SupplyService.RECRUIT_ROW_ID, &"adventurer"], [9, SupplyService.SHOP_ROW_ID, &"equipment"]]:
		var state := _helper_state(int(spec[0]), 1920 + int(spec[0]))
		var row := state.zones[spec[1]] as ZoneData
		var found := false
		for card_id: StringName in row.card_instance_ids:
			var card := state.cards[card_id] as Dictionary
			var definition := definitions[StringName(card["definition_id"])] as CardDefinition
			if definition.card_type == spec[2]:
				found = ResourceService.effective_purchase_cost(state, &"p1", card_id, definitions) == maxi(0, int(definition.cost) - 1)
				break
		_expect(found, "helper %s should discount its official purchase category" % spec[0])
	var rest_six := _helper_state(7, 1927)
	_expect(HelperService.rule_amount(rest_six, definitions, &"rest_hand_size", 5) == 6, "helper 07 should replace rest hand size with six")
	var cap := _helper_state(8, 1928)
	_expect(HelperService.party_capacity(cap, definitions) == 6, "helper 08 should raise party capacity")
	var buy := _helper_state(4, 1924)
	var buy_player := buy.players[&"p1"] as PlayerStateData
	buy_player.turn_facts[&"defeated_enemy"] = true
	buy.phase = &"action2"
	var buy_result := RulesEngine.dispatch(buy, _end_phase_envelope(buy, "helper-buy-start"), definitions)
	_expect(bool(buy_result.get("ok", false)) and (buy_result.get("state") as GameStateData).phase == &"purchase" and int(((buy_result.get("state") as GameStateData).players[&"p1"] as PlayerStateData).turn_resources.get(&"purchase_power", 0)) == 5, "helper 04 should award once at the purchase boundary")
	var reveal := _helper_state(3, 1923)
	var reveal_player := reveal.players[&"p1"] as PlayerStateData
	var draw_zone := StringName(reveal_player.zone_ids[&"draw_pile"])
	var enemy_id := &"card-monster-mimic-02"
	var enemy_move := ZoneService.move_card(reveal, enemy_id, ZoneService.find_card_zone(reveal, enemy_id), draw_zone)
	_expect(bool(enemy_move.get("ok", false)), "helper 03 test enemy should enter draw pile")
	(reveal.cards[enemy_id] as Dictionary)["owner_id"] = "p1"
	var reveal_events: Array[Dictionary] = []
	var reveal_error := HelperService.trigger(reveal, &"p1", &"on_purchase_start", reveal_events, definitions)
	_expect(reveal_error.is_empty() and ZoneService.find_card_zone(reveal, enemy_id) == StringName(reveal_player.zone_ids[&"hand"]), "helper 03 should publicly reveal and gain enemy cards")
	var capacity_state := _helper_state(8, 1938)
	var extra_id := _move_definition_to_player_hand(capacity_state, &"base:adventurer/adventurer-01", &"p1")
	var joined := PartyService.apply(capacity_state, &"p1", {"card_instance_id":str(extra_id)}, definitions, [])
	_expect(joined.is_empty() and (capacity_state.zones[StringName((capacity_state.players[&"p1"] as PlayerStateData).zone_ids[&"party"])] as ZoneData).card_instance_ids.size() == 6, "helper 08 should allow a sixth party member")
	var attached_id := _move_definition_to_player_hand(capacity_state, &"base:resource/resource-02", &"p1")
	var equip_events: Array[Dictionary] = []
	var equip_error := EquipmentService.apply(capacity_state, &"p1", {"type":"EQUIP_ITEM","card_instance_id":str(attached_id),"target_card_id":str(extra_id)}, definitions, equip_events)
	_expect(equip_error.is_empty(), "helper 08 fixture should attach equipment to sixth member")
	var departure_events: Array[Dictionary] = []
	var departure_error := HelperService.rotate(capacity_state, &"p1", departure_events, definitions)
	_expect(departure_error.is_empty() and ZoneService.find_card_zone(capacity_state, extra_id) == StringName((capacity_state.players[&"p1"] as PlayerStateData).zone_ids[&"discard_pile"]), "helper 08 departure should discard rightmost excess member")
	if equip_error.is_empty() and departure_error.is_empty():
		var attachment_state := (capacity_state.cards[attached_id] as Dictionary).get("state", {}) as Dictionary
		_expect(ZoneService.find_card_zone(capacity_state, attached_id) == StringName((capacity_state.players[&"p1"] as PlayerStateData).zone_ids[&"discard_pile"]) and not attachment_state.has("equipped_to") and ((capacity_state.cards[extra_id] as Dictionary).get("state", {}) as Dictionary).get("equipment_ids", []) == [], "helper 08 capacity shrink should discard equipment and clear both attachment links")


func _test_official_helper_choices_and_rotation() -> void:
	var definitions := _load_definitions()
	var transfer := _helper_state(11, 1941)
	var transfer_events: Array[Dictionary] = []
	var transfer_error := HelperService.trigger(transfer, &"p1", &"on_turn_start", transfer_events, definitions)
	_expect(transfer_error.is_empty() and StringName(transfer.effect_state.get("op", "")) == &"choose_transfer_card", "helper 11 should force a hand transfer choice")
	_expect(RulesEngine.get_legal_commands(transfer, &"p2", definitions).is_empty() and RulesEngine.get_legal_commands(transfer, &"p1", definitions).size() == 5, "helper 11 pending choice should close all other legal commands")
	var hand_card := StringName((transfer.effect_state.get("eligible_card_ids", []) as Array)[0])
	var invalid := RulesEngine.dispatch(transfer, _command_envelope(transfer, {"type":"RESOLVE_CHOICE","choice_id":str(transfer.effect_state["choice_id"]),"card_instance_id":str(hand_card),"skip":true}, "helper-invalid-skip"), definitions)
	_expect(not bool(invalid.get("ok", false)) and invalid.get("before_hash") == invalid.get("after_hash"), "helper 11 may not skip or mutate on invalid choice")
	var wrong_envelope := _command_envelope(transfer, {"type":"RESOLVE_CHOICE","choice_id":str(transfer.effect_state["choice_id"]),"card_instance_id":str(hand_card),"skip":false}, "helper-wrong-actor")
	wrong_envelope["actor_id"] = "p2"
	var wrong := RulesEngine.dispatch(transfer, wrong_envelope, definitions)
	_expect(not bool(wrong.get("ok", false)) and wrong.get("before_hash") == wrong.get("after_hash"), "helper 11 should reject wrong actor atomically")
	var empty_hand := _helper_state(11, 1944)
	var empty_player := empty_hand.players[&"p1"] as PlayerStateData
	var empty_hand_zone := empty_hand.zones[StringName(empty_player.zone_ids[&"hand"])] as ZoneData
	for card_id: StringName in empty_hand_zone.card_instance_ids.duplicate():
		ZoneService.move_card(empty_hand, card_id, empty_hand_zone.zone_id, StringName(empty_player.zone_ids[&"discard_pile"]))
	var empty_events: Array[Dictionary] = []
	var empty_error := HelperService.trigger(empty_hand, &"p1", &"on_turn_start", empty_events, definitions)
	_expect(empty_error.is_empty() and empty_hand.effect_state.is_empty(), "helper 11 should complete without pending when hand is empty")
	var moved := RulesEngine.dispatch(transfer, _command_envelope(transfer, {"type":"RESOLVE_CHOICE","choice_id":str(transfer.effect_state["choice_id"]),"card_instance_id":str(hand_card),"skip":false}, "helper-transfer"), definitions)
	_expect(bool(moved.get("ok", false)), "helper 11 should transfer the chosen card")
	if bool(moved.get("ok", false)):
		var resulting := moved["state"] as GameStateData
		_expect(ZoneService.find_card_zone(resulting, hand_card) == StringName((resulting.players[&"p2"] as PlayerStateData).zone_ids[&"hand"]) and StringName((resulting.cards[hand_card] as Dictionary).get("owner_id", "")) == &"p2", "helper 11 should transfer zone and ownership to left player")
		var transfer_types: Array[String] = []
		for event: Dictionary in moved.get("events", []):
			transfer_types.append(str(event.get("type", "")))
		_expect(transfer_types.find("card_transferred") > 0 and transfer_types.find("choice_resolved") > transfer_types.find("card_transferred"), "helper transfer should order move, ownership event, then choice completion")
	var rest := _helper_state(2, 1942)
	var item_id := _move_definition_to_player_hand(rest, &"base:resource/resource-01", &"p1")
	var rest_player := rest.players[&"p1"] as PlayerStateData
	ZoneService.move_card(rest, item_id, StringName(rest_player.zone_ids[&"hand"]), StringName(rest_player.zone_ids[&"discard_pile"]))
	rest.phase = &"rest"
	var rest_step := RulesEngine.dispatch(rest, _end_phase_envelope(rest, "helper-rest"), definitions)
	_expect(bool(rest_step.get("ok", false)) and StringName((rest_step.get("state") as GameStateData).effect_state.get("op", "")) == &"choose_move_card", "helper 02 should pause rest after cleanup and before draw")
	if bool(rest_step.get("ok", false)):
		var pending := rest_step["state"] as GameStateData
		var rest_choice := RulesEngine.dispatch(pending, _command_envelope(pending, {"type":"RESOLVE_CHOICE","choice_id":str(pending.effect_state["choice_id"]),"card_instance_id":str(item_id),"skip":false}, "helper-rest-choice"), definitions)
		_expect(bool(rest_choice.get("ok", false)), "helper 02 should resolve rest choice")
		if bool(rest_choice.get("ok", false)):
			var done := rest_choice["state"] as GameStateData
			_expect(done.active_player_id == &"p2" and ZoneService.find_card_zone(done, item_id) == StringName(rest_player.zone_ids[&"hand"]), "helper 02 selected item should be drawn before turn rotation")
	var bar := _helper_state(5, 1945)
	var bar_player := bar.players[&"p1"] as PlayerStateData
	var adventurer_id := _move_definition_to_player_hand(bar, &"base:adventurer/adventurer-03", &"p1")
	ZoneService.move_card(bar, adventurer_id, StringName(bar_player.zone_ids[&"hand"]), StringName(bar_player.zone_ids[&"discard_pile"]))
	var bar_events: Array[Dictionary] = []
	var bar_error := HelperService.trigger(bar, &"p1", &"on_turn_start", bar_events, definitions)
	_expect(bar_error.is_empty() and StringName(bar.effect_state.get("op", "")) == &"choose_move_card", "helper 05 should offer a turn-start adventurer recovery")
	var bar_repeat_events: Array[Dictionary] = []
	var bar_repeat := HelperService.trigger(bar, &"p1", &"on_turn_start", bar_repeat_events, definitions)
	_expect(bar_repeat.is_empty() and bar_repeat_events.is_empty(), "helper 05 should not trigger twice in one turn")
	if not bar.effect_state.is_empty():
		var bar_result := RulesEngine.dispatch(bar, _command_envelope(bar, {"type":"RESOLVE_CHOICE","choice_id":str(bar.effect_state["choice_id"]),"card_instance_id":str(adventurer_id),"skip":false}, "helper-bar-recover"), definitions)
		_expect(bool(bar_result.get("ok", false)) and ZoneService.find_card_zone(bar_result.get("state") as GameStateData, adventurer_id) == StringName(bar_player.zone_ids[&"hand"]), "helper 05 should recover the chosen adventurer")
	var smith := _helper_state(10, 1950)
	var smith_player := smith.players[&"p1"] as PlayerStateData
	var equipment_id := _move_definition_to_player_hand(smith, &"base:resource/resource-02", &"p1")
	ZoneService.move_card(smith, equipment_id, StringName(smith_player.zone_ids[&"hand"]), StringName(smith_player.zone_ids[&"discard_pile"]))
	smith.phase = &"rest"
	var smith_rest := RulesEngine.dispatch(smith, _end_phase_envelope(smith, "helper-smith-rest"), definitions)
	_expect(bool(smith_rest.get("ok", false)) and StringName((smith_rest.get("state") as GameStateData).effect_state.get("op", "")) == &"choose_move_card", "helper 10 should offer only equipment recovery before rest draw")
	if bool(smith_rest.get("ok", false)):
		var smith_pending := smith_rest["state"] as GameStateData
		_expect(str(equipment_id) in (smith_pending.effect_state.get("eligible_card_ids", []) as Array) and str(item_id) not in (smith_pending.effect_state.get("eligible_card_ids", []) as Array), "helper 10 should filter equipment candidates")
		var smith_choice := RulesEngine.dispatch(smith_pending, _command_envelope(smith_pending, {"type":"RESOLVE_CHOICE","choice_id":str(smith_pending.effect_state["choice_id"]),"card_instance_id":"","skip":true}, "helper-smith-skip"), definitions)
		_expect(bool(smith_choice.get("ok", false)) and (smith_choice.get("state") as GameStateData).active_player_id == &"p2", "helper 10 may be skipped and rest should continue")
	var draft := _helper_state(12, 1943)
	var draft_events: Array[Dictionary] = []
	var draft_error := HelperService.trigger(draft, &"p1", &"on_enter_helper", draft_events, definitions)
	_expect(draft_error.is_empty() and StringName(draft.effect_state.get("op", "")) == &"choose_supply_deck_draft", "helper 12 should ask the active player to choose a supply deck")
	var source_snapshot := SnapshotCodec.encode(draft, "helper-content", "helper-rules")
	_expect(bool(SnapshotCodec.decode(source_snapshot, "helper-content", "helper-rules").get("ok", false)), "helper source-selection pending should round-trip")
	var first_step := RulesEngine.dispatch(draft, _command_envelope(draft, {"type":"RESOLVE_CHOICE","choice_id":str(draft.effect_state["choice_id"]),"card_instance_id":str(SupplyService.RECRUIT_DECK_ID),"skip":false}, "helper-draft-source"), definitions)
	var first_repeat := RulesEngine.dispatch(draft.clone_state(), _command_envelope(draft, {"type":"RESOLVE_CHOICE","choice_id":str(draft.effect_state["choice_id"]),"card_instance_id":str(SupplyService.RECRUIT_DECK_ID),"skip":false}, "helper-draft-source"), definitions)
	_expect(bool(first_repeat.get("ok", false)) and first_step.get("after_hash") == first_repeat.get("after_hash"), "helper draft source step should replay with the same hash")
	var bad_source := RulesEngine.dispatch(draft, _command_envelope(draft, {"type":"RESOLVE_CHOICE","choice_id":str(draft.effect_state["choice_id"]),"card_instance_id":str(SupplyService.MONSTER_CYCLE_ID),"skip":false}, "helper-draft-wrong-source"), definitions)
	_expect(not bool(bad_source.get("ok", false)) and bad_source.get("before_hash") == bad_source.get("after_hash"), "helper 12 should reject non-supply source without mutation")
	var empty_shop := draft.clone_state()
	var sink := ZoneData.new(&"shared:helper-test-sink", &"removed", &"public")
	empty_shop.zones[sink.zone_id] = sink
	var shop := empty_shop.zones[SupplyService.SHOP_DECK_ID] as ZoneData
	for card_id: StringName in shop.card_instance_ids.duplicate():
		ZoneService.move_card(empty_shop, card_id, SupplyService.SHOP_DECK_ID, sink.zone_id)
	var empty_choice := RulesEngine.dispatch(empty_shop, _command_envelope(empty_shop, {"type":"RESOLVE_CHOICE","choice_id":str(empty_shop.effect_state["choice_id"]),"card_instance_id":str(SupplyService.SHOP_DECK_ID),"skip":false}, "helper-empty-shop"), definitions)
	_expect(bool(empty_choice.get("ok", false)) and (empty_choice.get("state") as GameStateData).effect_state.is_empty(), "helper 12 may choose an empty official deck and finish without a draft")
	var one_card := draft.clone_state()
	var one_card_sink := ZoneData.new(&"shared:helper-one-card-sink", &"removed", &"public")
	one_card.zones[one_card_sink.zone_id] = one_card_sink
	var recruit_deck := one_card.zones[SupplyService.RECRUIT_DECK_ID] as ZoneData
	for index in recruit_deck.card_instance_ids.size() - 1:
		var card_id: StringName = recruit_deck.card_instance_ids[0]
		ZoneService.move_card(one_card, card_id, recruit_deck.zone_id, one_card_sink.zone_id)
	var one_source := RulesEngine.dispatch(one_card, _command_envelope(one_card, {"type":"RESOLVE_CHOICE","choice_id":str(one_card.effect_state["choice_id"]),"card_instance_id":str(SupplyService.RECRUIT_DECK_ID),"skip":false}, "helper-one-source"), definitions)
	_expect(bool(one_source.get("ok", false)) and (one_source.get("state") as GameStateData).effect_state.get("selection_order", []) == ["p1"], "helper 12 should draft only available supply cards")
	_expect(bool(first_step.get("ok", false)), "helper 12 source selection should reveal a formal draft zone")
	if bool(first_step.get("ok", false)):
		var first_state := first_step["state"] as GameStateData
		_expect(StringName(first_state.effect_state.get("op", "")) == &"draft_gain_card" and (first_state.zones[HelperService.DRAFT_ROW_ID] as ZoneData).card_instance_ids.size() == 2, "helper 12 should reveal two official supply cards")
		var tampered := first_state.clone_state()
		var tampered_card := StringName((tampered.effect_state.get("remaining_card_ids", []) as Array)[0])
		ZoneService.move_card(tampered, tampered_card, HelperService.DRAFT_ROW_ID, StringName((tampered.players[&"p1"] as PlayerStateData).zone_ids[&"hand"]))
		(tampered.cards[tampered_card] as Dictionary)["owner_id"] = "p1"
		var tampered_result := RulesEngine.dispatch(tampered, _command_envelope(tampered, {"type":"RESOLVE_CHOICE","choice_id":str(tampered.effect_state["choice_id"]),"card_instance_id":str(tampered_card),"skip":false}, "helper-draft-tampered"), definitions)
		_expect(not bool(tampered_result.get("ok", false)) and tampered_result.get("before_hash") == tampered_result.get("after_hash"), "moved helper draft candidate should fail atomically")
		var first_card := StringName((first_state.effect_state.get("remaining_card_ids", []) as Array)[0])
		var first_pick := RulesEngine.dispatch(first_state, _command_envelope(first_state, {"type":"RESOLVE_CHOICE","choice_id":str(first_state.effect_state["choice_id"]),"card_instance_id":str(first_card),"skip":false}, "helper-draft-first"), definitions)
		var first_pick_repeat := RulesEngine.dispatch(first_state.clone_state(), _command_envelope(first_state, {"type":"RESOLVE_CHOICE","choice_id":str(first_state.effect_state["choice_id"]),"card_instance_id":str(first_card),"skip":false}, "helper-draft-first"), definitions)
		_expect(bool(first_pick_repeat.get("ok", false)) and first_pick.get("after_hash") == first_pick_repeat.get("after_hash"), "helper draft middle step should replay with the same hash")
		_expect(bool(first_pick.get("ok", false)), "helper 12 first player should choose")
		if bool(first_pick.get("ok", false)):
			var middle := first_pick["state"] as GameStateData
			_expect(middle.active_player_id == &"p1" and StringName(middle.effect_state.get("required_actor_id", "")) == &"p2" and RulesEngine.get_legal_commands(middle, &"p1", definitions).is_empty(), "helper 12 should keep turn actor but require next seat")
			var middle_snapshot := SnapshotCodec.encode(middle, "helper-content", "helper-rules")
			_expect(bool(SnapshotCodec.decode(middle_snapshot, "helper-content", "helper-rules").get("ok", false)), "helper draft middle state should round-trip")
			var last_card := StringName((middle.effect_state.get("remaining_card_ids", []) as Array)[0])
			var last_envelope := _command_envelope(middle, {"type":"RESOLVE_CHOICE","choice_id":str(middle.effect_state["choice_id"]),"card_instance_id":str(last_card),"skip":false}, "helper-draft-second")
			last_envelope["actor_id"] = "p2"
			var last_pick := RulesEngine.dispatch(middle, last_envelope, definitions)
			var last_repeat := RulesEngine.dispatch(middle.clone_state(), last_envelope, definitions)
			_expect(bool(last_repeat.get("ok", false)) and last_pick.get("after_hash") == last_repeat.get("after_hash"), "helper draft final step should replay with the same hash")
			_expect(bool(last_pick.get("ok", false)), "helper 12 second player should complete draft")
			if bool(last_pick.get("ok", false)):
				var finished := last_pick["state"] as GameStateData
				_expect(finished.effect_state.is_empty() and (finished.zones[HelperService.DRAFT_ROW_ID] as ZoneData).card_instance_ids.is_empty() and ZoneService.find_card_zone(finished, last_card) == StringName((finished.players[&"p2"] as PlayerStateData).zone_ids[&"hand"]), "helper 12 draft should finish with unique zones and correct owner")
				var final_snapshot := SnapshotCodec.encode(finished, "helper-content", "helper-rules")
				_expect(bool(SnapshotCodec.decode(final_snapshot, "helper-content", "helper-rules").get("ok", false)), "completed helper draft should round-trip")
	var rotation := _helper_state(12, 1953)
	var rotation_events: Array[Dictionary] = []
	var rotation_error := HelperService.rotate(rotation, &"p1", rotation_events, definitions)
	_expect(rotation_error.is_empty() and StringName(rotation.effect_state.get("op", "")) == &"choose_supply_deck_draft" and HelperService.active_card_id(rotation).is_empty(), "helper 12 departure should suspend next reveal until its draft completes")
	if rotation_error.is_empty() and not rotation.effect_state.is_empty():
		var rotation_source := RulesEngine.dispatch(rotation, _command_envelope(rotation, {"type":"RESOLVE_CHOICE","choice_id":str(rotation.effect_state["choice_id"]),"card_instance_id":str(SupplyService.SHOP_DECK_ID),"skip":false}, "helper-rotation-source"), definitions)
		_expect(bool(rotation_source.get("ok", false)), "helper leave draft should accept a supply source")
		if bool(rotation_source.get("ok", false)):
			var rotation_pending := rotation_source["state"] as GameStateData
			for picker in ["p1", "p2"]:
				var candidate := str((rotation_pending.effect_state.get("remaining_card_ids", []) as Array)[0])
				var envelope := _command_envelope(rotation_pending, {"type":"RESOLVE_CHOICE","choice_id":str(rotation_pending.effect_state["choice_id"]),"card_instance_id":candidate,"skip":false}, "helper-rotation-%s" % picker)
				envelope["actor_id"] = picker
				var pick := RulesEngine.dispatch(rotation_pending, envelope, definitions)
				_expect(bool(pick.get("ok", false)), "helper departure draft should accept each required actor")
				if not bool(pick.get("ok", false)):
					break
				rotation_pending = pick["state"] as GameStateData
			_expect(not HelperService.active_card_id(rotation_pending).is_empty() and (rotation_pending.zones[HelperService.DRAFT_ROW_ID] as ZoneData).card_instance_ids.is_empty(), "helper rotation should reveal the next helper only after outgoing draft completes")
	var boss_state := _helper_state(8, 1954)
	var boss_error := _expose_boss(boss_state, &"card-boss-10")
	_expect(boss_error.is_empty(), "helper Boss fixture should expose a simple Boss")
	var boss_events: Array[Dictionary] = []
	var completion := {"actor_id":"p1","target_card_id":"card-boss-10","participant_ids":[],"claim_optional_reward":true}
	var complete_error := BossService.complete_defeat(boss_state, &"p1", completion, boss_events, definitions)
	_expect(complete_error.is_empty(), "Boss defeat should invoke the shared helper transition")
	if complete_error.is_empty():
		var event_types: Array[String] = []
		for event: Dictionary in boss_events:
			event_types.append(str(event.get("type", "")))
		_expect(event_types.find("boss_defeated") >= 0 and event_types.find("helper_left") > event_types.find("boss_defeated") and event_types.find("helper_revealed") > event_types.find("helper_left"), "Boss victory should order helper leave before reveal")
		_expect(InvariantService.validate(boss_state).is_empty(), "Boss-triggered helper transition should keep zone uniqueness")
	var final_boss := _helper_state(12, 1955)
	_expect(_expose_boss(final_boss, &"card-boss-10").is_empty(), "final Boss fixture should expose target")
	var final_deck := final_boss.zones[BossService.BOSS_DECK_ID] as ZoneData
	for card_id: StringName in final_deck.card_instance_ids.duplicate():
		ZoneService.move_card(final_boss, card_id, final_deck.zone_id, BossService.BOSS_RESERVE_ID)
	var final_events: Array[Dictionary] = []
	var final_error := BossService.complete_defeat(final_boss, &"p1", completion, final_events, definitions)
	_expect(final_error.is_empty() and StringName(final_boss.effect_state.get("op", "")) == &"choose_supply_deck_draft", "last Boss should still trigger departing helper 12")
	if final_error.is_empty():
		var final_source := RulesEngine.dispatch(final_boss, _command_envelope(final_boss, {"type":"RESOLVE_CHOICE","choice_id":str(final_boss.effect_state["choice_id"]),"card_instance_id":str(SupplyService.SHOP_DECK_ID),"skip":false}, "helper-final-source"), definitions)
		_expect(bool(final_source.get("ok", false)), "last helper draft should accept supply choice")
		if bool(final_source.get("ok", false)):
			var final_pending := final_source["state"] as GameStateData
			for picker in ["p1", "p2"]:
				var candidate := str((final_pending.effect_state.get("remaining_card_ids", []) as Array)[0])
				var envelope := _command_envelope(final_pending, {"type":"RESOLVE_CHOICE","choice_id":str(final_pending.effect_state["choice_id"]),"card_instance_id":candidate,"skip":false}, "helper-final-%s" % picker)
				envelope["actor_id"] = picker
				var pick := RulesEngine.dispatch(final_pending, envelope, definitions)
				_expect(bool(pick.get("ok", false)), "last helper draft should complete each seat")
				if not bool(pick.get("ok", false)):
					break
				final_pending = pick["state"] as GameStateData
			_expect(final_pending.effect_state.is_empty() and HelperService.active_card_id(final_pending).is_empty(), "last Boss should not reveal a replacement helper")


func _test_official_helper_hud() -> void:
	var packed := load("res://scenes/boot/main.tscn") as PackedScene
	var app := packed.instantiate() as GameApp
	app.enable_helpers = true
	root.add_child(app)
	await process_frame
	app.session.state = _helper_state(12, 1952)
	var events: Array[Dictionary] = []
	var error := HelperService.trigger(app.session.state, &"p1", &"on_enter_helper", events, app.session.content_registry.definitions)
	_expect(error.is_empty(), "helper HUD fixture should enter source choice")
	app.session._emit_state_changed()
	await process_frame
	var helper_text := ""
	for child: Node in app.hud.market_actions.get_children():
		if child is Label:
			helper_text += (child as Label).text
	_expect("情報商" in helper_text and "進場" in helper_text, "helper HUD should show the current helper and full effect")
	var source_buttons: Array[Button] = []
	var source_labels := ""
	for child: Node in app.hud.hand_actions.get_children():
		if child is Button and "選擇" in (child as Button).text:
			source_buttons.append(child as Button)
		elif child is Label:
			source_labels += (child as Label).text
	_expect(source_buttons.size() == 2 and app.hud.end_phase_button.disabled, "helper source choice should offer two focus-trapped legal buttons")
	_expect("冒險者牌庫" in source_labels and "物資牌庫" in source_labels, "helper HUD should distinguish official draft supply sources")
	if source_buttons.size() == 2:
		_expect(source_buttons[0].focus_neighbor_bottom == source_buttons[1].get_path() and source_buttons[1].focus_neighbor_bottom == source_buttons[0].get_path(), "helper source choice focus should cycle")
	var source_result := app.session.resolve_choice(str(app.session.state.effect_state.get("choice_id", "")), SupplyService.RECRUIT_DECK_ID, false)
	_expect(bool(source_result.get("ok", false)), "helper HUD source choice should dispatch")
	await process_frame
	_expect("情報商物資輪抽" in app.hud.hand_title.text and "玩家一" in app.hud.hand_summary.text, "helper draft HUD should show title and required actor")
	if bool(source_result.get("ok", false)):
		var first_id := StringName((app.session.state.effect_state.get("remaining_card_ids", []) as Array)[0])
		var first_pick := app.session.resolve_choice(str(app.session.state.effect_state.get("choice_id", "")), first_id, false)
		_expect(bool(first_pick.get("ok", false)), "helper HUD first draft pick should dispatch")
		await process_frame
		_expect("玩家二" in app.hud.hand_summary.text and app.hud.end_phase_button.disabled and app.session.state.active_player_id == &"p1", "helper HUD should update required actor and keep ordinary actions closed")
	app.queue_free()
	await process_frame


func _test_bond_hud() -> void:
	var packed := load("res://scenes/boot/main.tscn") as PackedScene
	var app := packed.instantiate() as GameApp
	root.add_child(app)
	await process_frame
	_expect(app.session.state.bonds_enabled and "秘密羈絆設置" in app.hud.hand_title.text \
			and "玩家一" in app.hud.hand_summary.text and app.hud.end_phase_button.disabled,
		"bond HUD begins with private setup and closed ordinary commands")
	var labels := ""
	var buttons: Array[Button] = []
	for child: Node in app.hud.hand_actions.get_children():
		if child is Label:
			labels += (child as Label).text
		if child is Button:
			buttons.append(child as Button)
	_expect(buttons.size() == 7 and "榮譽" in labels and "效果：" in labels,
		"bond HUD shows seven candidates with full data")
	if buttons.size() == 7:
		_expect(buttons[0].focus_neighbor_top == buttons[6].get_path() \
				and buttons[6].focus_neighbor_bottom == buttons[0].get_path(),
			"bond setup focus remains cyclic")
	var first_private := str((app.session.state.effect_state.get("eligible_card_ids", []) as Array)[0])
	for _index in 10:
		var choice := app.session.state.effect_state
		if StringName(choice.get("op", "")) != &"select_bonds":
			break
		var pick := ""
		for raw_id: Variant in choice.get("eligible_card_ids", []):
			if str(raw_id) not in (choice.get("selected_card_ids", []) as Array):
				pick = str(raw_id)
				break
		var result := app.session.resolve_choice(str(choice.get("choice_id", "")), StringName(pick), false)
		_expect(bool(result.get("ok", false)), "bond HUD setup choice commits")
		if not bool(result.get("ok", false)):
			break
		await process_frame
		if StringName(app.session.state.effect_state.get("required_actor_id", "")) == &"p2":
			_expect("玩家二" in app.hud.hand_summary.text and app.hud.end_phase_button.disabled \
					and not app.hud._cards.has(first_private),
				"bond HUD changes to next required actor without leaking first player's bond")
	_expect(app.session.state.effect_state.is_empty() and "本人未完成羈絆" in _labels_text(app.hud.hand_actions),
		"bond HUD displays only current player's incomplete bonds after setup")
	if app.session.state.effect_state.is_empty():
		BondSuite.new()._install_bond(app.session.state, &"card-bond-24", &"p1")
		(app.session.state.players[&"p1"] as PlayerStateData).turn_facts["defeated_monster_count"] = 1
		var bond_events: Array[Dictionary] = []
		BondService.check(app.session.state, &"p1", &"after_defeat", {}, bond_events, app.session.content_registry.definitions)
		app.session._emit_state_changed()
		await process_frame
		var claim_buttons: Array[Button] = []
		for child: Node in app.hud.hand_actions.get_children():
			if child is Button:
				claim_buttons.append(child as Button)
		_expect("羈絆完成選擇" in app.hud.hand_title.text and "全場鎮壓" in _labels_text(app.hud.hand_actions) \
				and app.hud.end_phase_button.disabled and claim_buttons.size() >= 2,
			"bond HUD shows private claim candidates and confirmation")
		if claim_buttons.size() >= 2:
			_expect(claim_buttons[0].focus_neighbor_top == claim_buttons.back().get_path() \
					and claim_buttons.back().focus_neighbor_bottom == claim_buttons[0].get_path(),
				"bond completion focus remains cyclic")
		var claim := app.session.resolve_choice(
			str(app.session.state.effect_state.get("choice_id", "")), &"card-bond-24", false
		)
		_expect(bool(claim.get("ok", false)), "bond HUD stages selected claim")
		if bool(claim.get("ok", false)):
			await process_frame
			_expect("確認完成" in _button_text(app.hud.hand_actions), "bond HUD confirms staged subset")
			var committed := app.session.resolve_choice(
				str(app.session.state.effect_state.get("choice_id", "")), &"", true
			)
			_expect(bool(committed.get("ok", false)), "bond HUD confirms selected claim")
			await process_frame
			_expect("已完成羈絆" in app.hud.market_summary.text and "全場鎮壓" in app.hud.market_summary.text,
				"completed bond becomes public in HUD")
	app.queue_free()
	await process_frame


func _labels_text(container: Node) -> String:
	var result := ""
	for child: Node in container.get_children():
		if child is Label:
			result += (child as Label).text
	return result


func _button_text(container: Node) -> String:
	var result := ""
	for child: Node in container.get_children():
		if child is Button:
			result += (child as Button).text
	return result


func _test_content_pack() -> void:
	var registry := ContentRegistry.new()
	var errors := registry.load_pack("res://content/packs/base_vertical_slice.json")
	_expect(errors.is_empty(), "base content pack should validate: %s" % "; ".join(errors))
	_expect(registry.definitions.size() == 132, "base pack should load 132 formal definitions")
	var mimic := registry.definitions.get(&"base:monster/monster-02") as CardDefinition
	_expect(
		mimic != null and mimic.copies == 3 and mimic.combat == 5 \
				and mimic.purchase_power == 2 and mimic.honor == 5,
		"mimic should use the confirmed 3 copies and 5/2/5 values"
	)
	var lamia := registry.definitions.get(&"base:monster/monster-05") as CardDefinition
	_expect(
		lamia != null and lamia.copies == 2 and lamia.combat == 4 \
				and lamia.purchase_power == 1 and lamia.honor == 3,
		"lamia should use the confirmed 2 copies and 4/1/3 values"
	)
	var lizardfolk_mage := registry.definitions.get(&"base:monster/monster-03") as CardDefinition
	_expect(
		lizardfolk_mage != null and lizardfolk_mage.copies == 3 \
				and lizardfolk_mage.combat == 6 and lizardfolk_mage.purchase_power == 2 \
				and lizardfolk_mage.honor == 5,
		"lizardfolk mage should use the confirmed 3 copies and 6/2/5 values"
	)
	var golem := registry.definitions.get(&"base:monster/monster-06") as CardDefinition
	_expect(
		golem != null and golem.copies == 2 and golem.combat == 7 \
				and golem.purchase_power == 2 and golem.honor == 5,
		"golem should use the confirmed 2 copies and 7/2/5 values"
	)
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
	var monster_definition_ids: Array[StringName] = []
	var monster_copy_count := 0
	for definition_id: StringName in registry.definitions:
		var definition := registry.definitions[definition_id] as CardDefinition
		if definition.card_type == &"monster":
			monster_definition_ids.append(definition_id)
			monster_copy_count += definition.copies
	_expect(monster_definition_ids.size() == 14, "all fourteen base monster definitions should exist")
	_expect(monster_copy_count == 32, "base monster definitions should total thirty-two instances")
	var boss_count := 0
	for definition_id: StringName in registry.definitions:
		var definition := registry.definitions[definition_id] as CardDefinition
		if definition.card_type == &"boss":
			boss_count += 1
			_expect(definition.copies == 1, "each base boss should have exactly one copy")
	_expect(boss_count == 11, "all eleven formal base boss definitions should exist")


func _test_content_pack_reload() -> void:
	var registry := ContentRegistry.new()
	var first_errors := registry.load_pack("res://content/packs/base_vertical_slice.json")
	var first_fingerprint := registry.pack_fingerprint
	var second_errors := registry.load_pack("res://content/packs/base_vertical_slice.json")
	_expect(first_errors.is_empty() and second_errors.is_empty(), "content pack should be safely reloadable")
	_expect(registry.definitions.size() == 132, "content reload must not retain duplicate definitions")
	_expect(registry.pack_fingerprint == first_fingerprint, "same content should keep the same fingerprint")


func _test_official_resource_content_and_supply() -> void:
	var definitions := _load_definitions()
	var expected := [
		["特大治癒藥水","item",3,null,1,3], ["火焰拳套","equipment",5,1,2,3],
		["邪魅法典","equipment",5,1,2,3], ["驅邪聖水","item",2,null,1,2],
		["維修道具包","item",3,null,1,2], ["貓咪娃娃","item",1,null,-1,2],
		["透視眼鏡","equipment",5,1,2,2], ["櫻花果子","item",4,null,1,2],
		["詛咒之槍","equipment",6,3,3,2], ["大號梳毛梳","item",3,null,1,2],
		["寫滿的行程表","equipment",6,2,2,2], ["真龍斧連枷","equipment",5,3,2,2],
		["賢者之石","item",3,null,1,2], ["絲綢緞帶","equipment",3,null,2,2],
		["魔法除塵撢","item",4,null,1,2], ["鬼哭太刀","equipment",6,2,2,2],
		["金色水晶球","item",4,null,2,2], ["名貴的首飾","equipment",4,2,1,2],
		["靈能法杖","equipment",4,1,1,2], ["充能魔劍","equipment",5,2,2,2],
		["精緻的耳環","equipment",4,1,1,2], ["調教手銬","item",3,null,1,2],
		["元素卷軸","item",4,null,2,2], ["聖龍護符","equipment",4,1,1,2],
		["騎士之盾","equipment",5,1,2,2], ["專用茶杯","item",4,null,1,2],
		["牛皮紙樂譜","item",5,null,2,2], ["特製高級紅酒","item",3,null,1,2],
	]
	var copy_total := 0
	for index in expected.size():
		var definition_id := StringName("base:resource/resource-%02d" % (index + 1))
		var definition := definitions.get(definition_id) as CardDefinition
		var spec: Array = expected[index]
		_expect(definition != null, "official resource %02d should exist" % (index + 1))
		if definition == null: continue
		_expect(definition.display_name == spec[0] and str(definition.card_type) == spec[1] \
				and definition.cost == spec[2] and definition.combat == spec[3] \
				and definition.honor == spec[4] and definition.copies == spec[5] \
				and not definition.rules_text.is_empty(),
			"official resource %02d should match confirmed data" % (index + 1))
		copy_total += definition.copies
	_expect(copy_total == 59, "twenty-eight official resources should total fifty-nine copies")
	for definition_id: StringName in definitions:
		_expect(not str(definition_id).begins_with("custom:resource/"), "official pack must exclude custom resources")
	var first := _baseline_state(1801, definitions)
	var second := _baseline_state(1801, definitions)
	var resource_instance_count := 0
	var resource_zone_ids: Dictionary = {}
	for card_id: StringName in first.cards:
		var definition_id := str((first.cards[card_id] as Dictionary).get("definition_id", ""))
		if definition_id.begins_with("base:resource/resource-"):
			resource_instance_count += 1
			resource_zone_ids[str(card_id)] = str(ZoneService.find_card_zone(first, card_id))
	_expect(resource_instance_count == 59, "official resource supply should contain fifty-nine instances")
	_expect((first.zones[SupplyService.SHOP_ROW_ID] as ZoneData).card_instance_ids.size() == 3 \
			and (first.zones[SupplyService.SHOP_DECK_ID] as ZoneData).card_instance_ids.size() == 56,
		"shop should expose three cards and retain fifty-six hidden cards")
	_expect(CanonicalJson.sha256(first.to_dictionary()) == CanonicalJson.sha256(second.to_dictionary()),
		"same seed should produce deterministic official resource supply order")
	_expect(resource_zone_ids.size() == 59, "every resource instance should occupy exactly one formal zone")


func _test_official_resource_core_effects() -> void:
	var definitions := _load_definitions()
	var state := _baseline_state(1802, definitions)
	var player := state.players[&"p1"] as PlayerStateData
	var hand := state.zones[player.zone_ids[&"hand"]] as ZoneData
	var party := state.zones[player.zone_ids[&"party"]] as ZoneData
	var spear_id := _move_definition_to_player_hand(state, &"base:resource/resource-09", &"p1")
	var wearer_id := party.card_instance_ids[0]
	var equip_events: Array[Dictionary] = []
	_expect(EquipmentService.apply(state, &"p1", {"type":"EQUIP_ITEM","card_instance_id":str(spear_id),"target_card_id":str(wearer_id)}, definitions, equip_events).is_empty(), "cursed spear should equip")
	var normal_combat := ResourceService.evaluate_party_member_combat(state, definitions, wearer_id, 0, party, true, &"monster")
	var boss_combat := ResourceService.evaluate_party_member_combat(state, definitions, wearer_id, 0, party, true, &"boss")
	_expect(normal_combat == 4 and boss_combat == 6, "cursed spear should add two combat only against a Boss")

	var ribbon_id := _move_definition_to_player_hand(state, &"base:resource/resource-14", &"p1")
	var invalid_ribbon := EquipmentService.validate(state, &"p1", {"type":"EQUIP_ITEM","card_instance_id":str(ribbon_id),"target_card_id":str(party.card_instance_ids[1])}, definitions)
	_expect(invalid_ribbon == "equipment_target_tag_restricted", "silk ribbon should reject non-mage and non-support wearers")
	var mage_id := party.card_instance_ids[2]
	var before_left := ResourceService.evaluate_party_member_combat(state, definitions, party.card_instance_ids[1], 1, party)
	var before_right := ResourceService.evaluate_party_member_combat(state, definitions, party.card_instance_ids[3], 3, party)
	_expect(EquipmentService.apply(state, &"p1", {"type":"EQUIP_ITEM","card_instance_id":str(ribbon_id),"target_card_id":str(mage_id)}, definitions, equip_events).is_empty(), "silk ribbon should equip to a mage")
	_expect(ResourceService.evaluate_party_member_combat(state, definitions, party.card_instance_ids[1], 1, party) == before_left + 2 \
			and ResourceService.evaluate_party_member_combat(state, definitions, party.card_instance_ids[3], 3, party) == before_right + 2,
		"silk ribbon should add two combat to both adjacent adventurers only")
	var departure_events: Array[Dictionary] = []
	_expect(PartyService.discard_party_member_with_equipment(state, player, mage_id, &"combat_departure", departure_events, definitions).is_empty(), "silk ribbon combat departure should resolve")
	_expect(ZoneService.find_card_zone(state, ribbon_id) == StringName(player.zone_ids[&"removed"]), "silk ribbon should enter removed zone on combat departure")

	var cost_state := _baseline_state(1803, definitions)
	var cost_player := cost_state.players[&"p1"] as PlayerStateData
	var holy_water_id := _move_definition_to_player_hand(cost_state, &"base:resource/resource-04", &"p1")
	_expect(not _commands_contain(ItemService.get_legal_commands(cost_state, &"p1", definitions), "USE_ITEM"), "holy water should not be usable without a hand monster cost")
	var monster_id := &"card-monster-rabbit-demon-01"
	ZoneService.move_card(cost_state, monster_id, ZoneService.find_card_zone(cost_state, monster_id), StringName(cost_player.zone_ids[&"hand"]))
	(cost_state.cards[monster_id] as Dictionary)["owner_id"] = "p1"
	for resource_number in [1, 2, 3]:
		var draw_id := _find_instance_by_definition(cost_state, StringName("base:resource/resource-%02d" % resource_number))
		if draw_id in [holy_water_id]: continue
		ZoneService.move_card(cost_state, draw_id, ZoneService.find_card_zone(cost_state, draw_id), StringName(cost_player.zone_ids[&"draw_pile"]))
		(cost_state.cards[draw_id] as Dictionary)["owner_id"] = "p1"
	var use_result := RulesEngine.dispatch(cost_state, _command_envelope(cost_state, {"type":"USE_ITEM","card_instance_id":str(holy_water_id)}, "cmd-resource-cost"), definitions)
	_expect(bool(use_result.get("ok", false)), "holy water should establish a mandatory discard cost")
	if bool(use_result.get("ok", false)):
		cost_state = use_result["state"] as GameStateData
		var pending_hash := CanonicalJson.sha256(cost_state.to_dictionary())
		var invalid_result := RulesEngine.dispatch(cost_state, _command_envelope(cost_state, {"type":"RESOLVE_CHOICE","choice_id":str(cost_state.effect_state.get("choice_id", "")),"card_instance_id":"card-p1-summoning-stone-01","skip":false}, "cmd-resource-cost-invalid"), definitions)
		_expect(not bool(invalid_result.get("ok", false)) and invalid_result.get("after_hash") == pending_hash, "invalid resource cost must remain atomic")
		var pay_result := RulesEngine.dispatch(cost_state, _command_envelope(cost_state, {"type":"RESOLVE_CHOICE","choice_id":str(cost_state.effect_state.get("choice_id", "")),"card_instance_id":str(monster_id),"skip":false}, "cmd-resource-cost-pay"), definitions)
		_expect(bool(pay_result.get("ok", false)) and (pay_result["state"] as GameStateData).effect_state.is_empty(), "paying holy water cost should draw three and finish")

	var cat_state := _baseline_state(1804, definitions)
	var cat_player := cat_state.players[&"p1"] as PlayerStateData
	cat_state.phase = &"purchase"
	cat_player.turn_resources["purchase_power"] = 10
	var cat_id := _find_instance_by_definition(cat_state, &"base:resource/resource-06")
	var shop := cat_state.zones[SupplyService.SHOP_ROW_ID] as ZoneData
	ZoneService.move_card(cat_state, shop.card_instance_ids[0], shop.zone_id, SupplyService.SHOP_DECK_ID)
	ZoneService.move_card(cat_state, cat_id, ZoneService.find_card_zone(cat_state, cat_id), shop.zone_id)
	var buy_cat := RulesEngine.dispatch(cat_state, _command_envelope(cat_state, {"type":"BUY_CARD","card_instance_id":str(cat_id),"source_row_id":str(shop.zone_id)}, "cmd-buy-cat"), definitions)
	_expect(bool(buy_cat.get("ok", false)), "cat doll purchase should resolve")
	if bool(buy_cat.get("ok", false)):
		cat_state = buy_cat["state"] as GameStateData
		_expect(ZoneService.find_card_zone(cat_state, cat_id) == &"p2:discard-pile" and str((cat_state.cards[cat_id] as Dictionary).get("owner_id", "")) == "p2", "cat doll purchase should transfer to the right player")
		ZoneService.move_card(cat_state, cat_id, &"p2:discard-pile", &"p2:hand")
		var cleanup_events: Array[Dictionary] = []
		DeckService.discard_hand_and_play_area(cat_state, &"p2", cleanup_events)
		_expect(ZoneService.find_card_zone(cat_state, cat_id) == &"p1:discard-pile" and str((cat_state.cards[cat_id] as Dictionary).get("owner_id", "")) == "p1", "cat doll discard should continue around the two-player seating cycle")

	var tea_state := _baseline_state(1805, definitions)
	var tea_id := _move_definition_to_player_hand(tea_state, &"base:resource/resource-26", &"p1")
	var tea_result := RulesEngine.dispatch(tea_state, _command_envelope(tea_state, {"type":"USE_ITEM","card_instance_id":str(tea_id)}, "cmd-use-tea"), definitions)
	_expect(bool(tea_result.get("ok", false)), "special tea cup should be usable before defeating an enemy")
	if bool(tea_result.get("ok", false)):
		tea_state = tea_result["state"] as GameStateData
		var phase_result := RulesEngine.dispatch(tea_state, _end_phase_envelope(tea_state, "cmd-tea-end-action"), definitions)
		_expect(bool(phase_result.get("ok", false)) and (phase_result["state"] as GameStateData).phase == &"action2", "tea cup should skip combat without ending action1 early")


func _test_official_resource_lifecycle_and_pending() -> void:
	var definitions := _load_definitions()
	var scroll_state := _baseline_state(1806, definitions)
	var scroll_player := scroll_state.players[&"p1"] as PlayerStateData
	var scroll_id := _move_definition_to_player_hand(scroll_state, &"base:resource/resource-23", &"p1")
	var scroll_result := RulesEngine.dispatch(scroll_state, _command_envelope(scroll_state, {"type":"USE_ITEM","card_instance_id":str(scroll_id)}, "cmd-use-scroll"), definitions)
	_expect(bool(scroll_result.get("ok", false)), "element scroll should discard the complete party and hand before drawing")
	if bool(scroll_result.get("ok", false)):
		scroll_state = scroll_result["state"] as GameStateData
		_expect((scroll_state.zones[scroll_player.zone_ids[&"party"]] as ZoneData).card_instance_ids.is_empty(), "element scroll should discard the whole party")
		_expect(ZoneService.find_card_zone(scroll_state, scroll_id) == StringName(scroll_player.zone_ids[&"play_area"]), "used element scroll should remain in playArea")
		_expect(bool((scroll_state.players[&"p1"] as PlayerStateData).turn_facts.get("item_used:base:resource/resource-23", false)), "element scroll should record its once-per-turn use")
		var second_scroll := &"card-supply-resource-23-02"
		ZoneService.move_card(scroll_state, second_scroll, ZoneService.find_card_zone(scroll_state, second_scroll), StringName(scroll_player.zone_ids[&"hand"]))
		(scroll_state.cards[second_scroll] as Dictionary)["owner_id"] = "p1"
		var legal_items := ItemService.get_legal_commands(scroll_state, &"p1", definitions)
		var second_usable := false
		for command: Dictionary in legal_items:
			second_usable = second_usable or str(command.get("card_instance_id", "")) == str(second_scroll)
		_expect(not second_usable, "element scroll should not be usable twice in one turn")

	var wine_state := _baseline_state(1807, definitions)
	var wine_player := wine_state.players[&"p1"] as PlayerStateData
	var wine_id := _move_definition_to_player_hand(wine_state, &"base:resource/resource-28", &"p1")
	var adventurer_id := _move_definition_to_player_hand(wine_state, &"base:adventurer/adventurer-02", &"p1")
	for instance_id: StringName in [&"card-supply-resource-01-01", &"card-supply-resource-02-01", &"card-supply-resource-03-01"]:
		if instance_id == wine_id: continue
		ZoneService.move_card(wine_state, instance_id, ZoneService.find_card_zone(wine_state, instance_id), StringName(wine_player.zone_ids[&"draw_pile"]))
		(wine_state.cards[instance_id] as Dictionary)["owner_id"] = "p1"
	var wine_use := RulesEngine.dispatch(wine_state, _command_envelope(wine_state, {"type":"USE_ITEM","card_instance_id":str(wine_id)}, "cmd-use-wine"), definitions)
	_expect(bool(wine_use.get("ok", false)), "wine should request an adventurer discard cost")
	if bool(wine_use.get("ok", false)):
		wine_state = wine_use["state"] as GameStateData
		var wine_snapshot := SnapshotCodec.encode(wine_state, "content-test", "rules-test")
		var wine_restore := SnapshotCodec.decode(wine_snapshot, "content-test", "rules-test")
		_expect(bool(wine_restore.get("ok", false)) and CanonicalJson.sha256((wine_restore.get("state") as GameStateData).to_dictionary()) == CanonicalJson.sha256(wine_state.to_dictionary()), "resource cost pending choice should snapshot round-trip")
		var hand_before := (wine_state.zones[wine_player.zone_ids[&"hand"]] as ZoneData).card_instance_ids.size()
		var wine_pay := RulesEngine.dispatch(wine_state, _command_envelope(wine_state, {"type":"RESOLVE_CHOICE","choice_id":str(wine_state.effect_state.get("choice_id", "")),"card_instance_id":str(adventurer_id),"skip":false}, "cmd-pay-wine"), definitions)
		_expect(bool(wine_pay.get("ok", false)), "wine adventurer cost should resolve")
		if bool(wine_pay.get("ok", false)):
			var resolved_wine := wine_pay["state"] as GameStateData
			var hand_after := (resolved_wine.zones[(resolved_wine.players[&"p1"] as PlayerStateData).zone_ids[&"hand"]] as ZoneData).card_instance_ids.size()
			_expect(hand_after == hand_before - 1 + 3, "wine should draw the discarded adventurer's printed combat")

	var sword_state := _baseline_state(1808, definitions)
	var sword_player := sword_state.players[&"p1"] as PlayerStateData
	var sword_party := sword_state.zones[sword_player.zone_ids[&"party"]] as ZoneData
	var sword_id := _move_definition_to_player_hand(sword_state, &"base:resource/resource-16", &"p1")
	var sword_wearer := sword_party.card_instance_ids[3]
	var sword_events: Array[Dictionary] = []
	_expect(EquipmentService.apply(sword_state, &"p1", {"type":"EQUIP_ITEM","card_instance_id":str(sword_id),"target_card_id":str(sword_wearer)}, definitions, sword_events).is_empty(), "demon blade should equip to a tank")
	var enemy_cost_id := &"card-monster-rabbit-demon-01"
	ZoneService.move_card(sword_state, enemy_cost_id, ZoneService.find_card_zone(sword_state, enemy_cost_id), StringName(sword_player.zone_ids[&"hand"]))
	(sword_state.cards[enemy_cost_id] as Dictionary)["owner_id"] = "p1"
	sword_state.phase = &"combat"
	var sword_commands := RulesEngine.get_legal_commands(sword_state, &"p1", definitions)
	var activation: Dictionary = {}
	for command: Dictionary in sword_commands:
		if str(command.get("type", "")) == "ACTIVATE_EQUIPMENT_EFFECT" and str(command.get("card_instance_id", "")) == str(sword_id): activation = command
	_expect(not activation.is_empty(), "demon blade should expose a generic combat equipment command")
	if not activation.is_empty():
		var activate_result := RulesEngine.dispatch(sword_state, _command_envelope(sword_state, activation, "cmd-activate-sword"), definitions)
		_expect(bool(activate_result.get("ok", false)), "demon blade activation should create a mandatory serialized cost")
		if bool(activate_result.get("ok", false)):
			sword_state = activate_result["state"] as GameStateData
			var pay_sword := RulesEngine.dispatch(sword_state, _command_envelope(sword_state, {"type":"RESOLVE_CHOICE","choice_id":str(sword_state.effect_state.get("choice_id", "")),"card_instance_id":str(enemy_cost_id),"skip":false}, "cmd-pay-sword"), definitions)
			_expect(bool(pay_sword.get("ok", false)), "demon blade enemy discard should resolve")
			if bool(pay_sword.get("ok", false)):
				var sword_bonus := int((((pay_sword["state"] as GameStateData).players[&"p1"] as PlayerStateData).turn_bonuses.get("card_combat_modifiers", {}) as Dictionary).get(str(sword_wearer), 0))
				_expect(sword_bonus == 1, "demon blade should use the discarded enemy's printed purchase power")


func _test_official_adventurer_content_and_supply() -> void:
	var definitions := _load_definitions()
	var expected := [
		["麥娜",4,2,2,"support"], ["托妮卡",3,3,2,"melee"],
		["卡儂",4,3,1,"mage"], ["修爾蒂",4,2,2,"tank"],
		["哈貝妮",3,1,1,"support"], ["莉茲米",4,2,2,"melee"],
		["辛芙妮",3,2,1,"ranged"], ["旋律",3,2,1,"melee"],
		["芙尼姆",3,2,1,"tank"], ["慕莎",4,2,2,"melee"],
		["布蕾斯",4,1,1,"mage"], ["安比夏",3,2,2,"tank"],
		["芭米爾",4,1,1,"support"], ["席夢娜",4,0,1,"melee"],
		["阿爾可",3,2,2,"ranged"], ["神樂",4,3,2,"tank"],
		["蕾普莉絲",3,1,1,"support"], ["羅絲瑪莉",4,2,2,"melee"],
		["賽席莉亞",4,2,2,"mage"], ["費歐娜",3,5,1,"mage"],
		["阿爾梅斯",4,2,2,"melee"], ["露希艾拉",3,1,1,"tank"],
		["拉菲娜",3,1,1,"mage"], ["索娜莉亞",4,1,1,"melee"],
		["米莉安",4,2,2,"tank"], ["莉莉西斯",4,3,2,"ranged"],
		["娜塔莉絲",3,1,1,"support"], ["塔菲娜",3,1,1,"support"],
		["莉迪亞",4,1,1,"mage"], ["尤伊爾",5,0,3,"support"],
	]
	var total_copies := 0
	for index in expected.size():
		var definition_id := StringName("base:adventurer/adventurer-%02d" % (index + 1))
		var definition := definitions.get(definition_id) as CardDefinition
		var values: Array = expected[index]
		_expect(
			definition != null and definition.display_name == values[0] \
					and definition.copies == 2 and definition.cost == values[1] \
					and definition.combat == values[2] and definition.honor == values[3] \
					and &"adventurer" in definition.tags \
					and StringName(values[4]) in definition.tags \
					and not definition.rules_text.is_empty(),
			"official adventurer %02d should match confirmed data" % (index + 1)
		)
		if definition != null:
			total_copies += definition.copies
	_expect(total_copies == 60, "thirty official adventurers should total sixty copies")
	for definition_id: StringName in definitions:
		_expect(not str(definition_id).begins_with("custom:"), "custom adventurers must not enter the formal content pack")
	var first := _baseline_state(1700, definitions)
	var second := _baseline_state(1700, definitions)
	var first_deck := first.zones[SupplyService.RECRUIT_DECK_ID] as ZoneData
	var first_row := first.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData
	_expect(first_deck.card_instance_ids.size() + first_row.card_instance_ids.size() == 60, "official recruit supply should contain sixty unique instances")
	_expect(
		first_deck.card_instance_ids == (second.zones[SupplyService.RECRUIT_DECK_ID] as ZoneData).card_instance_ids \
				and first_row.card_instance_ids == (second.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData).card_instance_ids,
		"official recruit supply order should be deterministic for the same seed"
	)
	var seen: Dictionary = {}
	for zone: ZoneData in [first_deck, first_row]:
		for card_id: StringName in zone.card_instance_ids:
			seen[str(card_id)] = true
	_expect(seen.size() == 60, "official recruit instances must be unique across deck and row")


func _test_official_adventurer_shared_operations() -> void:
	var definitions := _load_definitions()
	var state := _baseline_state(1701, definitions)
	var player := state.players[&"p1"] as PlayerStateData
	var recovered_id := &"card-p1-starter-adventurer-01"
	ZoneService.move_card(state, recovered_id, player.zone_ids[&"party"], player.zone_ids[&"discard_pile"])
	var events: Array[Dictionary] = []
	var recover_effect: Array[Dictionary] = [{
		"op":"choose_move_card", "source_zone_key":"discard_pile",
		"destination_zone_key":"hand", "allowed_tags":["adventurer"],
		"amount":1, "optional":true, "prompt":"取回冒險者",
		"source_card_instance_id":"card-p1-starter-adventurer-02",
	}]
	var recover_error := EffectResolver.resolve(state, &"p1", recover_effect, events, definitions)
	_expect(recover_error.is_empty() and state.effect_state.get("op") == "choose_move_card", "shared move operation should create a serialized optional choice")
	var pending_hash := CanonicalJson.sha256(state.to_dictionary())
	var snapshot := SnapshotCodec.encode(state, "content-adventurer", "rules-adventurer")
	var restored := SnapshotCodec.decode(snapshot, "content-adventurer", "rules-adventurer")
	_expect(bool(restored.get("ok", false)) and CanonicalJson.sha256((restored.get("state") as GameStateData).to_dictionary()) == pending_hash, "adventurer pending move should round-trip")
	var illegal := RulesEngine.dispatch(state, _command_envelope(state, {
		"type":"RESOLVE_CHOICE", "choice_id":str(state.effect_state.get("choice_id", "")),
		"card_instance_id":"card-p1-summoning-stone-01", "skip":false,
	}, "cmd-adventurer-illegal"), definitions)
	_expect(not bool(illegal.get("ok", false)) and illegal.get("after_hash") == pending_hash, "invalid adventurer candidate must be atomic")
	var legal := RulesEngine.dispatch(state, _command_envelope(state, {
		"type":"RESOLVE_CHOICE", "choice_id":str(state.effect_state.get("choice_id", "")),
		"card_instance_id":str(recovered_id), "skip":false,
	}, "cmd-adventurer-recover"), definitions)
	_expect(bool(legal.get("ok", false)) and ZoneService.find_card_zone(legal["state"], recovered_id) == player.zone_ids[&"hand"], "shared move operation should recover the locked owned card")

	var inspect_state := _baseline_state(1702, definitions)
	var inspect_player := inspect_state.players[&"p1"] as PlayerStateData
	for raw_id: Variant in (inspect_state.zones[inspect_player.zone_ids[&"hand"]] as ZoneData).card_instance_ids.slice(0, 3):
		ZoneService.move_card(inspect_state, StringName(str(raw_id)), inspect_player.zone_ids[&"hand"], inspect_player.zone_ids[&"draw_pile"])
	var inspect_events: Array[Dictionary] = []
	var inspect_error := EffectResolver.resolve(inspect_state, &"p1", [{
		"op":"inspect_deck_top", "amount":3, "remove_max":1, "optional":true,
		"prompt":"查看並排序", "source_card_instance_id":"card-p1-starter-adventurer-02",
	}], inspect_events, definitions)
	_expect(inspect_error.is_empty() and inspect_state.effect_state.get("op") == "inspect_deck_top" and (inspect_state.zones[inspect_player.zone_ids[&"inspection"]] as ZoneData).card_instance_ids.size() == 3, "deck inspection must use a formal owner-only zone")
	var skip_command: Dictionary = {}
	for command: Dictionary in RulesEngine.get_legal_commands(inspect_state, &"p1", definitions):
		if bool(command.get("skip", false)):
			skip_command = command
	var skipped := RulesEngine.dispatch(inspect_state, _command_envelope(inspect_state, skip_command, "cmd-inspect-remove-skip"), definitions)
	_expect(bool(skipped.get("ok", false)) and (skipped["state"] as GameStateData).effect_state.get("op") == "order_deck_top", "inspection skip should continue into mandatory ordering: %s" % str(skipped.get("error", "wrong pending op")))
	if bool(skipped.get("ok", false)):
		var ordering := skipped["state"] as GameStateData
		var order_steps := 0
		while not ordering.effect_state.is_empty() and order_steps < 3:
			var commands := RulesEngine.get_legal_commands(ordering, &"p1", definitions)
			var ordered := RulesEngine.dispatch(ordering, _command_envelope(ordering, commands[0], "cmd-order-%d" % order_steps), definitions)
			_expect(bool(ordered.get("ok", false)), "each deck ordering step should commit")
			if not bool(ordered.get("ok", false)):
				break
			ordering = ordered["state"] as GameStateData
			order_steps += 1
		_expect(ordering.effect_state.is_empty() and (ordering.zones[inspect_player.zone_ids[&"inspection"]] as ZoneData).card_instance_ids.is_empty(), "deck ordering should restore every inspected card and clear pending state")

	var target_state := _baseline_state(1703, definitions)
	var target_events: Array[Dictionary] = []
	var target_error := EffectResolver.resolve(target_state, &"p1", [{
		"op":"choose_target_combat_modifier", "source_zone_id":str(SupplyService.MONSTER_ROW_ID),
		"allowed_card_types":["monster"], "amount":-2, "optional":true,
		"prompt":"指定魔物", "source_card_instance_id":"card-p1-starter-adventurer-02",
	}], target_events, definitions)
	var target_command := RulesEngine.get_legal_commands(target_state, &"p1", definitions)[0]
	var target_result := RulesEngine.dispatch(target_state, _command_envelope(target_state, target_command, "cmd-target-modifier"), definitions)
	_expect(target_error.is_empty() and bool(target_result.get("ok", false)) and not ((target_result["state"] as GameStateData).players[&"p1"] as PlayerStateData).turn_bonuses.get("target_combat_modifiers", {}).is_empty(), "public target modifier should lock and apply one legal monster")

	var departure_base := _baseline_state(1704, definitions)
	var departure_player := departure_base.players[&"p1"] as PlayerStateData
	var departure_party := departure_base.zones[departure_player.zone_ids[&"party"]] as ZoneData
	for starter_id: StringName in departure_party.card_instance_ids.duplicate():
		ZoneService.move_card(departure_base, starter_id, departure_player.zone_ids[&"party"], departure_player.zone_ids[&"discard_pile"])
	var almes_id := _find_instance_by_definition(departure_base, &"base:adventurer/adventurer-21")
	var almes_card := departure_base.cards[almes_id] as Dictionary
	almes_card["owner_id"] = "p1"
	ZoneService.move_card(departure_base, almes_id, ZoneService.find_card_zone(departure_base, almes_id), departure_player.zone_ids[&"party"])
	departure_base.phase = &"combat"
	departure_player.turn_resources[&"combat"] = 3
	var use_state := departure_base.clone_state()
	var skip_state := departure_base.clone_state()
	var use_command: Dictionary = {}
	var skip_departure_command: Dictionary = {}
	for command: Dictionary in RulesEngine.get_legal_commands(departure_base, &"p1", definitions):
		if command.get("target_card_id") != "card-monster-skeleton-01" or not bool(command.get("claim_optional_reward", false)):
			continue
		if bool(command.get("use_optional_departures", true)):
			use_command = command
		else:
			skip_departure_command = command
	_expect(not use_command.is_empty() and not skip_departure_command.is_empty(), "optional combat departure should expose execute and skip legal commands")
	var used := RulesEngine.dispatch(use_state, _command_envelope(use_state, use_command, "cmd-departure-use"), definitions)
	var declined := RulesEngine.dispatch(skip_state, _command_envelope(skip_state, skip_departure_command, "cmd-departure-skip"), definitions)
	_expect(bool(used.get("ok", false)) and ZoneService.find_card_zone(used["state"], almes_id) == departure_player.zone_ids[&"draw_pile"], "accepted departure replacement should place the adventurer on its own deck top")
	_expect(bool(declined.get("ok", false)) and ZoneService.find_card_zone(declined["state"], almes_id) == departure_player.zone_ids[&"discard_pile"], "declined departure replacement should use normal combat discard")


func _test_initial_invariants() -> void:
	var state := _baseline_state()
	var errors := InvariantService.validate(state)
	_expect(errors.is_empty(), "initial state should satisfy invariants: %s" % "; ".join(errors))


func _test_two_player_state() -> void:
	var state := _baseline_state()
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
	var state := _baseline_state()
	_expect(state.cards.size() == 182, "setup should include all formal supply and boss instances")
	var monster_instance_count := 0
	var monster_definition_ids: Dictionary = {}
	for card_instance_id: StringName in state.cards:
		var definition_id := StringName((state.cards[card_instance_id] as Dictionary).get("definition_id", ""))
		if str(definition_id).begins_with("base:monster/"):
			monster_instance_count += 1
			monster_definition_ids[definition_id] = true
	_expect(monster_instance_count == 32, "setup should instantiate all thirty-two base monsters")
	_expect(monster_definition_ids.size() == 14, "setup should include instances of all fourteen base monsters")
	_expect(
		(state.zones[SupplyService.RESOURCE_DRAFT_ROW_ID] as ZoneData).card_instance_ids.is_empty(),
		"formal resource draft row should start empty"
	)
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
	var wrong_seat := _baseline_state()
	(wrong_seat.players[&"p2"] as PlayerStateData).seat_index = 0
	_expect(not InvariantService.validate(wrong_seat).is_empty(), "duplicate player seats must fail invariants")

	var shared_zone := _baseline_state()
	var player_one := shared_zone.players[&"p1"] as PlayerStateData
	player_one.zone_ids[&"hand"] = player_one.zone_ids[&"draw_pile"]
	_expect(not InvariantService.validate(shared_zone).is_empty(), "player zone references must be unique")

	var exposed_hand := _baseline_state()
	(exposed_hand.zones[&"p1:hand"] as ZoneData).visibility = &"public"
	_expect(not InvariantService.validate(exposed_hand).is_empty(), "private hand zone must not become public")
	_expect(RulesEngine.get_legal_commands(exposed_hand, &"p1").is_empty(), "invalid state must expose no legal commands")

	var attachment_state := _baseline_state()
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
	var state := _baseline_state()
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
	var inactive := _baseline_state()
	inactive.status = &"finished"
	_expect(RulesEngine.get_legal_commands(inactive, &"p1").is_empty(), "finished game should expose no commands")
	var inactive_result := RulesEngine.dispatch(inactive, _end_phase_envelope(inactive, "cmd-inactive"))
	_expect(str(inactive_result.get("error", "")) == "game_not_active", "dispatcher must reject commands after game end")

	var pending := _baseline_state()
	pending.effect_state = {
		"type": "pending_choice",
		"choice_id": "choice-test",
		"actor_id": "p1",
		"op": "choose_remove_card",
		"prompt": "test",
		"source_zone_ids": {"hand": "p1:hand"},
		"source_zone_keys": ["hand"],
		"destination_zone_id": "p1:removed",
		"eligible_card_ids": ["card-p1-summoning-stone-01"],
		"eligible_card_sources": {
			"card-p1-summoning-stone-01": {"zone_key": "hand", "zone_id": "p1:hand"},
		},
		"min_selections": 0,
		"max_selections": 1,
		"selected_card_ids": [],
		"selected_count": 0,
		"effect_index": 0,
		"source_card_instance_id": "test-source",
	}
	_expect(
		not _commands_contain(RulesEngine.get_legal_commands(pending, &"p1"), "END_PHASE"),
		"pending effect should expose no END_PHASE"
	)
	var pending_result := RulesEngine.dispatch(pending, _end_phase_envelope(pending, "cmd-pending"))
	_expect(str(pending_result.get("error", "")) == "effects_pending", "dispatcher must enforce pending-effect legality")

	var wrong_actor := _baseline_state()
	var wrong_actor_envelope := _end_phase_envelope(wrong_actor, "cmd-wrong-actor")
	wrong_actor_envelope["actor_id"] = "p2"
	var wrong_actor_result := RulesEngine.dispatch(wrong_actor, wrong_actor_envelope)
	_expect(str(wrong_actor_result.get("error", "")) == "wrong_actor", "non-active player command must be rejected")


func _test_equip_item_legality_and_resources() -> void:
	var state := _baseline_state()
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
	var wrong_phase := _baseline_state()
	wrong_phase.phase = &"combat"
	var before_hash := CanonicalJson.sha256(wrong_phase.to_dictionary())
	var wrong_phase_result := RulesEngine.dispatch(
		wrong_phase,
		_equip_item_envelope(wrong_phase, &"card-p1-spirit-crystal-01", &"card-p1-starter-adventurer-01", "cmd-wrong-phase"),
		definitions
	)
	_expect(str(wrong_phase_result.get("error", "")) == "wrong_phase", "equipment may only be played during an action phase")
	_expect(CanonicalJson.sha256(wrong_phase.to_dictionary()) == before_hash, "wrong-phase play must not mutate state")

	var stone_state := _baseline_state()
	var stone_hash := CanonicalJson.sha256(stone_state.to_dictionary())
	var stone_result := RulesEngine.dispatch(
		stone_state,
		_equip_item_envelope(stone_state, &"card-p1-summoning-stone-01", &"card-p1-starter-adventurer-01", "cmd-play-stone"),
		definitions
	)
	_expect(str(stone_result.get("error", "")) == "unsupported_card_type", "summoning stones must stay in hand as passive purchase power")
	_expect(CanonicalJson.sha256(stone_state.to_dictionary()) == stone_hash, "unsupported card play must be atomic")

	var invalid_target := _baseline_state()
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
	var state := _baseline_state()
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
	var state := _baseline_state()
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

	var invalid_state := _baseline_state()
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
	var state := _baseline_state(211)
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
	var state := _baseline_state(219)
	var row := state.zones[SupplyService.MONSTER_ROW_ID] as ZoneData
	var cycle := state.zones[SupplyService.MONSTER_CYCLE_ID] as ZoneData
	_expect(row.card_instance_ids.size() == 3, "vertical slice should reveal three monsters")
	_expect(cycle.card_instance_ids.size() == 29, "vertical slice cycle should retain twenty-nine monsters")
	_expect(row.card_instance_ids.size() + cycle.card_instance_ids.size() == 32, "monster row and cycle should contain the complete base set")
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
	var same_seed := _baseline_state(219)
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


func _test_boss_content_and_supply() -> void:
	var definitions := _load_definitions()
	var expected_values := [
		["base:boss/boss-01", 9, 3, 10], ["base:boss/boss-02", 9, 3, 10],
		["base:boss/boss-03", 10, 3, 10], ["base:boss/boss-04", 5, 3, 10],
		["base:boss/boss-05", 9, 3, 10], ["base:boss/boss-06", 8, 3, 10],
		["base:boss/boss-07", 9, 3, 8], ["base:boss/boss-08", 9, 3, 8],
		["base:boss/boss-09", 8, 3, 8], ["base:boss/boss-10", 14, 3, 8],
		["base:boss/boss-11", 6, 3, 8],
	]
	for values: Array in expected_values:
		var definition := definitions.get(StringName(values[0])) as CardDefinition
		_expect(
			definition != null and definition.copies == 1 and definition.card_type == &"boss"
					and definition.combat == values[1] and definition.purchase_power == values[2]
					and definition.honor == values[3] and definition.framework_ready,
			"boss %s should use confirmed formal values" % values[0]
		)
	var expected_operations := {
		"base:boss/boss-01": [["modify_requirement_by_zone_count"], ["grant_purchase_power", "choose_gain_card"]],
		"base:boss/boss-02": [["replace_combat_departure"], ["gain_from_supply_deck", "grant_purchase_power", "gain_from_supply_deck"]],
		"base:boss/boss-03": [["post_departure_cost"], ["grant_purchase_power", "choose_remove_card"]],
		"base:boss/boss-04": [["attach_on_reveal"], ["grant_purchase_power", "draw"]],
		"base:boss/boss-05": [["suppress_equipment"], ["grant_purchase_power", "choose_gain_card"]],
		"base:boss/boss-06": [["modify_requirement_by_professions"], ["grant_purchase_power", "gain_from_supply_deck"]],
		"base:boss/boss-07": [["attach_on_reveal"], ["grant_purchase_power", "gain_from_supply_deck"]],
		"base:boss/boss-08": [["participant_limit"], ["grant_purchase_power", "choose_gain_card"]],
		"base:boss/boss-09": [["modify_requirement_by_professions"], ["grant_purchase_power", "gain_from_supply_deck"]],
		"base:boss/boss-10": [["modify_requirement_by_professions"], ["grant_purchase_power", "draw"]],
		"base:boss/boss-11": [["participant_limit"], ["grant_purchase_power", "choose_gain_card"]],
	}
	for definition_id: String in expected_operations:
		var definition := definitions[StringName(definition_id)] as CardDefinition
		var rule_ops: Array[String] = []
		var effect_ops: Array[String] = []
		for rule: Dictionary in definition.special_rules:
			rule_ops.append(str(rule.get("op", "")))
		for effect: Dictionary in definition.effects:
			effect_ops.append(str(effect.get("op", "")))
		_expect([rule_ops, effect_ops] == expected_operations[definition_id], "boss %s should keep its formal data-driven operations" % definition_id)
	var state := _baseline_state(503)
	var equipment_rule := BossRuleEvaluator.evaluate(
		state, &"p1", definitions[&"base:boss/boss-05"], definitions
	)
	var limit_rule := BossRuleEvaluator.evaluate(
		state, &"p1", definitions[&"base:boss/boss-08"], definitions
	)
	var left_rule := BossRuleEvaluator.evaluate(
		state, &"p1", definitions[&"base:boss/boss-09"], definitions
	)
	var troll_rule := BossRuleEvaluator.evaluate(
		state, &"p1", definitions[&"base:boss/boss-06"], definitions
	)
	var wolf_rule := BossRuleEvaluator.evaluate(
		state, &"p1", definitions[&"base:boss/boss-11"], definitions
	)
	_expect(bool(equipment_rule.get("equipment_suppressed", false)), "shared boss rules should suppress equipment when declared")
	_expect(int(limit_rule.get("participant_limit", -1)) == 3, "shared boss rules should apply participant limits")
	_expect(int(left_rule.get("requirement", 0)) == 13, "shared boss rules should evaluate the left player's five public professions")
	_expect(int(troll_rule.get("requirement", 0)) == 13, "shared boss rules should evaluate the active player's full-party professions")
	_expect(int(wolf_rule.get("participant_limit", -1)) == 1, "shared boss rules should support a single front participant")
	var active := state.zones[BossService.BOSS_ACTIVE_ID] as ZoneData
	var deck := state.zones[BossService.BOSS_DECK_ID] as ZoneData
	var reserve := state.zones[BossService.BOSS_RESERVE_ID] as ZoneData
	_expect(active.card_instance_ids.size() == 1, "setup should reveal one boss")
	_expect(deck.card_instance_ids.size() == 3, "two-player setup should keep three bosses in its deck")
	_expect(reserve.card_instance_ids.size() == 7, "unselected bosses should remain in the formal reserve")
	_expect(active.card_instance_ids.size() + deck.card_instance_ids.size() + reserve.card_instance_ids.size() == 11, "every boss instance should occupy exactly one boss zone")
	var repeated := _baseline_state(503)
	_expect(
		CanonicalJson.sha256(state.to_dictionary()) == CanonicalJson.sha256(repeated.to_dictionary()),
		"boss selection and reveal should be deterministic for the same seed"
	)
	var restored := GameStateData.from_dictionary(state.to_dictionary())
	_expect(
		CanonicalJson.sha256(restored.to_dictionary()) == CanonicalJson.sha256(state.to_dictionary()),
		"boss zones should survive snapshot-shaped round trip"
	)


func _test_boss_combat_and_rest_reveal() -> void:
	var definitions := _load_definitions()
	var state := _baseline_state(509)
	var setup_error := _expose_boss(state, &"card-boss-10")
	_expect(setup_error.is_empty(), "boss combat fixture should expose slime girl")
	if not setup_error.is_empty():
		return
	state.phase = &"combat"
	(state.players[&"p1"] as PlayerStateData).turn_resources["combat"] = 20
	var preview := CombatService.preview_attack(state, &"p1", &"card-boss-10", definitions)
	_expect(bool(preview.get("legal", false)) and preview.get("target_type") == "boss", "ready boss should enter shared target-aware combat")
	_expect(int(preview.get("requirement", -1)) == 9, "slime girl should subtract five distinct starting professions")
	var deck_target := (state.zones[BossService.BOSS_DECK_ID] as ZoneData).card_instance_ids[0]
	var before_invalid := CanonicalJson.sha256(state.to_dictionary())
	var invalid := RulesEngine.dispatch(
		state,
		_command_envelope(state, {"type": "ATTACK_TARGET", "target_card_id": str(deck_target), "claim_optional_reward": true}, "cmd-boss-invalid"),
		definitions
	)
	_expect(not bool(invalid.get("ok", false)) and invalid.get("after_hash") == before_invalid, "boss attacks from a non-active zone should be rejected atomically")
	var envelope := _command_envelope(
		state,
		{"type": "ATTACK_TARGET", "target_card_id": "card-boss-10", "claim_optional_reward": true},
		"cmd-boss-defeat"
	)
	var first := RulesEngine.dispatch(state, envelope, definitions)
	var second := RulesEngine.dispatch(state.clone_state(), envelope, definitions)
	_expect(bool(first.get("ok", false)) and first.get("after_hash") == second.get("after_hash"), "boss combat should replay to the same canonical hash")
	if not bool(first.get("ok", false)):
		return
	state = first["state"] as GameStateData
	var player := state.players[&"p1"] as PlayerStateData
	_expect(int(player.turn_resources.get("purchase_power", 0)) == 5, "boss reward should grant purchase power")
	_expect(int(player.counters.get(&"defeated_boss_count", 0)) == 1, "boss defeat should update persistent player statistics")
	_expect(ZoneService.find_card_zone(state, &"card-boss-10") == player.zone_ids[&"discard_pile"], "defeated boss should enter the winner discard pile with ownership")
	_expect((state.zones[BossService.BOSS_ACTIVE_ID] as ZoneData).card_instance_ids.is_empty(), "defeated boss should leave an empty active slot until rest")
	var event_types: Array[String] = []
	for event: Dictionary in first.get("events", []):
		event_types.append(str(event.get("type", "")))
	_expect(event_types.find("effect_resolved") < event_types.find("boss_defeated") and event_types.find("boss_defeated") < event_types.find("enemy_defeated"), "boss rewards, defeat, and enemy completion events should stay ordered")
	var restored := GameStateData.from_dictionary(state.to_dictionary())
	_expect(CanonicalJson.sha256(restored.to_dictionary()) == CanonicalJson.sha256(state.to_dictionary()), "post-defeat boss transition should round-trip")
	for index in 4:
		var phase_result := RulesEngine.dispatch(state, _end_phase_envelope(state, "cmd-boss-rest-%d" % index), definitions)
		_expect(bool(phase_result.get("ok", false)), "boss rest transition %d should dispatch" % index)
		if not bool(phase_result.get("ok", false)):
			return
		state = phase_result["state"] as GameStateData
	_expect((state.zones[BossService.BOSS_ACTIVE_ID] as ZoneData).card_instance_ids.size() == 1, "rest should reveal the next boss")
	_expect(InvariantService.validate(state).is_empty(), "boss defeat and reveal should preserve zone uniqueness")


func _test_boss_multi_gain_and_atomicity() -> void:
	var definitions := _load_definitions()
	var state := _baseline_state(521)
	_expect(_expose_boss(state, &"card-boss-01").is_empty(), "multi-gain fixture should expose red dragon")
	var shop := state.zones[SupplyService.SHOP_ROW_ID] as ZoneData
	var shop_deck := state.zones[SupplyService.SHOP_DECK_ID] as ZoneData
	for card_id: StringName in shop.card_instance_ids.duplicate():
		ZoneService.move_card(state, card_id, shop.zone_id, shop_deck.zone_id)
	for card_id: StringName in [&"card-supply-resource-08-01", &"card-supply-resource-08-02"]:
		var source_id := ZoneService.find_card_zone(state, card_id)
		ZoneService.move_card(state, card_id, source_id, shop.zone_id)
	state.phase = &"combat"
	(state.players[&"p1"] as PlayerStateData).turn_resources["combat"] = 30
	var attack := RulesEngine.dispatch(
		state,
		_command_envelope(state, {"type": "ATTACK_TARGET", "target_card_id": "card-boss-01", "claim_optional_reward": true}, "cmd-boss-multi"),
		definitions
	)
	_expect(bool(attack.get("ok", false)), "red dragon should establish a multi-card gain")
	if not bool(attack.get("ok", false)):
		return
	state = attack["state"] as GameStateData
	_expect(state.effect_state.get("op") == "choose_gain_card" and int(state.effect_state.get("max_selections", 0)) == 2, "boss public-row reward should lock two selections")
	_expect(ZoneService.find_card_zone(state, &"card-boss-01") == BossService.BOSS_ACTIVE_ID, "boss should remain active while its reward choice is pending")
	var first_card_id := StringName((state.effect_state.get("eligible_card_ids", []) as Array)[0])
	var first_choice := RulesEngine.dispatch(
		state,
		_command_envelope(state, {"type": "RESOLVE_CHOICE", "choice_id": state.effect_state["choice_id"], "card_instance_id": str(first_card_id), "skip": false}, "cmd-boss-multi-1"),
		definitions
	)
	_expect(bool(first_choice.get("ok", false)), "first boss reward selection should commit")
	if not bool(first_choice.get("ok", false)):
		return
	state = first_choice["state"] as GameStateData
	_expect(int(state.effect_state.get("selected_count", 0)) == 1, "first gain should preserve serializable pending progress")
	var middle_hash := CanonicalJson.sha256(state.to_dictionary())
	var restored := GameStateData.from_dictionary(state.to_dictionary())
	_expect(CanonicalJson.sha256(restored.to_dictionary()) == middle_hash, "multi-gain intermediate state should round-trip")
	var wrong_actor_envelope := _command_envelope(state, {"type": "RESOLVE_CHOICE", "choice_id": state.effect_state["choice_id"], "card_instance_id": str((state.effect_state.get("eligible_card_ids", []) as Array)[1]), "skip": false}, "cmd-boss-multi-wrong")
	wrong_actor_envelope["actor_id"] = "p2"
	var wrong_actor := RulesEngine.dispatch(state, wrong_actor_envelope, definitions)
	_expect(not bool(wrong_actor.get("ok", false)) and wrong_actor.get("after_hash") == middle_hash, "non-required actor must be rejected without changing multi-gain progress")
	var second_card_id := StringName((state.effect_state.get("eligible_card_ids", []) as Array)[1])
	var second_choice := RulesEngine.dispatch(
		state,
		_command_envelope(state, {"type": "RESOLVE_CHOICE", "choice_id": state.effect_state["choice_id"], "card_instance_id": str(second_card_id), "skip": false}, "cmd-boss-multi-2"),
		definitions
	)
	_expect(bool(second_choice.get("ok", false)), "second gain should complete the boss reward")
	if bool(second_choice.get("ok", false)):
		var resolved := second_choice["state"] as GameStateData
		_expect(resolved.effect_state.is_empty() and ZoneService.find_card_zone(resolved, &"card-boss-01") == &"p1:discard-pile", "boss should be claimed only after all mandatory gains")


func _test_boss_departure_replacement() -> void:
	var definitions := _load_definitions()
	var state := _baseline_state(523)
	_expect(_expose_boss(state, &"card-boss-02").is_empty(), "departure fixture should expose baphomet")
	var player := state.players[&"p1"] as PlayerStateData
	var party := state.zones[player.zone_ids[&"party"]] as ZoneData
	var recruit_id := (state.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData).card_instance_ids[0]
	var fixture_events: Array[Dictionary] = []
	PartyService.discard_party_member_with_equipment(state, player, party.card_instance_ids[0], &"fixture", fixture_events)
	ZoneService.move_card(state, recruit_id, SupplyService.RECRUIT_ROW_ID, party.zone_id, 0)
	(state.cards[recruit_id] as Dictionary)["owner_id"] = "p1"
	var equip_error := EquipmentService.apply(
		state, &"p1", {"card_instance_id": "card-p1-spirit-crystal-01", "target_card_id": str(recruit_id)}, definitions, fixture_events
	)
	_expect(equip_error.is_empty(), "departure fixture should attach equipment")
	state.phase = &"combat"
	player.turn_resources["combat"] = 30
	var before_rng := state.rng_state
	var replay_state := GameStateData.from_dictionary(state.to_dictionary())
	var envelope := _command_envelope(state, {"type": "ATTACK_TARGET", "target_card_id": "card-boss-02", "claim_optional_reward": true}, "cmd-baphomet")
	var attack := RulesEngine.dispatch(
		state, envelope, definitions
	)
	var replay := RulesEngine.dispatch(replay_state, envelope, definitions)
	_expect(bool(attack.get("ok", false)), "baphomet departure and deck rewards should resolve")
	_expect(attack.get("after_hash") == replay.get("after_hash") and attack.get("events") == replay.get("events"), "departure replacement shuffle and events should replay deterministically")
	if not bool(attack.get("ok", false)):
		return
	var resolved := attack["state"] as GameStateData
	_expect(resolved.rng_state != before_rng, "returning a non-starter should deterministically shuffle the recruit supply")
	_expect(ZoneService.find_card_zone(resolved, &"card-p1-spirit-crystal-01") == &"p1:discard-pile", "equipment should discard under replacement departure")
	_expect((resolved.cards[recruit_id] as Dictionary).get("state", {}).get("equipment_ids", []).is_empty(), "departure should clear the participant attachment link")
	_expect(not (resolved.cards[&"card-p1-spirit-crystal-01"] as Dictionary).get("state", {}).has("equipped_to"), "departure should clear the equipment reverse link")
	_expect(int((resolved.players[&"p1"] as PlayerStateData).turn_resources.get("purchase_power", 0)) == 5, "baphomet ordered reward should grant purchase power")
	var starter_state := _baseline_state(525)
	_expect(_expose_boss(starter_state, &"card-boss-02").is_empty(), "starter departure fixture should expose baphomet")
	starter_state.phase = &"combat"
	(starter_state.players[&"p1"] as PlayerStateData).turn_resources["combat"] = 30
	var starter_attack := RulesEngine.dispatch(
		starter_state,
		_command_envelope(starter_state, {"type": "ATTACK_TARGET", "target_card_id": "card-boss-02", "claim_optional_reward": true}, "cmd-baphomet-starter"),
		definitions
	)
	_expect(bool(starter_attack.get("ok", false)) and ZoneService.find_card_zone(starter_attack["state"] as GameStateData, &"card-p1-starter-adventurer-01") == &"p1:removed", "starter participant should use the declared removed destination")


func _test_boss_attachment_transitions() -> void:
	var definitions := _load_definitions()
	for spec: Array in [["card-boss-04", "base:boss/boss-04"], ["card-boss-07", "base:boss/boss-07"]]:
		var state := _baseline_state(527)
		var boss_id := StringName(spec[0])
		_expect(_expose_boss(state, boss_id).is_empty(), "attachment fixture should expose %s" % spec[1])
		var reveal_events: Array[Dictionary] = []
		var reveal_error := BossService._apply_reveal_rules(state, boss_id, definitions, reveal_events)
		_expect(reveal_error.is_empty(), "boss attachment reveal should resolve")
		var attachment_zone := state.zones[BossService.BOSS_ATTACHMENT_ID] as ZoneData
		_expect(attachment_zone.card_instance_ids.size() == 1, "boss should hold one physical public attachment")
		if attachment_zone.card_instance_ids.is_empty():
			continue
		var attachment_id := attachment_zone.card_instance_ids[0]
		_expect(StringName((state.cards[attachment_id] as Dictionary).get("state", {}).get("attached_to", "")) == boss_id, "boss attachment must be bidirectional")
		_expect(InvariantService.validate(state).is_empty(), "attached boss state should satisfy zone uniqueness")
		var attached_hash := CanonicalJson.sha256(state.to_dictionary())
		_expect(CanonicalJson.sha256(GameStateData.from_dictionary(state.to_dictionary()).to_dictionary()) == attached_hash, "boss attachment links should survive snapshot-shaped round trip")
		state.phase = &"combat"
		(state.players[&"p1"] as PlayerStateData).turn_resources["combat"] = 40
		var attachment_definition := definitions[StringName((state.cards[attachment_id] as Dictionary).get("definition_id", ""))] as CardDefinition
		var boss_definition := definitions[StringName((state.cards[boss_id] as Dictionary).get("definition_id", ""))] as CardDefinition
		var attachment_preview := CombatService.preview_attack(state, &"p1", boss_id, definitions)
		_expect(int(attachment_preview.get("requirement", -1)) == int(boss_definition.combat) + int(attachment_definition.combat), "attached card combat should contribute through the shared evaluator")
		var attack := RulesEngine.dispatch(
			state,
			_command_envelope(state, {"type": "ATTACK_TARGET", "target_card_id": str(boss_id), "claim_optional_reward": true}, "cmd-attachment-%s" % spec[1]),
			definitions
		)
		_expect(bool(attack.get("ok", false)), "attached boss should resolve through shared combat")
		if not bool(attack.get("ok", false)):
			continue
		var resolved := attack["state"] as GameStateData
		_expect((resolved.zones[BossService.BOSS_ATTACHMENT_ID] as ZoneData).card_instance_ids.is_empty(), "defeat should clear the attachment zone")
		_expect(not (resolved.cards[attachment_id] as Dictionary).get("state", {}).has("attached_to"), "defeat should clear the reverse attachment link")
		var expected_zone := &"p1:discard-pile" if boss_id == &"card-boss-07" else BossService.BOSS_REMOVED_ID
		if boss_id == &"card-boss-04" and &"cycle_anchor" in attachment_definition.tags:
			expected_zone = SupplyService.MONSTER_CYCLE_ID
		_expect(ZoneService.find_card_zone(resolved, attachment_id) == expected_zone, "attachment should use its declared defeat destination")


func _test_lich_success_and_failure() -> void:
	var definitions := _load_definitions()
	var failed_state := _baseline_state(529)
	_expect(_expose_boss(failed_state, &"card-boss-03").is_empty(), "lich failure fixture should expose lich")
	failed_state.phase = &"combat"
	(failed_state.players[&"p1"] as PlayerStateData).turn_resources["combat"] = 30
	var party_before := (failed_state.zones[&"p1:party"] as ZoneData).card_instance_ids.size()
	var failed := RulesEngine.dispatch(
		failed_state,
		_command_envelope(failed_state, {"type": "ATTACK_TARGET", "target_card_id": "card-boss-03", "claim_optional_reward": true}, "cmd-lich-fail"),
		definitions
	)
	_expect(bool(failed.get("ok", false)), "unpayable lich attack should commit its exceptional failed-combat result")
	if bool(failed.get("ok", false)):
		var after_failure := failed["state"] as GameStateData
		_expect((after_failure.zones[&"p1:party"] as ZoneData).card_instance_ids.size() < party_before, "lich failure must retain participant departures")
		_expect(ZoneService.find_card_zone(after_failure, &"card-boss-03") == BossService.BOSS_ACTIVE_ID and int((after_failure.players[&"p1"] as PlayerStateData).turn_resources.get("purchase_power", 0)) == 0, "lich failure must leave the boss alive and grant no reward")
		_expect(_events_contain(failed.get("events", []), "boss_attack_failed"), "lich failure should emit its explicit result event")
		var departure_event_index := _event_index(failed.get("events", []), "card_moved")
		var failure_event_index := _event_index(failed.get("events", []), "boss_attack_failed")
		_expect(departure_event_index >= 0 and failure_event_index > departure_event_index, "lich failure event must follow committed participant departure")

	var state := _baseline_state(531)
	_expect(_expose_boss(state, &"card-boss-03").is_empty(), "lich success fixture should expose lich")
	var adventurer_id := (state.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData).card_instance_ids[0]
	ZoneService.move_card(state, adventurer_id, SupplyService.RECRUIT_ROW_ID, &"p1:hand")
	(state.cards[adventurer_id] as Dictionary)["owner_id"] = "p1"
	state.phase = &"combat"
	(state.players[&"p1"] as PlayerStateData).turn_resources["combat"] = 30
	var attack := RulesEngine.dispatch(
		state,
		_command_envelope(state, {"type": "ATTACK_TARGET", "target_card_id": "card-boss-03", "claim_optional_reward": true}, "cmd-lich-success"),
		definitions
	)
	_expect(bool(attack.get("ok", false)) and (attack["state"] as GameStateData).effect_state.get("op") == "pay_post_departure_cost", "payable lich attack should request a mandatory serialized cost")
	if not bool(attack.get("ok", false)):
		return
	state = attack["state"] as GameStateData
	var pending_hash := CanonicalJson.sha256(state.to_dictionary())
	var restored := GameStateData.from_dictionary(state.to_dictionary())
	_expect(CanonicalJson.sha256(restored.to_dictionary()) == pending_hash, "lich pending cost should round-trip")
	var tampered := state.clone_state()
	var tampered_completion := tampered.effect_state["boss_completion"] as Dictionary
	var tampered_effects := tampered_completion["remaining_effects"] as Array
	(tampered_effects[0] as Dictionary)["amount"] = 999
	var tampered_hash := CanonicalJson.sha256(tampered.to_dictionary())
	var tampered_result := RulesEngine.dispatch(
		tampered,
		_command_envelope(tampered, {"type": "RESOLVE_CHOICE", "choice_id": tampered.effect_state["choice_id"], "card_instance_id": str(adventurer_id), "skip": false}, "cmd-lich-tampered"),
		definitions
	)
	_expect(not bool(tampered_result.get("ok", false)) and tampered_result.get("after_hash") == tampered_hash, "tampered boss continuation must fail atomically")
	var pay := RulesEngine.dispatch(
		state,
		_command_envelope(state, {"type": "RESOLVE_CHOICE", "choice_id": state.effect_state["choice_id"], "card_instance_id": str(adventurer_id), "skip": false}, "cmd-lich-pay"),
		definitions
	)
	_expect(bool(pay.get("ok", false)), "lich cost selection should resume ordered rewards")
	if not bool(pay.get("ok", false)):
		return
	state = pay["state"] as GameStateData
	_expect(state.effect_state.get("op") == "choose_remove_card" and ZoneService.find_card_zone(state, &"card-boss-03") == BossService.BOSS_ACTIVE_ID, "lich optional removal should remain pending before boss claim")
	var finish := RulesEngine.dispatch(
		state,
		_command_envelope(state, {"type": "RESOLVE_CHOICE", "choice_id": state.effect_state["choice_id"], "card_instance_id": "", "skip": true}, "cmd-lich-finish"),
		definitions
	)
	_expect(bool(finish.get("ok", false)) and ZoneService.find_card_zone(finish["state"] as GameStateData, &"card-boss-03") == &"p1:discard-pile", "finishing lich reward should commit the boss defeat")
	var choice_event_index := _event_index(finish.get("events", []), "choice_resolved")
	var defeat_event_index := _event_index(finish.get("events", []), "boss_defeated")
	_expect(choice_event_index >= 0 and defeat_event_index > choice_event_index, "lich reward completion must precede the boss defeat event")


func _test_combat_preview_and_reward() -> void:
	var definitions := _load_definitions()
	var state := _baseline_state(221)
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
	var state := _baseline_state(225)
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
	var rabbit_state := _baseline_state(226)
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

	var slime_state := _baseline_state(232)
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


func _test_mimic_dice_reward() -> void:
	var definitions := _load_definitions()
	var faces_seen: Dictionary = {}
	for seed_value in range(1, 500):
		var state := _baseline_state(seed_value)
		var player := state.players[&"p1"] as PlayerStateData
		player.turn_resources[&"purchase_power"] = 0
		var events: Array[Dictionary] = []
		var effect := {
			"op": "roll_resource_reward",
			"die_sides": 6,
			"resource": "purchase_power",
			"conversion": "ceil_divide",
			"divisor": 2,
			"source_card_instance_id": "card-monster-mimic-01",
		}
		var error := EffectResolver.resolve(state, &"p1", [effect], events, definitions)
		_expect(error.is_empty(), "generic dice reward should resolve")
		if not error.is_empty():
			return
		var roll := int(events[0].get("die_result", 0))
		faces_seen[roll] = true
		_expect(
			int(player.turn_resources.get("purchase_power", 0)) == (roll + 1) / 2,
			"each d6 face should map to ceiling-half purchase power"
		)
		_expect(
			events[0].get("die_sides") == 6 and events[0].get("resource") == "purchase_power" \
					and events[0].get("source_card_instance_id") == "card-monster-mimic-01" \
					and events[0].get("actor_id") == "p1",
			"dice event should record sides, resource, source card, and actor"
		)
		if faces_seen.size() == 6:
			break
	_expect(faces_seen.size() == 6, "dice reward coverage should observe all six faces")

	var state := _baseline_state(307)
	var expose_error := _expose_monster(
		state, &"card-monster-mimic-01", &"card-monster-rabbit-demon-01"
	)
	_expect(expose_error.is_empty(), "mimic fixture should expose the target")
	var phase_result := RulesEngine.dispatch(
		state, _end_phase_envelope(state, "cmd-mimic-combat"), definitions
	)
	if not bool(phase_result.get("ok", false)):
		_expect(false, "mimic fixture should enter combat")
		return
	state = phase_result["state"] as GameStateData
	var preview := CombatService.preview_attack(state, &"p1", &"card-monster-mimic-01", definitions)
	_expect(
		"1／2 → 1、3／4 → 2、5／6 → 3 購買力" in str(preview.get("reward_summary", "")),
		"mimic preview should show the complete dice conversion"
	)
	var rng_before := state.rng_state
	var before_hash := CanonicalJson.sha256(state.to_dictionary())
	var invalid := RulesEngine.dispatch(
		state,
		_command_envelope(state, {
			"type": "ATTACK_TARGET",
			"target_card_id": "card-monster-mimic-01",
			"claim_optional_reward": false,
		}, "cmd-mimic-invalid"),
		definitions
	)
	_expect(str(invalid.get("error", "")) == "reward_not_optional", "mimic reward must not be skippable")
	_expect(
		state.rng_state == rng_before and CanonicalJson.sha256(state.to_dictionary()) == before_hash,
		"failed mimic dispatch must not consume RNG or mutate state"
	)
	var command := _command_envelope(state, {
		"type": "ATTACK_TARGET",
		"target_card_id": "card-monster-mimic-01",
		"claim_optional_reward": true,
	}, "cmd-mimic-attack")
	var result := RulesEngine.dispatch(state, command, definitions)
	var repeated := RulesEngine.dispatch(state.clone_state(), command, definitions)
	_expect(bool(result.get("ok", false)), "mimic attack should resolve immediately")
	_expect(result.get("after_hash") == repeated.get("after_hash"), "mimic attack hash should be deterministic")
	if not bool(result.get("ok", false)):
		return
	var resolved := result["state"] as GameStateData
	_expect(resolved.rng_state != rng_before, "mimic attack should advance serialized RNG state")
	var departure_index := -1
	var roll_index := -1
	var reward_index := -1
	var claim_index := -1
	var defeated_index := -1
	for index in (result.get("events", []) as Array).size():
		var event := (result.get("events", []) as Array)[index] as Dictionary
		if event.get("reason") == "combat_departure" and departure_index < 0:
			departure_index = index
		elif event.get("type") == "die_rolled":
			roll_index = index
		elif event.get("type") == "effect_resolved" and event.get("op") == "roll_resource_reward":
			reward_index = index
		elif event.get("reason") == "defeated_monster_claimed":
			claim_index = index
		elif event.get("type") == "enemy_defeated":
			defeated_index = index
	_expect(
		departure_index < roll_index and roll_index < reward_index \
				and reward_index < claim_index and claim_index < defeated_index,
		"mimic events should order departure, roll, reward, claim, and defeat"
	)
	var encoded := SnapshotCodec.encode(resolved, "content-mimic", "rules-mimic")
	var decoded := SnapshotCodec.decode(encoded, "content-mimic", "rules-mimic")
	_expect(bool(decoded.get("ok", false)), "post-mimic RNG state should round-trip")
	if bool(decoded.get("ok", false)):
		var restored := decoded["state"] as GameStateData
		var next_events: Array[Dictionary] = []
		var restored_events: Array[Dictionary] = []
		var next_rng_before := resolved.rng_state
		EffectResolver.resolve(resolved, &"p1", [(definitions[&"base:monster/monster-02"] as CardDefinition).effects[0]], next_events, definitions)
		EffectResolver.resolve(restored, &"p1", [(definitions[&"base:monster/monster-02"] as CardDefinition).effects[0]], restored_events, definitions)
		_expect(next_events == restored_events, "snapshot RNG continuation should reproduce the next dice event")
		_expect(resolved.rng_state != next_rng_before, "consecutive dice rewards should deterministically advance RNG")


func _test_lamia_resource_draft() -> void:
	var definitions := _load_definitions()
	var state := _baseline_state(311)
	var expose_error := _expose_monster(
		state, &"card-monster-lamia-01", &"card-monster-rabbit-demon-01"
	)
	_expect(expose_error.is_empty(), "lamia fixture should expose the target")
	var phase_result := RulesEngine.dispatch(
		state, _end_phase_envelope(state, "cmd-lamia-combat"), definitions
	)
	if not bool(phase_result.get("ok", false)):
		_expect(false, "lamia fixture should enter combat")
		return
	state = phase_result["state"] as GameStateData
	var attack_command := _command_envelope(state, {
		"type": "ATTACK_TARGET",
		"target_card_id": "card-monster-lamia-01",
		"claim_optional_reward": true,
	}, "cmd-lamia-attack")
	var attack := RulesEngine.dispatch(state, attack_command, definitions)
	var repeated_attack := RulesEngine.dispatch(state.clone_state(), attack_command, definitions)
	_expect(bool(attack.get("ok", false)), "lamia attack should create a resource draft")
	_expect(attack.get("after_hash") == repeated_attack.get("after_hash"), "initial lamia draft hash should be deterministic")
	if not bool(attack.get("ok", false)):
		return
	var pending := attack["state"] as GameStateData
	var choice := pending.effect_state
	var departure_index := -1
	var first_reveal_index := -1
	var request_index := -1
	var claim_index := -1
	var defeated_index := -1
	for index in (attack.get("events", []) as Array).size():
		var event := (attack.get("events", []) as Array)[index] as Dictionary
		if event.get("reason") == "combat_departure" and departure_index < 0:
			departure_index = index
		elif event.get("reason") == "resource_draft_reveal" and first_reveal_index < 0:
			first_reveal_index = index
		elif event.get("type") == "choice_requested":
			request_index = index
		elif event.get("reason") == "defeated_monster_claimed":
			claim_index = index
		elif event.get("type") == "enemy_defeated":
			defeated_index = index
	_expect(
		departure_index < first_reveal_index and first_reveal_index < request_index \
				and request_index < claim_index and claim_index < defeated_index,
		"lamia attack events should order departure, reveal, choice, claim, and defeat"
	)
	_expect(pending.active_player_id == &"p1", "lamia draft must preserve the active player")
	_expect(choice.get("required_actor_id") == "p1", "defeater should select first")
	_expect(choice.get("selection_order") == ["p1", "p2"], "lamia draft should follow leftward turn order")
	var draft_row := pending.zones[SupplyService.RESOURCE_DRAFT_ROW_ID] as ZoneData
	_expect(draft_row.card_instance_ids.size() == 2, "two players should reveal two resource cards")
	_expect(
		(choice.get("remaining_card_ids", []) as Array).size() == 2 \
				and (choice.get("eligible_card_ids", []) as Array).size() == 2,
		"lamia pending choice should lock and expose both candidates"
	)
	_expect(RulesEngine.get_legal_commands(pending, &"p2", definitions).is_empty(), "non-required player should have no legal commands")
	var p1_commands := RulesEngine.get_legal_commands(pending, &"p1", definitions)
	_expect(p1_commands.size() == 2, "required player should choose either revealed card without skip")
	var has_skip := false
	for command: Dictionary in p1_commands:
		has_skip = has_skip or bool(command.get("skip", false))
	_expect(not has_skip, "lamia draft must never expose a skip command")
	var forced_skip := _command_envelope(pending, {
		"type": "RESOLVE_CHOICE",
		"choice_id": str(choice.get("choice_id", "")),
		"card_instance_id": "",
		"skip": true,
	}, "cmd-lamia-forced-skip")
	var forced_skip_result := RulesEngine.dispatch(pending, forced_skip, definitions)
	_expect(str(forced_skip_result.get("error", "")) == "choice_required", "lamia draft must reject forged skip commands")
	var pending_hash := CanonicalJson.sha256(pending.to_dictionary())
	var pending_snapshot := SnapshotCodec.encode(pending, "content-lamia", "rules-lamia")
	_expect(
		bool(SnapshotCodec.decode(pending_snapshot, "content-lamia", "rules-lamia").get("ok", false)),
		"new lamia draft should round-trip"
	)
	var moved_candidate := pending.clone_state()
	var moved_id := StringName((moved_candidate.effect_state.get("remaining_card_ids", []) as Array)[0])
	ZoneService.move_card(
		moved_candidate, moved_id, SupplyService.RESOURCE_DRAFT_ROW_ID, &"p1:discard-pile"
	)
	(moved_candidate.cards[moved_id] as Dictionary)["owner_id"] = "p1"
	var moved_hash := CanonicalJson.sha256(moved_candidate.to_dictionary())
	var moved_command := (p1_commands[0] as Dictionary).duplicate(true)
	moved_command["card_instance_id"] = str(moved_id)
	var moved_result := RulesEngine.dispatch(
		moved_candidate,
		_command_envelope(moved_candidate, moved_command, "cmd-lamia-moved"),
		definitions
	)
	_expect(not bool(moved_result.get("ok", true)), "moved lamia candidate must be rejected")
	_expect(CanonicalJson.sha256(moved_candidate.to_dictionary()) == moved_hash, "moved candidate rejection must be atomic")
	var wrong_source := pending.clone_state()
	wrong_source.effect_state["choice_zone_id"] = str(SupplyService.SHOP_ROW_ID)
	var wrong_source_hash := CanonicalJson.sha256(wrong_source.to_dictionary())
	var wrong_source_result := RulesEngine.dispatch(
		wrong_source,
		_command_envelope(wrong_source, p1_commands[0], "cmd-lamia-wrong-source"),
		definitions
	)
	_expect(not bool(wrong_source_result.get("ok", true)), "tampered lamia source must be rejected")
	_expect(CanonicalJson.sha256(wrong_source.to_dictionary()) == wrong_source_hash, "wrong source rejection must be atomic")
	var wrong_card_command := (p1_commands[0] as Dictionary).duplicate(true)
	wrong_card_command["card_instance_id"] = str(
		(pending.zones[SupplyService.SHOP_ROW_ID] as ZoneData).card_instance_ids[0]
	)
	var wrong_card_result := RulesEngine.dispatch(
		pending,
		_command_envelope(pending, wrong_card_command, "cmd-lamia-wrong-card"),
		definitions
	)
	_expect(str(wrong_card_result.get("error", "")) == "ineligible_choice_card", "card outside draft row must be rejected")
	_expect(CanonicalJson.sha256(pending.to_dictionary()) == pending_hash, "wrong-card rejection must be atomic")
	var wrong_owner := pending.clone_state()
	var owner_tamper_id := StringName((wrong_owner.effect_state.get("remaining_card_ids", []) as Array)[0])
	(wrong_owner.cards[owner_tamper_id] as Dictionary)["owner_id"] = "p2"
	var wrong_owner_hash := CanonicalJson.sha256(wrong_owner.to_dictionary())
	var wrong_owner_result := RulesEngine.dispatch(
		wrong_owner,
		_command_envelope(wrong_owner, p1_commands[0], "cmd-lamia-wrong-owner"),
		definitions
	)
	_expect(not bool(wrong_owner_result.get("ok", true)), "owned card in draft row must be rejected")
	_expect(CanonicalJson.sha256(wrong_owner.to_dictionary()) == wrong_owner_hash, "ownership tamper rejection must be atomic")
	var wrong_actor_command := (p1_commands[0] as Dictionary).duplicate(true)
	var wrong_actor_envelope := _command_envelope(pending, wrong_actor_command, "cmd-lamia-wrong-actor")
	wrong_actor_envelope["actor_id"] = "p2"
	var wrong_actor := RulesEngine.dispatch(pending, wrong_actor_envelope, definitions)
	_expect(str(wrong_actor.get("error", "")) == "wrong_actor", "wrong lamia chooser must be rejected")
	_expect(CanonicalJson.sha256(pending.to_dictionary()) == pending_hash, "wrong lamia chooser must be atomic")
	var first_card_id := StringName(p1_commands[0].get("card_instance_id", ""))
	var first_envelope := _command_envelope(pending, p1_commands[0], "cmd-lamia-first")
	var first := RulesEngine.dispatch(pending, first_envelope, definitions)
	var repeated_first := RulesEngine.dispatch(repeated_attack["state"] as GameStateData, first_envelope, definitions)
	_expect(bool(first.get("ok", false)), "first lamia pick should commit")
	_expect(first.get("after_hash") == repeated_first.get("after_hash"), "mid-draft hash should be deterministic")
	if not bool(first.get("ok", false)):
		return
	var middle := first["state"] as GameStateData
	_expect(middle.revision == pending.revision + 1, "first lamia pick should increment revision")
	_expect(middle.active_player_id == &"p1", "active player must remain the defeater after first pick")
	_expect(middle.effect_state.get("required_actor_id") == "p2", "second player should become required actor")
	_expect(ZoneService.find_card_zone(middle, first_card_id) == &"p1:hand", "first card should enter p1 hand")
	_expect(StringName((middle.cards[first_card_id] as Dictionary).get("owner_id", "")) == &"p1", "first card owner should be p1")
	_expect(RulesEngine.get_legal_commands(middle, &"p1", definitions).is_empty(), "active but non-required player should have no commands")
	var p2_commands := RulesEngine.get_legal_commands(middle, &"p2", definitions)
	_expect(p2_commands.size() == 1, "p2 should receive only the remaining mandatory choice")
	_expect(
		RulesEngine.get_legal_commands(middle, &"p2", definitions)[0].get("actor_id") == "p2",
		"legal draft command should be assigned to its required actor"
	)
	var middle_snapshot := SnapshotCodec.encode(middle, "content-lamia-mid", "rules-lamia")
	_expect(
		bool(SnapshotCodec.decode(middle_snapshot, "content-lamia-mid", "rules-lamia").get("ok", false)),
		"lamia draft after one pick should round-trip"
	)
	var illegal_end := _command_envelope(middle, {"type": "END_PHASE"}, "cmd-lamia-illegal-end")
	illegal_end["actor_id"] = "p2"
	var middle_hash := CanonicalJson.sha256(middle.to_dictionary())
	var illegal_end_result := RulesEngine.dispatch(middle, illegal_end, definitions)
	_expect(str(illegal_end_result.get("error", "")) == "effects_pending", "assigned chooser cannot execute normal commands")
	_expect(CanonicalJson.sha256(middle.to_dictionary()) == middle_hash, "illegal pending command must be atomic")
	var duplicate_command := (p2_commands[0] as Dictionary).duplicate(true)
	duplicate_command["card_instance_id"] = str(first_card_id)
	var duplicate_envelope := _command_envelope(middle, duplicate_command, "cmd-lamia-repeat-card")
	duplicate_envelope["actor_id"] = "p2"
	var duplicate_result := RulesEngine.dispatch(middle, duplicate_envelope, definitions)
	_expect(str(duplicate_result.get("error", "")) == "choice_card_already_selected", "draft cannot select an already gained card")
	_expect(CanonicalJson.sha256(middle.to_dictionary()) == middle_hash, "repeat-card rejection must preserve mid-draft state")
	var second_card_id := StringName(p2_commands[0].get("card_instance_id", ""))
	var second_envelope := _command_envelope(middle, p2_commands[0], "cmd-lamia-second")
	second_envelope["actor_id"] = "p2"
	var second := RulesEngine.dispatch(middle, second_envelope, definitions)
	var repeated_second := RulesEngine.dispatch(repeated_first["state"] as GameStateData, second_envelope, definitions)
	_expect(bool(second.get("ok", false)), "second lamia pick should complete the draft")
	_expect(second.get("after_hash") == repeated_second.get("after_hash"), "completed draft hash should be deterministic")
	if bool(second.get("ok", false)):
		var resolved := second["state"] as GameStateData
		_expect(resolved.effect_state.is_empty(), "last draft pick should clear pending choice")
		_expect((resolved.zones[SupplyService.RESOURCE_DRAFT_ROW_ID] as ZoneData).card_instance_ids.is_empty(), "last pick should empty draft row")
		_expect(ZoneService.find_card_zone(resolved, second_card_id) == &"p2:hand", "second card should enter p2 hand")
		_expect(StringName((resolved.cards[second_card_id] as Dictionary).get("owner_id", "")) == &"p2", "second card owner should be p2")
		_expect(_commands_contain(RulesEngine.get_legal_commands(resolved, &"p1", definitions), "END_PHASE"), "normal active-player commands should resume")
		var progressed_index := -1
		for index in (first.get("events", []) as Array).size():
			if ((first.get("events", []) as Array)[index] as Dictionary).get("type") == "choice_progressed":
				progressed_index = index
		_expect(progressed_index > 0, "first lamia pick should move the card before announcing next chooser")
		var resolved_index := -1
		var effect_index := -1
		for index in (second.get("events", []) as Array).size():
			var event := (second.get("events", []) as Array)[index] as Dictionary
			if event.get("type") == "choice_resolved":
				resolved_index = index
			elif event.get("type") == "effect_resolved":
				effect_index = index
		_expect(resolved_index > 0 and resolved_index < effect_index, "final lamia pick should move, resolve choice, then complete effect")

	var one_card := _baseline_state(313)
	var deck := one_card.zones[SupplyService.SHOP_DECK_ID] as ZoneData
	while deck.card_instance_ids.size() > 1:
		var card_id: StringName = deck.card_instance_ids.back()
		ZoneService.move_card(one_card, card_id, SupplyService.SHOP_DECK_ID, &"p1:discard-pile")
		(one_card.cards[card_id] as Dictionary)["owner_id"] = "p1"
	var one_events: Array[Dictionary] = []
	var draft_effect := (definitions[&"base:monster/monster-05"] as CardDefinition).effects[0]
	var one_error := EffectResolver.resolve(one_card, &"p1", [draft_effect], one_events, definitions)
	_expect(one_error.is_empty() and (one_card.effect_state.get("eligible_card_ids", []) as Array).size() == 1, "short supply should reveal only its actual final card")
	_expect(InvariantService.validate(one_card).is_empty(), "one-card lamia draft should satisfy invariants")
	var empty_state := _baseline_state(317)
	deck = empty_state.zones[SupplyService.SHOP_DECK_ID] as ZoneData
	while not deck.card_instance_ids.is_empty():
		var card_id: StringName = deck.card_instance_ids.back()
		ZoneService.move_card(empty_state, card_id, SupplyService.SHOP_DECK_ID, &"p1:discard-pile")
		(empty_state.cards[card_id] as Dictionary)["owner_id"] = "p1"
	var empty_events: Array[Dictionary] = []
	var empty_error := EffectResolver.resolve(empty_state, &"p1", [draft_effect], empty_events, definitions)
	_expect(empty_error.is_empty() and empty_state.effect_state.is_empty(), "empty supply should complete without pending choice")
	_expect(_events_contain(empty_events, "effect_resolved"), "empty supply should emit effect completion")
	var p2_start := _baseline_state(319)
	p2_start.active_player_id = &"p2"
	var p2_events: Array[Dictionary] = []
	var p2_error := EffectResolver.resolve(p2_start, &"p2", [draft_effect], p2_events, definitions)
	_expect(p2_error.is_empty(), "lamia draft should support a non-starting-player defeater")
	_expect(
		p2_start.effect_state.get("selection_order") == ["p2", "p1"] \
				and p2_start.effect_state.get("required_actor_id") == "p2",
		"draft order should rotate from the actual defeater"
	)


func _test_automaton_archer_pending_choice() -> void:
	var definitions := _load_definitions()
	var state := _baseline_state(235)
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

	var skip_state := _baseline_state(236)
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
	var no_candidate := _baseline_state(237)
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

	var state := _baseline_state(239)
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
		pending.effect_state.get("source_zone_keys", []) == ["discard_pile"] \
				and StringName((pending.effect_state.get("source_zone_ids", {}) as Dictionary) \
				.get("discard_pile", "")) == player.zone_ids[&"discard_pile"],
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


func _test_multi_zone_removal_monsters() -> void:
	var definitions := _load_definitions()
	var lizard_id := &"card-monster-lizardfolk-mage-01"
	var lizard_state := _baseline_state(245)
	var equip_result := RulesEngine.dispatch(
		lizard_state,
		_equip_item_envelope(
			lizard_state,
			&"card-p1-spirit-crystal-01",
			&"card-p1-starter-adventurer-05",
			"cmd-lizard-equip"
		),
		definitions
	)
	_expect(bool(equip_result.get("ok", false)), "lizard fixture should equip a remaining party member")
	if not bool(equip_result.get("ok", false)):
		return
	lizard_state = equip_result["state"] as GameStateData
	for move_spec: Array in [
		[&"card-p1-summoning-stone-01", &"p1:draw-pile"],
		[&"card-p1-summoning-stone-02", &"p1:play-area"],
		[&"card-p1-summoning-stone-03", &"p1:removed"],
	]:
		var move_result := ZoneService.move_card(
			lizard_state,
			StringName(move_spec[0]),
			&"p1:hand",
			StringName(move_spec[1])
		)
		_expect(bool(move_result.get("ok", false)), "lizard wrong-zone fixture should move a card")
	var expose_error := _expose_monster(
		lizard_state, lizard_id, &"card-monster-rabbit-demon-01"
	)
	_expect(expose_error.is_empty(), "lizard fixture should expose the target")
	var lizard_player := lizard_state.players[&"p1"] as PlayerStateData
	lizard_player.turn_resources[&"combat"] = 6
	var phase_result := RulesEngine.dispatch(
		lizard_state,
		_end_phase_envelope(lizard_state, "cmd-lizard-combat-phase"),
		definitions
	)
	_expect(bool(phase_result.get("ok", false)), "lizard fixture should enter combat")
	if not bool(phase_result.get("ok", false)):
		return
	lizard_state = phase_result["state"] as GameStateData
	var lizard_preview := CombatService.preview_attack(lizard_state, &"p1", lizard_id, definitions)
	_expect(
		bool(lizard_preview.get("legal", false)) \
				and "可從手牌、隊伍或棄牌堆移除 1 張" \
				in str(lizard_preview.get("reward_summary", "")),
		"lizard preview should describe all removal sources"
	)
	var lizard_attack_envelope := _command_envelope(lizard_state, {
		"type": "ATTACK_TARGET",
		"target_card_id": str(lizard_id),
		"claim_optional_reward": true,
	}, "cmd-attack-lizard")
	var lizard_attack := RulesEngine.dispatch(lizard_state, lizard_attack_envelope, definitions)
	var repeated_lizard_attack := RulesEngine.dispatch(
		lizard_state.clone_state(), lizard_attack_envelope, definitions
	)
	_expect(bool(lizard_attack.get("ok", false)), "lizard attack should create a pending choice")
	_expect(
		lizard_attack.get("after_hash") == repeated_lizard_attack.get("after_hash"),
		"lizard pending hash should be deterministic"
	)
	if not bool(lizard_attack.get("ok", false)):
		return
	var lizard_pending := lizard_attack["state"] as GameStateData
	var lizard_choice := lizard_pending.effect_state
	var lizard_sources := lizard_choice.get("eligible_card_sources", {}) as Dictionary
	var source_counts := {"hand": 0, "party": 0, "discard_pile": 0}
	for raw_card_id: Variant in lizard_choice.get("eligible_card_ids", []):
		var card_id := str(raw_card_id)
		var source_record := lizard_sources.get(card_id, {}) as Dictionary
		var source_key := str(source_record.get("zone_key", ""))
		source_counts[source_key] = int(source_counts.get(source_key, 0)) + 1
	_expect(
		lizard_choice.get("source_zone_keys", []) == ["hand", "party", "discard_pile"] \
				and (lizard_choice.get("source_zone_ids", {}) as Dictionary) == {
					"hand": "p1:hand",
					"party": "p1:party",
					"discard_pile": "p1:discard-pile",
				} \
				and int(source_counts.hand) == 1 \
				and int(source_counts.party) == 4 \
				and int(source_counts.discard_pile) == 1,
		"lizard pending should lock hand, remaining party, and departed discard candidates"
	)
	_expect(
		lizard_sources.get("card-p1-starter-adventurer-01", {}).get("zone_key") \
				== "discard_pile",
		"combat-departed adventurer should be a discard candidate"
	)
	_expect(
		str(lizard_id) not in (lizard_choice.get("eligible_card_ids", []) as Array),
		"defeated lizard must not be captured as its own reward candidate"
	)
	var lizard_attack_events := lizard_attack.get("events", []) as Array
	var departure_index := -1
	var request_index := -1
	var claim_index := -1
	for event_index in lizard_attack_events.size():
		var event := lizard_attack_events[event_index] as Dictionary
		if event.get("reason") == "combat_departure" and departure_index < 0:
			departure_index = event_index
		elif event.get("type") == "choice_requested":
			request_index = event_index
		elif event.get("reason") == "defeated_monster_claimed":
			claim_index = event_index
	_expect(
		departure_index >= 0 and departure_index < request_index and request_index < claim_index,
		"multi-source candidates must lock after combat departure and before monster claim"
	)
	var initial_snapshot := SnapshotCodec.encode(lizard_pending, "content-lizard", "rules-lizard")
	var initial_decoded := SnapshotCodec.decode(initial_snapshot, "content-lizard", "rules-lizard")
	_expect(
		bool(initial_decoded.get("ok", false)) \
				and CanonicalJson.stringify((initial_decoded["state"] as GameStateData).effect_state) \
				== CanonicalJson.stringify(lizard_choice),
		"initial multi-source pending state should round-trip"
	)
	var wrong_zone_ids: Array[StringName] = [
		&"card-p2-summoning-stone-01",
		&"card-p1-summoning-stone-01",
		&"card-p1-summoning-stone-02",
		&"card-p1-summoning-stone-03",
		&"card-p1-spirit-crystal-01",
		(lizard_pending.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData).card_instance_ids[0],
		(lizard_pending.zones[SupplyService.RECRUIT_DECK_ID] as ZoneData).card_instance_ids[0],
		&"card-monster-skeleton-01",
	]
	for wrong_index in wrong_zone_ids.size():
		var pending_hash := CanonicalJson.sha256(lizard_pending.to_dictionary())
		var wrong_result := RulesEngine.dispatch(
			lizard_pending,
			_command_envelope(lizard_pending, {
				"type": "RESOLVE_CHOICE",
				"choice_id": str(lizard_choice.get("choice_id", "")),
				"card_instance_id": str(wrong_zone_ids[wrong_index]),
				"skip": false,
			}, "cmd-lizard-wrong-zone-%d" % wrong_index),
			definitions
		)
		_expect(
			str(wrong_result.get("error", "")) == "ineligible_choice_card" \
					and wrong_result.get("after_hash") == pending_hash,
			"multi-source removal must reject opponent and every disallowed zone atomically"
		)
	var party_selected := &"card-p1-starter-adventurer-05"
	var lizard_resolve_envelope := _command_envelope(lizard_pending, {
		"type": "RESOLVE_CHOICE",
		"choice_id": str(lizard_choice.get("choice_id", "")),
		"card_instance_id": str(party_selected),
		"skip": false,
	}, "cmd-lizard-remove-party")
	var lizard_resolve := RulesEngine.dispatch(
		lizard_pending, lizard_resolve_envelope, definitions
	)
	var repeated_lizard_resolve := RulesEngine.dispatch(
		repeated_lizard_attack["state"] as GameStateData,
		lizard_resolve_envelope,
		definitions
	)
	_expect(bool(lizard_resolve.get("ok", false)), "lizard should remove one party adventurer")
	_expect(
		lizard_resolve.get("after_hash") == repeated_lizard_resolve.get("after_hash"),
		"lizard resolved hash should be deterministic"
	)
	if bool(lizard_resolve.get("ok", false)):
		var lizard_resolved := lizard_resolve["state"] as GameStateData
		var removed_adventurer := lizard_resolved.cards[party_selected] as Dictionary
		var departed_equipment := lizard_resolved.cards[&"card-p1-spirit-crystal-01"] as Dictionary
		_expect(
			ZoneService.find_card_zone(lizard_resolved, party_selected) == &"p1:removed" \
					and ZoneService.find_card_zone(
						lizard_resolved, &"card-p1-spirit-crystal-01"
					) == &"p1:discard-pile" \
					and (removed_adventurer.get("state", {}) as Dictionary) \
					.get("equipment_ids", []).is_empty() \
					and not (departed_equipment.get("state", {}) as Dictionary).has("equipped_to"),
			"party removal should exile the adventurer, discard equipment, and clear attachments"
		)
		_expect(lizard_resolved.effect_state.is_empty(), "lizard should auto-complete after one card")

	var lizard_skip_command: Dictionary = {}
	for command: Dictionary in RulesEngine.get_legal_commands(lizard_pending, &"p1", definitions):
		if bool(command.get("skip", false)):
			lizard_skip_command = command
			break
	var lizard_skip := RulesEngine.dispatch(
		lizard_pending,
		_command_envelope(lizard_pending, lizard_skip_command, "cmd-lizard-skip"),
		definitions
	)
	_expect(
		bool(lizard_skip.get("ok", false)) \
				and (lizard_skip["state"] as GameStateData).effect_state.is_empty(),
		"lizard removal should allow skipping"
	)
	var no_candidate := _baseline_state(246)
	var no_player := no_candidate.players[&"p1"] as PlayerStateData
	for source_key: StringName in [&"hand", &"party", &"discard_pile"]:
		var source := no_candidate.zones[no_player.zone_ids[source_key]] as ZoneData
		for card_id: StringName in source.card_instance_ids.duplicate():
			ZoneService.move_card(
				no_candidate, card_id, source.zone_id, no_player.zone_ids[&"removed"]
			)
	var no_candidate_events: Array[Dictionary] = []
	var no_candidate_error := EffectResolver.resolve(
		no_candidate,
		&"p1",
		[(definitions[&"base:monster/monster-03"] as CardDefinition).effects[0]],
		no_candidate_events,
		definitions
	)
	_expect(
		no_candidate_error.is_empty() and no_candidate.effect_state.is_empty() \
				and no_candidate_events.size() == 1 \
				and no_candidate_events[0].get("reason") == "no_eligible_candidates",
		"lizard with no legal source candidates should complete immediately"
	)

	var golem_id := &"card-monster-golem-01"
	var golem_state := _baseline_state(247)
	_expose_monster(golem_state, golem_id, &"card-monster-rabbit-demon-01")
	(golem_state.players[&"p1"] as PlayerStateData).turn_resources[&"combat"] = 6
	phase_result = RulesEngine.dispatch(
		golem_state,
		_end_phase_envelope(golem_state, "cmd-golem-combat-phase"),
		definitions
	)
	golem_state = phase_result["state"] as GameStateData
	var golem_preview := CombatService.preview_attack(golem_state, &"p1", golem_id, definitions)
	_expect(
		bool(golem_preview.get("legal", false)) \
				and "可從手牌、隊伍或棄牌堆移除最多 2 張" \
				in str(golem_preview.get("reward_summary", "")),
		"golem preview should describe its two-card multi-source removal"
	)
	var golem_attack_envelope := _command_envelope(golem_state, {
		"type": "ATTACK_TARGET",
		"target_card_id": str(golem_id),
		"claim_optional_reward": true,
	}, "cmd-attack-golem")
	var golem_attack := RulesEngine.dispatch(golem_state, golem_attack_envelope, definitions)
	var repeated_golem_attack := RulesEngine.dispatch(
		golem_state.clone_state(), golem_attack_envelope, definitions
	)
	_expect(bool(golem_attack.get("ok", false)), "golem attack should create a two-card choice")
	_expect(
		golem_attack.get("after_hash") == repeated_golem_attack.get("after_hash"),
		"golem initial pending hash should be deterministic"
	)
	if not bool(golem_attack.get("ok", false)):
		return
	var golem_pending := golem_attack["state"] as GameStateData
	var golem_choice_id := str(golem_pending.effect_state.get("choice_id", ""))
	_expect(
		int(golem_pending.effect_state.get("min_selections", -1)) == 0 \
				and int(golem_pending.effect_state.get("max_selections", -1)) == 2 \
				and int(golem_pending.effect_state.get("selected_count", -1)) == 0,
		"golem pending should serialize 0..2 selection progress"
	)
	_expect(
		str(golem_id) not in (golem_pending.effect_state.get("eligible_card_ids", []) as Array),
		"defeated golem must not be captured as its own reward candidate"
	)
	var golem_initial_snapshot := SnapshotCodec.encode(
		golem_pending, "content-golem", "rules-golem"
	)
	_expect(
		bool(SnapshotCodec.decode(
			golem_initial_snapshot, "content-golem", "rules-golem"
		).get("ok", false)),
		"golem initial pending state should round-trip"
	)
	var zero_command: Dictionary = {}
	for command: Dictionary in RulesEngine.get_legal_commands(golem_pending, &"p1", definitions):
		if bool(command.get("skip", false)):
			zero_command = command
			break
	var zero_result := RulesEngine.dispatch(
		golem_pending,
		_command_envelope(golem_pending, zero_command, "cmd-golem-zero"),
		definitions
	)
	_expect(
		bool(zero_result.get("ok", false)) \
				and (zero_result["state"] as GameStateData).effect_state.is_empty() \
				and (zero_result.get("events", []) as Array).size() == 2,
		"golem should allow completing with zero removals"
	)
	var first_id := StringName(
		(golem_pending.effect_state.get("eligible_card_ids", []) as Array)[0]
	)
	var first_envelope := _command_envelope(golem_pending, {
		"type": "RESOLVE_CHOICE",
		"choice_id": golem_choice_id,
		"card_instance_id": str(first_id),
		"skip": false,
	}, "cmd-golem-first")
	var first_result := RulesEngine.dispatch(golem_pending, first_envelope, definitions)
	var repeated_first := RulesEngine.dispatch(
		repeated_golem_attack["state"] as GameStateData, first_envelope, definitions
	)
	_expect(bool(first_result.get("ok", false)), "golem first removal should commit")
	_expect(
		first_result.get("after_hash") == repeated_first.get("after_hash"),
		"golem intermediate hash should be deterministic"
	)
	if not bool(first_result.get("ok", false)):
		return
	var mid_state := first_result["state"] as GameStateData
	_expect(
		int(mid_state.effect_state.get("selected_count", -1)) == 1 \
				and mid_state.effect_state.get("selected_card_ids", []) == [str(first_id)] \
				and ZoneService.find_card_zone(mid_state, first_id) == &"p1:removed",
		"golem should preserve pending progress after its first removal"
	)
	var first_events := first_result.get("events", []) as Array
	_expect(
		first_events.size() == 2 \
				and (first_events[0] as Dictionary).get("reason") == "card_removed" \
				and (first_events[1] as Dictionary).get("type") == "choice_progressed",
		"golem first-step events should order removal before progress"
	)
	var mid_commands := RulesEngine.get_legal_commands(mid_state, &"p1", definitions)
	var finish_commands := 0
	for command: Dictionary in mid_commands:
		if bool(command.get("skip", false)):
			finish_commands += 1
	_expect(
		mid_commands.size() \
				== (mid_state.effect_state.get("eligible_card_ids", []) as Array).size() \
				and finish_commands == 1,
		"golem first removal should leave remaining candidates plus one finish command"
	)
	var mid_snapshot := SnapshotCodec.encode(mid_state, "content-golem", "rules-golem")
	var mid_decoded := SnapshotCodec.decode(mid_snapshot, "content-golem", "rules-golem")
	_expect(
		bool(mid_decoded.get("ok", false)) \
				and CanonicalJson.stringify((mid_decoded["state"] as GameStateData).effect_state) \
				== CanonicalJson.stringify(mid_state.effect_state),
		"golem one-selected pending state should round-trip"
	)
	var mid_hash := CanonicalJson.sha256(mid_state.to_dictionary())
	var repeated_result := RulesEngine.dispatch(
		mid_state,
		_command_envelope(mid_state, {
			"type": "RESOLVE_CHOICE",
			"choice_id": golem_choice_id,
			"card_instance_id": str(first_id),
			"skip": false,
		}, "cmd-golem-repeat"),
		definitions
	)
	_expect(
		str(repeated_result.get("error", "")) == "choice_card_already_selected" \
				and repeated_result.get("after_hash") == mid_hash,
		"golem must reject selecting the same card twice without losing first-step progress"
	)
	var remaining_id := StringName("")
	for raw_id: Variant in mid_state.effect_state.get("eligible_card_ids", []):
		if str(raw_id) != str(first_id):
			remaining_id = StringName(str(raw_id))
			break
	var moved_state := mid_state.clone_state()
	var remaining_source := (moved_state.effect_state.get(
		"eligible_card_sources", {}
	) as Dictionary).get(str(remaining_id), {}) as Dictionary
	var move_tamper := ZoneService.move_card(
		moved_state,
		remaining_id,
		StringName(remaining_source.get("zone_id", "")),
		&"p1:play-area"
	)
	_expect(bool(move_tamper.get("ok", false)), "golem moved-source fixture should mutate candidate")
	var moved_hash := CanonicalJson.sha256(moved_state.to_dictionary())
	var moved_result := RulesEngine.dispatch(
		moved_state,
		_command_envelope(moved_state, {
			"type": "RESOLVE_CHOICE",
			"choice_id": golem_choice_id,
			"card_instance_id": str(remaining_id),
			"skip": false,
		}, "cmd-golem-moved"),
		definitions
	)
	_expect(
		str(moved_result.get("error", "")).begins_with("invalid_state:") \
				and moved_result.get("before_hash") == moved_hash \
				and moved_result.get("after_hash") == moved_hash,
		"golem moved candidate must reject only that command atomically"
	)
	var owner_state := mid_state.clone_state()
	(owner_state.cards[remaining_id] as Dictionary)["owner_id"] = "p2"
	var owner_hash := CanonicalJson.sha256(owner_state.to_dictionary())
	var owner_result := RulesEngine.dispatch(
		owner_state,
		_command_envelope(owner_state, {
			"type": "RESOLVE_CHOICE",
			"choice_id": golem_choice_id,
			"card_instance_id": str(remaining_id),
			"skip": false,
		}, "cmd-golem-owner"),
		definitions
	)
	_expect(
		str(owner_result.get("error", "")).begins_with("invalid_state:") \
				and owner_result.get("after_hash") == owner_hash,
		"golem ownership tamper must preserve committed first-step progress"
	)
	var finish_command: Dictionary = {}
	for command: Dictionary in mid_commands:
		if bool(command.get("skip", false)):
			finish_command = command
			break
	var one_result := RulesEngine.dispatch(
		mid_state,
		_command_envelope(mid_state, finish_command, "cmd-golem-finish-one"),
		definitions
	)
	_expect(
		bool(one_result.get("ok", false)) \
				and (one_result["state"] as GameStateData).effect_state.is_empty() \
				and int(((one_result.get("events", []) as Array)[0] as Dictionary) \
				.get("selected_count", -1)) == 1 \
				and not bool(((one_result.get("events", []) as Array)[0] as Dictionary) \
				.get("skipped", true)),
		"golem should allow completing after exactly one removal"
	)
	var second_envelope := _command_envelope(mid_state, {
		"type": "RESOLVE_CHOICE",
		"choice_id": golem_choice_id,
		"card_instance_id": str(remaining_id),
		"skip": false,
	}, "cmd-golem-second")
	var two_result := RulesEngine.dispatch(mid_state, second_envelope, definitions)
	var repeated_two := RulesEngine.dispatch(
		repeated_first["state"] as GameStateData, second_envelope, definitions
	)
	_expect(
		bool(two_result.get("ok", false)) \
				and (two_result["state"] as GameStateData).effect_state.is_empty() \
				and ZoneService.find_card_zone(
					two_result["state"] as GameStateData, remaining_id
				) == &"p1:removed",
		"golem should auto-complete after exactly two removals"
	)
	_expect(
		two_result.get("after_hash") == repeated_two.get("after_hash"),
		"golem final two-card hash should be deterministic"
	)
	var second_events := two_result.get("events", []) as Array
	_expect(
		second_events.size() == 3 \
				and (second_events[0] as Dictionary).get("reason") == "card_removed" \
				and (second_events[1] as Dictionary).get("type") == "choice_resolved" \
				and int((second_events[1] as Dictionary).get("selected_count", -1)) == 2 \
				and (second_events[2] as Dictionary).get("type") == "effect_resolved",
		"golem final-step events should order removal, choice completion, then effect completion"
	)


func _test_gargoyle_recruit_choice() -> void:
	var definitions := _load_definitions()
	var no_candidate := _baseline_state(251)
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
	var filter_state := _baseline_state(252)
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

	var state := _baseline_state(253)
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
	var no_candidate := _baseline_state(282)
	var no_candidate_definitions := base_definitions.duplicate()
	for resource_number in range(1, 29):
		var definition_id := StringName("base:resource/resource-%02d" % resource_number)
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
	var state := _baseline_state(seed)
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
	var state := _baseline_state(259)
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

	var empty_hand_state := _baseline_state(261)
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

	var boundary := _baseline_state(263)
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

	var failing_state := _baseline_state(265)
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
	var wrong_phase := _baseline_state(227)
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

	var insufficient := _baseline_state(228)
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
	var state := _baseline_state(230)
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
	var first := _baseline_state(223)
	var second := _baseline_state(223)
	for row_id: StringName in [SupplyService.RECRUIT_ROW_ID, SupplyService.SHOP_ROW_ID]:
		var first_row := first.zones[row_id] as ZoneData
		var second_row := second.zones[row_id] as ZoneData
		_expect(first_row.card_instance_ids.size() == 3, "supply row %s should start with three cards" % row_id)
		_expect(first_row.card_instance_ids == second_row.card_instance_ids, "same seed should produce the same %s order" % row_id)
	_expect((first.zones[SupplyService.RECRUIT_DECK_ID] as ZoneData).card_instance_ids.size() == 57, "recruit deck should retain fifty-seven official adventurers")
	_expect((first.zones[SupplyService.SHOP_DECK_ID] as ZoneData).card_instance_ids.size() == 56, "shop deck should retain fifty-six cards after the opening row")
	_expect(InvariantService.validate(first).is_empty(), "initial supply should satisfy invariants")


func _test_purchase_and_rest_refill() -> void:
	var definitions := _load_definitions()
	var state := _advance_to_purchase(_baseline_state(227), definitions, "cmd-buy-setup")
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
	var wrong_phase := _baseline_state(229)
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

	var poor_state := _advance_to_purchase(_baseline_state(233), definitions, "cmd-poor-setup")
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
	var state := _baseline_state(239)
	var row := state.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData
	for card_instance_id: StringName in row.card_instance_ids.duplicate():
		ZoneService.move_card(state, card_instance_id, SupplyService.RECRUIT_ROW_ID, &"p1:discard-pile")
	var deck := state.zones[SupplyService.RECRUIT_DECK_ID] as ZoneData
	while deck.card_instance_ids.size() > 3:
		ZoneService.move_card(
			state, deck.card_instance_ids[0], SupplyService.RECRUIT_DECK_ID, &"p1:discard-pile"
		)
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
		_baseline_state(240), definitions, "cmd-refresh-setup"
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
	var wrong_phase := _baseline_state(242)
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
		_baseline_state(244), definitions, "cmd-refresh-invalid-setup"
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
		_baseline_state(246), definitions, "cmd-refresh-order-setup"
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


func _test_official_adventurer_hud_integration() -> void:
	var packed := load("res://scenes/boot/main.tscn") as PackedScene
	var app := packed.instantiate() as GameApp
	app.enable_helpers = false
	root.add_child(app)
	await process_frame
	var full_detail_found := false
	for node: Node in app.hud.market_actions.find_children("*", "Label", true, false):
		var label := node as Label
		if label != null and "職業" in label.text and "效果：" in label.text \
				and "費用" in label.text and "戰力" in label.text and "榮譽" in label.text:
			full_detail_found = true
			break
	_expect(full_detail_found, "recruit HUD should show full official adventurer stats, profession, and rules text")
	app.queue_free()


func _test_market_refresh_hud_integration() -> void:
	var packed := load("res://scenes/boot/main.tscn") as PackedScene
	var app := packed.instantiate() as GameApp
	app.enable_helpers = false
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
	app.enable_helpers = false
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


func _test_official_resource_hud_integration() -> void:
	var packed := load("res://scenes/boot/main.tscn") as PackedScene
	var app := packed.instantiate() as GameApp
	app.enable_helpers = false
	root.add_child(app)
	await process_frame
	var state := app.session.state
	var holy_water_id := _move_definition_to_player_hand(state, &"base:resource/resource-04", &"p1")
	var monster_id := &"card-monster-rabbit-demon-01"
	ZoneService.move_card(state, monster_id, ZoneService.find_card_zone(state, monster_id), &"p1:hand")
	(state.cards[monster_id] as Dictionary)["owner_id"] = "p1"
	app.session._emit_state_changed()
	await process_frame
	var full_card_text_found := false
	var use_button: Button
	for child: Node in app.hud.hand_actions.get_children():
		if child is Label and "驅邪聖水｜費用 2｜榮譽 1" in (child as Label).text \
				and "棄置 1 張魔物後，抽 3 張牌" in (child as Label).text:
			full_card_text_found = true
		elif child is Button and (child as Button).text == "使用":
			var index := child.get_index()
			if index > 0 and app.hud.hand_actions.get_child(index - 1) is Label \
					and "驅邪聖水" in (app.hud.hand_actions.get_child(index - 1) as Label).text:
				use_button = child as Button
	_expect(full_card_text_found, "resource HUD should show type values and complete rules text")
	_expect(use_button != null, "resource HUD should expose a legal item action")
	if use_button != null:
		use_button.pressed.emit()
		await process_frame
		_expect("必要成本" in app.hud.hand_summary.text and "魔物" in app.hud.hand_summary.text, "resource pending HUD should show its locked mandatory cost")
		_expect(app.hud.end_phase_button.disabled, "resource cost pending choice should trap command focus")
	app.queue_free()


func _test_boss_hud_integration() -> void:
	var packed := load("res://scenes/boot/main.tscn") as PackedScene
	var app := packed.instantiate() as GameApp
	app.enable_helpers = false
	root.add_child(app)
	await process_frame
	var expose_error := _expose_boss(app.session.state, &"card-boss-10")
	_expect(expose_error.is_empty(), "boss HUD fixture should expose slime girl")
	app.session.state.phase = &"combat"
	(app.session.state.players[&"p1"] as PlayerStateData).turn_resources["combat"] = 20
	app.session._emit_state_changed()
	await process_frame
	var boss_info_found := false
	var boss_attack_button: Button
	for child: Node in app.hud.market_actions.get_children():
		if child is Label and "史萊姆娘｜戰力 14" in (child as Label).text \
				and "自己完整隊伍" in (child as Label).text:
			boss_info_found = true
		elif child is Button and "抽 3 張牌" in (child as Button).text:
			boss_attack_button = child as Button
	_expect(boss_info_found, "HUD should show public boss stats, rules, and reward text")
	_expect(boss_attack_button != null, "HUD should expose the ready boss attack preview")
	if boss_attack_button != null:
		_expect(not boss_attack_button.focus_neighbor_top.is_empty() and not boss_attack_button.focus_neighbor_bottom.is_empty(), "boss attack should participate in keyboard/gamepad focus flow")
	app.queue_free()


func _test_boss_choice_hud_integration() -> void:
	var packed := load("res://scenes/boot/main.tscn") as PackedScene
	var app := packed.instantiate() as GameApp
	app.enable_helpers = false
	root.add_child(app)
	await process_frame
	_expect(_expose_boss(app.session.state, &"card-boss-01").is_empty(), "boss choice HUD should expose red dragon")
	var shop := app.session.state.zones[SupplyService.SHOP_ROW_ID] as ZoneData
	var deck := app.session.state.zones[SupplyService.SHOP_DECK_ID] as ZoneData
	for card_id: StringName in shop.card_instance_ids.duplicate():
		ZoneService.move_card(app.session.state, card_id, shop.zone_id, deck.zone_id)
	for card_id: StringName in [&"card-supply-resource-08-01", &"card-supply-resource-08-02"]:
		ZoneService.move_card(app.session.state, card_id, ZoneService.find_card_zone(app.session.state, card_id), shop.zone_id)
	app.session.state.phase = &"combat"
	(app.session.state.players[&"p1"] as PlayerStateData).turn_resources["combat"] = 30
	var attack := app.session.attack_target(&"card-boss-01", true)
	_expect(bool(attack.get("ok", false)), "boss HUD should enter mandatory multi-gain")
	await process_frame
	var gain_buttons: Array[Button] = []
	for child: Node in app.hud.hand_actions.get_children():
		if child is Button and (child as Button).text == "從商店取得此牌":
			gain_buttons.append(child as Button)
	_expect(gain_buttons.size() == 2 and app.hud.end_phase_button.disabled, "Boss reward HUD should lock focus to two eligible gains")
	if not gain_buttons.is_empty():
		gain_buttons[0].pressed.emit()
		await process_frame
		_expect("已選 1/2" in app.hud.hand_summary.text, "Boss reward HUD should show multi-gain progress")
		var remaining_button: Button
		for child: Node in app.hud.hand_actions.get_children():
			if child is Button and (child as Button).text == "從商店取得此牌":
				remaining_button = child as Button
		_expect(remaining_button != null and remaining_button.focus_neighbor_top == remaining_button.get_path() and remaining_button.focus_neighbor_bottom == remaining_button.get_path(), "mandatory reward focus should remain closed on the final choice")
	app.queue_free()

	var lich_app := packed.instantiate() as GameApp
	lich_app.enable_helpers = false
	root.add_child(lich_app)
	await process_frame
	_expect(_expose_boss(lich_app.session.state, &"card-boss-03").is_empty(), "lich HUD should expose lich")
	var adventurer_id := (lich_app.session.state.zones[SupplyService.RECRUIT_ROW_ID] as ZoneData).card_instance_ids[0]
	ZoneService.move_card(lich_app.session.state, adventurer_id, SupplyService.RECRUIT_ROW_ID, &"p1:hand")
	(lich_app.session.state.cards[adventurer_id] as Dictionary)["owner_id"] = "p1"
	lich_app.session.state.phase = &"combat"
	(lich_app.session.state.players[&"p1"] as PlayerStateData).turn_resources["combat"] = 30
	var lich_attack := lich_app.session.attack_target(&"card-boss-03", true)
	_expect(bool(lich_attack.get("ok", false)), "lich HUD should enter its post-departure cost")
	await process_frame
	var cost_button: Button
	for child: Node in lich_app.hud.hand_actions.get_children():
		if child is Button and (child as Button).text == "棄置此冒險者":
			cost_button = child as Button
	_expect(cost_button != null and "完成巫妖討伐" in lich_app.hud.hand_summary.text, "lich HUD should show full mandatory cost prompt")
	_expect(lich_app.hud.end_phase_button.disabled, "lich pending cost should block ordinary commands")
	lich_app.queue_free()


func _test_pending_choice_hud_integration() -> void:
	var packed := load("res://scenes/boot/main.tscn") as PackedScene
	var app := packed.instantiate() as GameApp
	app.enable_helpers = false
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
	app.enable_helpers = false
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


func _test_multi_zone_removal_hud_integration() -> void:
	var packed := load("res://scenes/boot/main.tscn") as PackedScene
	var app := packed.instantiate() as GameApp
	app.enable_helpers = false
	root.add_child(app)
	await process_frame
	var expose_error := _expose_monster(
		app.session.state,
		&"card-monster-golem-01",
		&"card-monster-rabbit-demon-01"
	)
	_expect(expose_error.is_empty(), "golem HUD fixture should expose the target")
	(app.session.state.players[&"p1"] as PlayerStateData).turn_resources[&"combat"] = 6
	var phase_result := app.session.end_phase()
	_expect(bool(phase_result.get("ok", false)), "golem HUD fixture should enter combat")
	var attack_result := app.session.attack_target(&"card-monster-golem-01", true)
	_expect(bool(attack_result.get("ok", false)), "golem HUD should create multi-source choice")
	await process_frame
	var removal_buttons: Array[Button] = []
	var completion_button: Button
	var source_labels := {"hand": 0, "party": 0, "discard": 0}
	for child: Node in app.hud.hand_actions.get_children():
		if child is Button and (child as Button).text.begins_with("從自己的"):
			removal_buttons.append(child as Button)
		elif child is Button and (child as Button).text == "略過移除":
			completion_button = child as Button
		elif child is Label:
			var label_text := (child as Label).text
			if "來源：自己的手牌" in label_text:
				source_labels.hand = int(source_labels.hand) + 1
			elif "來源：自己的隊伍" in label_text:
				source_labels.party = int(source_labels.party) + 1
			elif "來源：自己的棄牌堆" in label_text:
				source_labels.discard = int(source_labels.discard) + 1
	_expect(
		int(source_labels.hand) == 5 \
				and int(source_labels.party) == 4 \
				and int(source_labels.discard) == 1,
		"golem HUD should label each remaining candidate with its actual source"
	)
	_expect(completion_button != null, "golem HUD should initially show skip removal")
	_expect(
		"可以從自己的手牌、隊伍或棄牌堆移除最多 2 張牌（已選 0/2）" \
				in app.hud.hand_summary.text \
				and "來源：自己的手牌、自己的隊伍、自己的棄牌堆" \
				in app.hud.hand_summary.text,
		"golem HUD should show complete multi-source prompt and initial progress"
	)
	if not removal_buttons.is_empty() and completion_button != null:
		_expect(
			removal_buttons[0].focus_neighbor_top == completion_button.get_path() \
					and completion_button.focus_neighbor_bottom == removal_buttons[0].get_path(),
			"golem pending focus should wrap inside choice controls"
		)
		removal_buttons[0].pressed.emit()
		await process_frame
		_expect(
			int(app.session.state.effect_state.get("selected_count", -1)) == 1 \
					and "（已選 1/2）" in app.hud.hand_summary.text,
			"golem HUD should reproject progress after the first removal"
		)
		var remaining_buttons: Array[Button] = []
		completion_button = null
		for child: Node in app.hud.hand_actions.get_children():
			if child is Button and (child as Button).text.begins_with("從自己的"):
				remaining_buttons.append(child as Button)
			elif child is Button and (child as Button).text == "完成移除（已選 1/2）":
				completion_button = child as Button
		_expect(
			remaining_buttons.size() == removal_buttons.size() - 1,
			"golem HUD should remove the selected card from projected candidates"
		)
		_expect(completion_button != null, "golem HUD should offer finish after one selection")
		if not remaining_buttons.is_empty() and completion_button != null:
			_expect(
				remaining_buttons[0].focus_neighbor_top == completion_button.get_path() \
						and completion_button.focus_neighbor_bottom \
						== remaining_buttons[0].get_path(),
				"golem progress focus should remain trapped"
			)
			completion_button.pressed.emit()
			await process_frame
			_expect(
				app.session.state.effect_state.is_empty(),
				"golem HUD finish should commit exactly one removal"
			)
	app.queue_free()


func _test_gargoyle_choice_hud_integration() -> void:
	var packed := load("res://scenes/boot/main.tscn") as PackedScene
	var app := packed.instantiate() as GameApp
	app.enable_helpers = false
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
	app.enable_helpers = false
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
	app.enable_helpers = false
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


func _test_mimic_and_lamia_hud_integration() -> void:
	var packed := load("res://scenes/boot/main.tscn") as PackedScene
	var mimic_app := packed.instantiate() as GameApp
	mimic_app.enable_helpers = false
	root.add_child(mimic_app)
	await process_frame
	var expose_error := _expose_monster(
		mimic_app.session.state,
		&"card-monster-mimic-01",
		&"card-monster-rabbit-demon-01"
	)
	_expect(expose_error.is_empty(), "mimic HUD fixture should expose the target")
	var phase_result := mimic_app.session.end_phase()
	_expect(bool(phase_result.get("ok", false)), "mimic HUD fixture should enter combat")
	await process_frame
	var preview_found := false
	for child: Node in mimic_app.hud.market_actions.get_children():
		if child is Button and "1／2 → 1、3／4 → 2、5／6 → 3 購買力" in (child as Button).text:
			preview_found = true
	_expect(preview_found, "mimic HUD should preview the complete dice rule")
	var attack_result := mimic_app.session.attack_target(&"card-monster-mimic-01", true)
	_expect(bool(attack_result.get("ok", false)), "mimic HUD attack should resolve")
	await process_frame
	_expect(
		"寶箱怪擲出" in mimic_app.hud.event_label.text \
				and "購買力" in mimic_app.hud.event_label.text,
		"mimic HUD should show the rolled face and gained purchase power"
	)
	mimic_app.queue_free()
	await process_frame

	var lamia_app := packed.instantiate() as GameApp
	lamia_app.enable_helpers = false
	root.add_child(lamia_app)
	await process_frame
	expose_error = _expose_monster(
		lamia_app.session.state,
		&"card-monster-lamia-01",
		&"card-monster-rabbit-demon-01"
	)
	_expect(expose_error.is_empty(), "lamia HUD fixture should expose the target")
	phase_result = lamia_app.session.end_phase()
	_expect(bool(phase_result.get("ok", false)), "lamia HUD fixture should enter combat")
	var lamia_attack := lamia_app.session.attack_target(&"card-monster-lamia-01", true)
	_expect(bool(lamia_attack.get("ok", false)), "lamia HUD attack should create the draft")
	await process_frame
	_expect(lamia_app.hud.hand_title.text == "蛇妖物資輪抽", "lamia HUD should show its draft title")
	_expect(
		"目前應選：玩家一" in lamia_app.hud.hand_summary.text \
				and "剩餘 2 張" in lamia_app.hud.hand_summary.text,
		"lamia HUD should show current chooser and remaining count"
	)
	var first_buttons: Array[Button] = []
	var candidate_labels := 0
	for child: Node in lamia_app.hud.hand_actions.get_children():
		if child is Button and (child as Button).text == "從物資輪抽區取得此牌":
			first_buttons.append(child as Button)
		elif child is Label and ("道具" in (child as Label).text or "裝備" in (child as Label).text):
			candidate_labels += 1
	_expect(first_buttons.size() == 2 and candidate_labels == 2, "lamia HUD should show both candidates with type and values")
	if first_buttons.size() == 2:
		_expect(
			first_buttons[0].focus_neighbor_top == first_buttons[1].get_path() \
					and first_buttons[1].focus_neighbor_bottom == first_buttons[0].get_path(),
			"lamia mandatory choice focus should wrap within candidates"
		)
		first_buttons[0].pressed.emit()
		await process_frame
		_expect(
			lamia_app.session.state.active_player_id == &"p1" \
					and lamia_app.session.state.effect_state.get("required_actor_id") == "p2",
			"lamia HUD pick should rotate chooser without changing active player"
		)
		_expect("目前應選：玩家二" in lamia_app.hud.hand_summary.text, "lamia HUD should update to player two")
		var second_button: Button
		for child: Node in lamia_app.hud.hand_actions.get_children():
			if child is Button and (child as Button).text == "從物資輪抽區取得此牌":
				second_button = child as Button
		if second_button != null:
			second_button.pressed.emit()
			await process_frame
			_expect(lamia_app.session.state.effect_state.is_empty(), "lamia HUD final pick should clear pending choice")
			_expect(not lamia_app.hud.end_phase_button.disabled, "lamia HUD should restore active-player controls")
	lamia_app.queue_free()


func _test_play_adventurer_capacity_and_equipment_departure() -> void:
	var definitions := _load_definitions()
	var state := _baseline_state(241)
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
	var state := _baseline_state(251)
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
	var state := _baseline_state()
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
	var errors := session.start_new_game(91, false, false)
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
	var state := _baseline_state()
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
	var state := _baseline_state(113)
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
	var exact_draw := _baseline_state(127)
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

	var shortage := _baseline_state(131)
	var shortage_events: Array[Dictionary] = []
	var cleanup_error := DeckService.discard_hand_and_play_area(shortage, &"p1", shortage_events)
	_expect(cleanup_error.is_empty(), "shortage fixture cleanup should succeed")
	var shortage_result := DeckService.draw_cards(shortage, &"p1", 9, shortage_events)
	_expect(bool(shortage_result.get("ok", false)), "short draw should finish without fabricating cards")
	_expect(int(shortage_result.get("drawn_count", 0)) == 5, "draw should return only physically available cards")
	_expect(InvariantService.validate(shortage).is_empty(), "short draw should preserve invariants")


func _test_seeded_shuffle_order() -> void:
	var first := _baseline_state(149)
	var second := _baseline_state(149)
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
	var state := _baseline_state()
	var first := RulesEngine.dispatch(state, _end_phase_envelope(state, "cmd-duplicate"))
	_expect(bool(first.get("ok", false)), "first command submission should succeed")
	if bool(first.get("ok", false)):
		var next_state := first["state"] as GameStateData
		var duplicate_envelope := _end_phase_envelope(next_state, "cmd-duplicate")
		var duplicate := RulesEngine.dispatch(next_state, duplicate_envelope)
		_expect(str(duplicate.get("error", "")) == "duplicate_command", "duplicate command ID must be rejected")


func _test_twenty_blank_rounds() -> void:
	var state := _baseline_state()
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
	var first := _baseline_state(301)
	var second := _baseline_state(301)
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
	var state := _baseline_state()
	var before_hash := CanonicalJson.sha256(state.to_dictionary())
	var envelope := _end_phase_envelope(state)
	envelope["expected_revision"] = 99
	var result := RulesEngine.dispatch(state, envelope)
	_expect(not bool(result.get("ok", true)), "stale command should fail")
	_expect(str(result.get("error", "")) == "stale_revision", "stale command should return stable error code")
	_expect(CanonicalJson.sha256(state.to_dictionary()) == before_hash, "failed command must not mutate state")
	_expect(result.get("before_hash") == result.get("after_hash"), "failed command must preserve hash")


func _test_snapshot_round_trip() -> void:
	var state := _baseline_state()
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
	var state := _baseline_state()
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


func _move_definition_to_player_hand(
	state: GameStateData, definition_id: StringName, player_id: StringName
) -> StringName:
	var card_id := _find_instance_by_definition(state, definition_id)
	if card_id.is_empty():
		return &""
	var player := state.players[player_id] as PlayerStateData
	var source_zone_id := ZoneService.find_card_zone(state, card_id)
	if source_zone_id != StringName(player.zone_ids[&"hand"]):
		var move_result := ZoneService.move_card(
			state, card_id, source_zone_id, StringName(player.zone_ids[&"hand"])
		)
		if not bool(move_result.get("ok", false)):
			return &""
	(state.cards[card_id] as Dictionary)["owner_id"] = str(player_id)
	return card_id


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


func _expose_boss(state: GameStateData, target_card_id: StringName) -> String:
	var active := state.zones[BossService.BOSS_ACTIVE_ID] as ZoneData
	if target_card_id in active.card_instance_ids:
		return ""
	var current_id := active.card_instance_ids[0]
	var current_card := state.cards[current_id] as Dictionary
	var current_state := current_card.get("state", {}) as Dictionary
	var definitions := _load_definitions()
	for raw_attachment_id: Variant in (current_state.get("attachment_ids", []) as Array).duplicate():
		var attachment_id := StringName(str(raw_attachment_id))
		var attachment := state.cards[attachment_id] as Dictionary
		var attachment_state := attachment.get("state", {}) as Dictionary
		attachment_state.erase("attached_to")
		attachment["state"] = attachment_state
		var attachment_definition := definitions.get(
			StringName(attachment.get("definition_id", ""))
		) as CardDefinition
		var destination := SupplyService.RECRUIT_DECK_ID \
				if attachment_definition != null and attachment_definition.card_type == &"adventurer" \
				else SupplyService.SHOP_DECK_ID
		ZoneService.move_card(
			state, attachment_id, BossService.BOSS_ATTACHMENT_ID, destination
		)
	current_state["attachment_ids"] = []
	current_card["state"] = current_state
	var move_result := ZoneService.move_card(
		state, current_id, BossService.BOSS_ACTIVE_ID, BossService.BOSS_DECK_ID, 0
	)
	if not bool(move_result.get("ok", false)):
		return str(move_result.get("error", "boss_fixture_replacement_failed"))
	var source_zone_id := ZoneService.find_card_zone(state, target_card_id)
	move_result = ZoneService.move_card(
		state, target_card_id, source_zone_id, BossService.BOSS_ACTIVE_ID
	)
	return "" if bool(move_result.get("ok", false)) else str(
		move_result.get("error", "boss_fixture_target_failed")
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


func _event_index(events: Array[Dictionary], event_type: String) -> int:
	for index in events.size():
		if str(events[index].get("type", "")) == event_type:
			return index
	return -1


func _commands_contain(commands: Array[Dictionary], command_type: String) -> bool:
	for command: Dictionary in commands:
		if str(command.get("type", "")) == command_type:
			return true
	return false
