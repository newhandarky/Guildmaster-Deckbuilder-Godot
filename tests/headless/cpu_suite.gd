class_name CpuSuite
extends RefCounted

var failures := PackedStringArray()


func run() -> PackedStringArray:
	_test_four_player_setup_and_privacy()
	_test_decision_and_snapshot()
	_test_combat_feature_parity()
	_test_boss_progress_policy()
	_test_multi_equipment_policy()
	_test_departed_supply_card_does_not_trigger()
	_test_four_seat_rotation()
	_test_progress_guard()
	return failures


func run_ui(tree: SceneTree) -> PackedStringArray:
	var packed := load("res://scenes/boot/main.tscn") as PackedScene
	var app := packed.instantiate() as GameApp
	tree.root.add_child(app)
	await tree.process_frame
	_expect(app.session.state.players.size() == 4 and app.enable_cpu,
		"production scene starts one human plus three CPU seats")
	var current := app.hud._current_state as Dictionary
	_expect(current.get("viewer_id", "") == "p1" and app.hud.end_phase_button.disabled,
		"four-player HUD stays on human private view during setup")
	for _pick in 5:
		var choice := app.session.state.effect_state
		if StringName(choice.get("required_actor_id", "")) != &"p1":
			break
		var selected := choice.get("selected_card_ids", []) as Array
		var card_id := ""
		for raw_id: Variant in choice.get("eligible_card_ids", []):
			if str(raw_id) not in selected:
				card_id = str(raw_id)
				break
		var result := app.session.resolve_choice(str(choice.get("choice_id", "")),
			StringName(card_id), false)
		_expect(bool(result.get("ok", false)), "human setup choice commits before CPU turn")
	await tree.process_frame
	await tree.process_frame
	_expect(app.session.state.effect_state.is_empty() \
		and app.session.state.active_player_id == &"p1",
		"CPU completes three private bond setups and returns control to human")
	current = app.hud._current_state as Dictionary
	var p2 := app.session.state.players[&"p2"] as PlayerStateData
	var p2_hand := (current.get("zones", {}) as Dictionary).get(str(p2.zone_ids[&"hand"]), {}) as Dictionary
	_expect(current.get("viewer_id", "") == "p1" \
		and (p2_hand.get("card_instance_ids", []) as Array).is_empty(),
		"CPU setup does not expose CPU hand in human HUD")
	var returned_to_human := false
	for _tick in 100:
		var access := app.session.get_turn_access()
		if app.session.state.round_number >= 2 and app.session.state.active_player_id == &"p1" \
				and app.session.state.phase == &"action1" and app.session.state.effect_state.is_empty():
			returned_to_human = true
			break
		if str(access.get("actor_id", "")) == "p1":
			var legal := app.session.get_legal_commands(&"p1")
			if not legal.is_empty():
				var selected := legal[0]
				for candidate: Dictionary in legal:
					if str(candidate.get("type", "")) == "END_PHASE":
						selected = candidate
						break
				var result := app.session.submit_command({
					"protocol_version": 1, "game_id": str(app.session.state.game_id),
					"command_id": "human-ui-%06d" % (app.session.state.revision + 1),
					"actor_id": "p1", "expected_revision": app.session.state.revision,
					"command": CpuCommandCodec.payload(selected),
				})
				_expect(bool(result.get("ok", false)), "human HUD command resolves")
				if not bool(result.get("ok", false)):
					break
		await tree.process_frame
	_expect(returned_to_human and (app.hud._current_state as Dictionary).get("viewer_id", "") == "p1",
		"three CPU seats complete their turns and return the HUD to the human")
	app.queue_free()
	await tree.process_frame
	return failures


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)


func _test_four_player_setup_and_privacy() -> void:
	var session := GameSession.new()
	var errors := session.start_new_game(21001, true, true, 4)
	_expect(errors.is_empty(), "four-player official setup starts")
	if not errors.is_empty():
		return
	var state := session.state
	_expect(state.turn_order == [&"p1", &"p2", &"p3", &"p4"] \
		and state.players.size() == 4 and InvariantService.validate(state).is_empty(),
		"four seats, order and zone uniqueness")
	var boss_count := (state.zones[BossService.BOSS_DECK_ID] as ZoneData).card_instance_ids.size() \
		+ (state.zones[BossService.BOSS_ACTIVE_ID] as ZoneData).card_instance_ids.size()
	var helper_count := (state.zones[HelperService.DECK_ID] as ZoneData).card_instance_ids.size() \
		+ (state.zones[HelperService.ACTIVE_ID] as ZoneData).card_instance_ids.size()
	_expect(boss_count == 6 and helper_count == 6, "four-player Boss/helper selection scales to six")
	for player_id: StringName in state.turn_order:
		var player := state.players[player_id] as PlayerStateData
		_expect((state.zones[player.zone_ids[&"bond_candidates"]] as ZoneData).card_instance_ids.size() == 7,
			"each of four players receives seven private bond candidates")
	var p2 := state.players[&"p2"] as PlayerStateData
	var p1_view := session.get_player_view(&"p1")
	var p2_hand := (p1_view["zones"] as Dictionary)[str(p2.zone_ids[&"hand"])] as Dictionary
	var p2_bonds := (p1_view["zones"] as Dictionary)[str(p2.zone_ids[&"bond_candidates"])] as Dictionary
	_expect((p2_hand.get("card_instance_ids", []) as Array).is_empty() \
		and (p2_bonds.get("card_instance_ids", []) as Array).is_empty() \
		and not p1_view.has("rng_state") and not p1_view.has("seed"),
		"other player hand, bonds and authoritative RNG are hidden")
	var wrong := session.submit_command({
		"protocol_version": 1, "game_id": str(state.game_id), "command_id": "wrong-cpu-actor",
		"actor_id": "p2", "expected_revision": state.revision,
		"command": {"type": "END_PHASE"},
	})
	_expect(not bool(wrong.get("ok", false)) and wrong.get("before_hash") == wrong.get("after_hash"),
		"non-required actor fails atomically during private setup")
	var first_context := session.get_client_context(&"p1")
	var first_decision := _decide(first_context)
	var altered := state.clone_state()
	var hidden_hand := altered.zones[p2.zone_ids[&"hand"]] as ZoneData
	if hidden_hand.card_instance_ids.size() > 1:
		hidden_hand.card_instance_ids.reverse()
	var hidden_bonds := altered.zones[p2.zone_ids[&"bond_candidates"]] as ZoneData
	if hidden_bonds.card_instance_ids.size() > 1:
		hidden_bonds.card_instance_ids.reverse()
	var hidden_deck := altered.zones[SupplyService.SHOP_DECK_ID] as ZoneData
	if hidden_deck.card_instance_ids.size() > 1:
		hidden_deck.card_instance_ids.reverse()
	altered.rng_state += 1
	session.state = altered
	var private_change_decision := _decide(session.get_client_context(&"p1"))
	_expect(first_decision.get("command") == private_change_decision.get("command") \
		and first_decision.get("reason_code") == private_change_decision.get("reason_code") \
		and first_decision.get("score") == private_change_decision.get("score") \
		and first_decision.get("context_fingerprint") == private_change_decision.get("context_fingerprint"),
		"opponent private order and authoritative RNG do not affect CPU decision")
	session.state = state
	for _step in 20:
		if state.effect_state.is_empty():
			break
		var required := StringName(state.effect_state.get("required_actor_id", ""))
		var legal := session.get_legal_commands(required)
		_expect(not legal.is_empty() and session.get_legal_commands(
			state.turn_order[(state.turn_order.find(required) + 1) % 4]
		).is_empty(), "only required bond actor has commands")
		if legal.is_empty():
			break
		var picked := session.submit_command({
			"protocol_version": 1, "game_id": str(state.game_id),
			"command_id": "cpu-setup-%06d" % (state.revision + 1),
			"actor_id": str(required), "expected_revision": state.revision,
			"command": CpuCommandCodec.payload(legal[0]),
		})
		_expect(bool(picked.get("ok", false)), "four-player bond setup choice resolves")
		if not bool(picked.get("ok", false)):
			break
		state = session.state
	_expect(state.effect_state.is_empty() and state.active_player_id == &"p1",
		"all four private bond selections complete without changing active player")


func _test_decision_and_snapshot() -> void:
	var session := GameSession.new()
	var errors := session.start_new_game(21003, true, true, 4)
	_expect(errors.is_empty(), "decision fixture starts")
	if not errors.is_empty():
		return
	var context := session.get_client_context(&"p1")
	var legal := context.get("legal_commands", []) as Array
	var features := context.get("action_features", []) as Array
	_expect(legal.size() == features.size(), "action features have legal-command parity")
	for raw_feature: Variant in features:
		var feature := raw_feature as Dictionary
		var found := false
		for raw_legal: Variant in legal:
			found = found or CpuCommandCodec.key(raw_legal as Dictionary) == str(feature.get("command_key", ""))
		_expect(found, "feature belongs to an actual legal command")
	var first := _decide(context)
	var second := _decide(context)
	_expect(not first.is_empty() and first == second,
		"same visible input yields identical command, reason, score and fingerprint")
	var reversed_legal: Array[Dictionary] = []
	reversed_legal.assign(legal)
	reversed_legal.reverse()
	var reversed_features: Array[Dictionary] = []
	reversed_features.assign(features)
	reversed_features.reverse()
	var reordered := CpuDecider.decide(context["player_view"], reversed_legal,
		reversed_features, context["public_definitions"])
	_expect(first == reordered, "canonical command tie-break ignores Dictionary/list order")
	var snapshot := SnapshotCodec.encode(session.state,
		session.content_registry.pack_fingerprint, GameSession.RULESET_FINGERPRINT)
	var decoded := SnapshotCodec.decode(snapshot, session.content_registry.pack_fingerprint,
		GameSession.RULESET_FINGERPRINT)
	_expect(bool(decoded.get("ok", false)), "four-player Snapshot round-trips")
	if not bool(decoded.get("ok", false)):
		return
	var restored := GameSession.new()
	var restore_errors := restored.start_new_game(21003, true, true, 4)
	_expect(restore_errors.is_empty(), "replay session starts")
	if not restore_errors.is_empty():
		return
	restored.state = decoded["state"] as GameStateData
	var restored_context := restored.get_client_context(&"p1")
	_expect(CanonicalJson.sha256(context["action_features"]) == CanonicalJson.sha256(
		restored_context["action_features"]) and first == _decide(restored_context),
		"Snapshot restore preserves features and CPU decision")
	var envelope := {
		"protocol_version": 1, "game_id": str(session.state.game_id),
		"command_id": "cpu-replay-step", "actor_id": "p1",
		"expected_revision": session.state.revision,
		"command": first.get("command", {}),
	}
	var original_step := session.submit_command(envelope)
	var replay_step := restored.submit_command(envelope)
	_expect(bool(original_step.get("ok", false)) and bool(replay_step.get("ok", false)) \
		and original_step.get("after_hash") == replay_step.get("after_hash"),
		"replay uses saved command and has deterministic after_hash")


func _test_four_seat_rotation() -> void:
	var session := GameSession.new()
	var errors := session.start_new_game(21004, false, false, 4)
	_expect(errors.is_empty(), "four-player no-helper fixture starts")
	if not errors.is_empty():
		return
	for seat_index in 4:
		var expected_id := StringName("p%d" % (seat_index + 1))
		_expect(session.state.active_player_id == expected_id,
			"turn order rotates to seat %d" % (seat_index + 1))
		for _phase in 5:
			var result := session.end_phase()
			_expect(bool(result.get("ok", false)), "four-player phase advances")
			if not bool(result.get("ok", false)):
				return
	_expect(session.state.active_player_id == &"p1" and session.state.round_number == 2,
		"fourth seat returns to first and increments round")


func _test_combat_feature_parity() -> void:
	var session := GameSession.new()
	if not session.start_new_game(21007, false, false, 4).is_empty():
		failures.append("combat-feature parity fixture starts")
		return
	var context := session.get_client_context(&"p1")
	var features := context.get("action_features", []) as Array
	var boss := session.state.zones[BossService.BOSS_ACTIVE_ID] as ZoneData
	if boss.card_instance_ids.is_empty():
		failures.append("combat-feature parity fixture exposes a Boss")
		return
	var boss_id: StringName = boss.card_instance_ids[0]
	for raw_feature: Variant in features:
		var feature := raw_feature as Dictionary
		var command := feature.get("command", {}) as Dictionary
		if command.get("type", "") == "BUY_CARD":
			_expect(not bool(feature.get("boss_unlocked", false)) \
				and int(feature.get("combat_gain", 0)) == 0,
				"buying future combat never claims immediate Boss unlock")
		if int(feature.get("combat_gain", 0)) <= 0 \
				and not bool(feature.get("boss_unlocked", false)):
			continue
		var result := RulesEngine.dispatch(session.state, {
			"protocol_version": 1, "game_id": str(session.state.game_id),
			"command_id": "feature-parity", "actor_id": "p1",
			"expected_revision": session.state.revision, "command": command,
		}, session.content_registry.definitions)
		_expect(bool(result.get("ok", false)), "projected combat action dispatches")
		if not bool(result.get("ok", false)):
			continue
		var after := result["state"] as GameStateData
		var preview := CombatService.preview_attack(after, &"p1", boss_id,
			session.content_registry.definitions)
		_expect(int(preview.get("gap", -1)) == int(feature.get("boss_gap_after", -2)) \
			and bool(preview.get("legal", false)) == bool(feature.get("boss_unlocked", false)),
			"projected Boss gap/unlock matches authoritative post-command preview")


func _test_progress_guard() -> void:
	var guard := CpuProgressGuard.new()
	_expect(guard.observe("same", "1:p2") == "" and guard.observe("same", "1:p2") == "" \
		and guard.observe("same", "1:p2") == "repeated_public_state",
		"three identical public contexts produce no-progress diagnostic")
	guard = CpuProgressGuard.new()
	var error := ""
	for index in 129:
		error = guard.observe("unique-%d" % index, "1:p2")
	_expect(error == "max_actions_per_turn" and CpuProgressGuard.MAX_ACTIONS_PER_TURN == 128 \
		and CpuProgressGuard.MAX_AUTONOMOUS_STEPS == 512,
		"CPU diagnostic preserves 128/512 caps")
	guard = CpuProgressGuard.new()
	_expect(guard.observe_result({"phase":"combat","active_player_id":"p2","status":"active",
		"effect_state":{}}, {"phase":"combat","active_player_id":"p2","status":"active",
		"effect_state":{}}, "END_PHASE", "before", "after") == "phase_not_advanced",
		"unchanged phase is diagnosed immediately")
	_expect(guard.observe_result({"effect_state":{"op":"choose_move_card","choice_id":"c",
		"required_actor_id":"p2","selected_count":0,"eligible_card_ids":["a"]}},
		{"effect_state":{"op":"choose_move_card","choice_id":"c",
		"required_actor_id":"p2","selected_count":0,"eligible_card_ids":["a"]}},
		"RESOLVE_CHOICE", "before", "after") == "choice_not_consumed",
		"unconsumed pending choice is diagnosed")


func _test_boss_progress_policy() -> void:
	var view := {"phase": "action1", "round": 1, "active_player_id": "p1",
		"effect_state": {}, "players": {}, "zones": {}}
	var play := {"type": "PLAY_ADVENTURER", "card_instance_id": "owned-card"}
	var end := {"type": "END_PHASE"}
	var legal: Array[Dictionary] = [play, end]
	var features: Array[Dictionary] = [
		{"command": play, "command_key": CpuCommandCodec.key(play),
			"printed_combat": 3, "boss_gap_before": 4,
			"consumes_last_boss_cost_card": true},
		{"command": end, "command_key": CpuCommandCodec.key(end)},
	]
	_expect(CpuDecider.decide(view, legal, features, {}).get("command", {}) == end,
		"CPU reserves the last matching hand card for a public Boss cost")
	features[0]["consumes_last_boss_cost_card"] = false
	_expect(CpuDecider.decide(view, legal, features, {}).get("command", {}) == play,
		"CPU may play a card when the Boss cost remains payable")
	features[0]["boss_gap_delta"] = -2
	_expect(CpuDecider.decide(view, legal, features, {}).get("command", {}) == end,
		"CPU does not replace stronger front-line combat with a weaker play")
	view["phase"] = "combat"
	var attack := {"type": "ATTACK_TARGET", "target_card_id": "visible-target"}
	legal = [attack, end]
	features = [
		{"command": attack, "command_key": CpuCommandCodec.key(attack),
			"attack_target_type": "monster", "boss_gap_before": 4,
			"participant_loss": 1},
		{"command": end, "command_key": CpuCommandCodec.key(end)},
	]
	_expect(CpuDecider.decide(view, legal, features, {}).get("command", {}) == end,
		"CPU preserves near-ready Boss party instead of losing combatants to a monster")
	features[0]["boss_gap_before"] = 9
	_expect(CpuDecider.decide(view, legal, features, {}).get("command", {}) == attack,
		"CPU can still gain resources while far from the Boss threshold")
	features[0]["attack_target_type"] = "boss"
	features[0]["boss_post_departure_cost_required"] = true
	features[0]["boss_post_departure_cost_available"] = 0
	_expect(CpuDecider.decide(view, legal, features, {}).get("command", {}) == end,
		"CPU does not intentionally attack a Boss when its required cost is unpayable")


func _test_multi_equipment_policy() -> void:
	var session := GameSession.new()
	if not session.start_new_game(21009, false, false, 4).is_empty():
		failures.append("multi-equipment policy fixture starts")
		return
	var state := session.state
	var adventurer_id := _move_definition_to_hand(state, "base:adventurer/adventurer-29")
	var joined := PartyService.apply(state, &"p1", {"card_instance_id": str(adventurer_id)},
		session.content_registry.definitions, [])
	_expect(joined.is_empty(), "policy adventurer joins party")
	if not joined.is_empty():
		return
	for definition_id: String in ["base:resource/resource-09", "base:resource/resource-11"]:
		var equipment_id := _move_definition_to_hand(state, definition_id)
		var attached := EquipmentService.apply(state, &"p1", {
			"type": "EQUIP_ITEM", "card_instance_id": str(equipment_id),
			"target_card_id": str(adventurer_id),
		}, session.content_registry.definitions, [])
		_expect(attached.is_empty(), "policy adventurer accepts second attachment")
	var target := state.cards.get(adventurer_id, {}) as Dictionary
	var attachments := ((target.get("state", {}) as Dictionary).get("equipment_ids", []) as Array)
	_expect(attachments.size() == 2 \
		and InvariantService.validate(state, session.content_registry.definitions).is_empty(),
		"two attachments remain bidirectional and satisfy data-driven capacity")


func _test_departed_supply_card_does_not_trigger() -> void:
	var session := GameSession.new()
	if not session.start_new_game(21010, false, false, 4).is_empty():
		failures.append("combat departure ownership fixture starts")
		return
	var state := session.state
	var supply_card_id := &""
	for raw_id: Variant in state.cards:
		var card := state.cards[raw_id] as Dictionary
		if str(card.get("definition_id", "")) == "base:adventurer/adventurer-06" \
				and str(card.get("owner_id", "")).is_empty():
			supply_card_id = StringName(str(raw_id))
			break
	_expect(not supply_card_id.is_empty(), "unowned adventurer supply card exists")
	if supply_card_id.is_empty():
		return
	var player := state.players[&"p1"] as PlayerStateData
	player.turn_facts["combat_participant_ids"] = [str(supply_card_id)]
	player.turn_facts["defeated_enemy"] = true
	var events: Array[Dictionary] = []
	var error := EffectResolver.resolve_party_trigger(state, &"p1", &"on_combat_end",
		events, session.content_registry.definitions)
	_expect(error.is_empty() and state.effect_state.is_empty(),
		"former participant in public supply cannot trigger an owner's combat-end effect")


func _move_definition_to_hand(state: GameStateData, definition_id: String) -> StringName:
	for raw_id: Variant in state.cards:
		var card := state.cards[raw_id] as Dictionary
		if str(card.get("definition_id", "")) != definition_id \
				or not str(card.get("owner_id", "")).is_empty():
			continue
		var card_id := StringName(str(raw_id))
		var source := ZoneService.find_card_zone(state, card_id)
		var destination := StringName((state.players[&"p1"] as PlayerStateData).zone_ids[&"hand"])
		if bool(ZoneService.move_card(state, card_id, source, destination).get("ok", false)):
			card["owner_id"] = "p1"
			return card_id
	return &""


func _decide(context: Dictionary) -> Dictionary:
	var legal: Array[Dictionary] = []
	legal.assign(context.get("legal_commands", []))
	var features: Array[Dictionary] = []
	features.assign(context.get("action_features", []))
	return CpuDecider.decide(context.get("player_view", {}), legal, features,
		context.get("public_definitions", {}))
