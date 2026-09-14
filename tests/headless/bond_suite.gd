class_name BondSuite
extends RefCounted

const EXPECTED_NAMES := [
	"提振士氣", "獨挑大樑", "魅惑時間", "卸甲逃跑", "設備改造",
	"順手牽羊", "援護射擊", "颯爽登場", "恐懼凝視", "野性狂化",
	"急速施法", "肉身強化", "全力以赴", "情熱舞蹈", "天馬行空",
	"精明交涉", "預知未來", "出其不意", "魔力爆發", "勇氣吶喊",
	"靈光一閃", "精神陶亂", "冒冒失失", "全場鎮壓", "母性感化",
	"魔性誘惑", "悠悠哉哉", "鎮魂演奏", "神聖祈禱", "洗腦操縱",
]
const EXPECTED_HONOR := [
	4, 4, 4, 3, 3, 3, 4, 4, 4, 4,
	5, 5, 4, 6, 5, 5, 7, 3, 5, 5,
	5, 4, 6, 3, 4, 4, 4, 4, 4, 4,
]

var failures := PackedStringArray()


func run(definitions: Dictionary) -> PackedStringArray:
	_test_content(definitions)
	_test_setup_and_privacy(definitions)
	_test_predicates(definitions)
	_test_completion_and_final_round(definitions)
	_test_combat_trigger(definitions)
	_test_simultaneous_and_tamper(definitions)
	_test_scoring_ties(definitions)
	_test_turn_fact_boundaries(definitions)
	_test_combat_start_boundary(definitions)
	return failures


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _test_content(definitions: Dictionary) -> void:
	var count := 0
	for number in 30:
		var definition := definitions.get(StringName("base:bond/bond-%02d" % (number + 1))) as CardDefinition
		_expect(definition != null, "bond %02d definition exists" % (number + 1))
		if definition == null:
			continue
		count += 1
		_expect(definition.display_name == EXPECTED_NAMES[number] \
				and definition.honor == EXPECTED_HONOR[number] and definition.copies == 1 \
				and definition.card_type == &"bond" and not definition.rules_text.is_empty() \
				and not definition.completion_rule.is_empty(),
			"bond %02d has official name, honor, copies, text and rule" % (number + 1))
	_expect(count == 30, "official bond pack has 30 definitions")
	for definition_id: Variant in definitions:
		if str(definition_id).begins_with("base:bond/"):
			_expect(str(definition_id).begins_with("base:bond/bond-"), "custom bonds absent")


func _dispatch_choice(state: GameStateData, card_id: String, skip: bool, definitions: Dictionary) -> Dictionary:
	var choice := state.effect_state
	var actor := str(choice.get("required_actor_id", ""))
	return RulesEngine.dispatch(state, {
		"protocol_version": 1, "game_id": str(state.game_id),
		"command_id": "bond-suite-%06d" % (state.revision + 1),
		"actor_id": actor, "expected_revision": state.revision,
		"command": {
			"type": "RESOLVE_CHOICE", "choice_id": str(choice.get("choice_id", "")),
			"card_instance_id": card_id, "skip": skip,
		},
	}, definitions)


func _complete_setup(state: GameStateData, definitions: Dictionary) -> GameStateData:
	var guard := 0
	while StringName(state.effect_state.get("op", "")) == &"select_bonds" and guard < 10:
		var choice := state.effect_state
		var selected := choice.get("selected_card_ids", []) as Array
		var pick := ""
		for raw_id: Variant in choice.get("eligible_card_ids", []):
			if str(raw_id) not in selected:
				pick = str(raw_id)
				break
		var result := _dispatch_choice(state, pick, false, definitions)
		_expect(bool(result.get("ok", false)), "setup pick %d must commit: %s" % [guard, result.get("error", "")])
		if not bool(result.get("ok", false)):
			break
		state = result["state"] as GameStateData
		guard += 1
	_expect(guard > 0 and guard <= 10 and state.effect_state.is_empty(), "both players select five bonds")
	return state


func _test_setup_and_privacy(definitions: Dictionary) -> void:
	var state := GameStateData.create_vertical_slice(20001, definitions, false, true)
	var same := GameStateData.create_vertical_slice(20001, definitions, false, true)
	var session := GameSession.new()
	var emitted_public: Array[Dictionary] = []
	session.state_changed.connect(func(view: Dictionary) -> void: emitted_public.append(view))
	var session_errors := session.start_new_game(20001, false, true)
	_expect(session_errors.is_empty() and emitted_public.size() == 1,
		"session emits a distinct public state projection")
	if emitted_public.size() == 1:
		var public_view := emitted_public[0]
		var public_zone := (public_view.get("zones", {}) as Dictionary).get(
			"p1:bond-candidates", {}
		) as Dictionary
		_expect((public_zone.get("card_instance_ids", []) as Array).is_empty() \
				and not public_view.has("seed") and not public_view.has("rng_state") \
				and not (public_view.get("effect_state", {}) as Dictionary).has("eligible_card_ids"),
			"public signal contains no private bond identities or shuffle seed")
	_expect(CanonicalJson.sha256(state.to_dictionary()) == CanonicalJson.sha256(same.to_dictionary()), "bond setup deterministic hash")
	_expect(InvariantService.validate(state).is_empty(), "initial bond setup invariant")
	_expect(state.cards.size() == same.cards.size(), "bond instances deterministic")
	var p1 := state.players[&"p1"] as PlayerStateData
	var p2 := state.players[&"p2"] as PlayerStateData
	_expect((state.zones[p1.zone_ids[&"bond_candidates"]] as ZoneData).card_instance_ids.size() == 7 \
			and (state.zones[p2.zone_ids[&"bond_candidates"]] as ZoneData).card_instance_ids.size() == 7 \
			and (state.zones[BondService.SUPPLY_ID] as ZoneData).card_instance_ids.size() == 16,
		"setup deals 7 each from 30")
	var view := PlayerView.project(state, &"p1")
	var visible_zones := view.get("zones", {}) as Dictionary
	var hidden_p2 := visible_zones[str(p2.zone_ids[&"bond_candidates"])] as Dictionary
	_expect((hidden_p2.get("card_instance_ids", []) as Array).is_empty() \
			and int(hidden_p2.get("card_count", 0)) == 7 \
			and not view.has("seed") and not view.has("rng_state"), "opponent bond identities and RNG hidden")
	var p2_candidate := (state.zones[p2.zone_ids[&"bond_candidates"]] as ZoneData).card_instance_ids[0]
	_expect(not (view.get("cards", {}) as Dictionary).has(str(p2_candidate)), "opponent bond card record hidden")
	_expect(RulesEngine.get_legal_commands(state, &"p2", definitions).is_empty(), "non-required actor has no setup commands")
	var before := CanonicalJson.sha256(state.to_dictionary())
	var wrong := RulesEngine.dispatch(state, {
		"protocol_version": 1, "game_id": str(state.game_id),
		"command_id": "wrong-bond-actor", "actor_id": "p2", "expected_revision": state.revision,
		"command": {"type": "RESOLVE_CHOICE", "choice_id": str(state.effect_state["choice_id"]),
			"card_instance_id": str(p2_candidate), "skip": false},
	}, definitions)
	_expect(not bool(wrong.get("ok", false)) and CanonicalJson.sha256(state.to_dictionary()) == before, "wrong setup actor rejected atomically")
	var snapshot := SnapshotCodec.encode(state, "bond-content", "bond-rules")
	var restored := SnapshotCodec.decode(snapshot, "bond-content", "bond-rules")
	_expect(bool(restored.get("ok", false)), "initial setup pending snapshot round-trip")
	var first_id := str((state.effect_state.get("eligible_card_ids", []) as Array)[0])
	var first := _dispatch_choice(state, first_id, false, definitions)
	_expect(bool(first.get("ok", false)), "first setup choice commits")
	if not bool(first.get("ok", false)):
		return
	state = first["state"] as GameStateData
	_expect(bool(SnapshotCodec.decode(SnapshotCodec.encode(state, "bond-content", "bond-rules"), "bond-content", "bond-rules").get("ok", false)), "mid-setup snapshot round-trip")
	state = _complete_setup(state, definitions)
	same = _complete_setup(same, definitions)
	_expect(CanonicalJson.sha256(state.to_dictionary()) == CanonicalJson.sha256(same.to_dictionary()),
		"resolved setup deterministic hash")
	if not state.effect_state.is_empty():
		return
	_expect((state.zones[p1.zone_ids[&"bonds"]] as ZoneData).card_instance_ids.size() == 5 \
			and (state.zones[p2.zone_ids[&"bonds"]] as ZoneData).card_instance_ids.size() == 5 \
			and (state.zones[BondService.REMOVED_ID] as ZoneData).card_instance_ids.size() == 4,
		"setup retains five each and removes four")
	_expect(InvariantService.validate(state).is_empty(), "completed setup invariant")
	var p2_view := PlayerView.project(state, &"p1")
	_expect(((p2_view.get("zones", {}) as Dictionary)[str(p2.zone_ids[&"bonds"])] as Dictionary).get("card_instance_ids", []).is_empty(), "incomplete opponent bonds remain hidden")


func _test_predicates(definitions: Dictionary) -> void:
	var party_specs := {
		1: ["support", "mage", "support"], 3: ["tank", "mage", "mage"],
		4: ["support"], 7: ["tank", "ranged", "ranged"],
		9: ["tank", "melee", "tank"], 10: ["melee", "melee"],
		11: ["support", "support"], 12: ["tank", "tank"],
		14: ["support", "mage", "tank", "melee", "ranged"],
		15: ["ranged", "ranged"], 19: ["mage", "mage"],
		20: ["melee", "melee"], 21: ["support", "support", "support"],
		22: ["tank", "tank"], 28: ["mage", "mage"],
		29: ["support", "support"], 30: ["support", "mage", "tank"],
	}
	var facts := {
		5: {"bought_equipment": 2}, 6: {"recruited_adventurer": 1, "bought_resource": 1},
		8: {"nonstarter_party_entries": 3}, 13: {"items_used:action1": 3},
		16: {"recruited_adventurer": 2}, 17: {"extra_cards_drawn": 3},
		23: {"combat_equipment_discarded": 3}, 24: {"defeated_monster_count": 1},
		25: {"monster_cards_used_for_purchase": 3}, 26: {"defeated_monster_count": 2},
	}
	for number in range(1, 31):
		var state := GameStateData.create_vertical_slice(20000 + number, definitions, false, false)
		var player := state.players[&"p1"] as PlayerStateData
		var rule := (definitions[StringName("base:bond/bond-%02d" % number)] as CardDefinition).completion_rule
		var context := {}
		_expect(not BondService._matches(state, player, rule, context, definitions), "bond %02d negative baseline" % number)
		if party_specs.has(number):
			_set_party(state, party_specs[number], definitions)
		if facts.has(number):
			player.turn_facts.merge(facts[number], true)
		if number == 2:
			context = {"participant_count": 1, "target_type": "monster"}
		if number == 18:
			context = {"nonstarter_departure_professions": 3}
		if number == 27:
			player.spent_purchase_power = 7
		_expect(BondService._matches(state, player, rule, context, definitions), "bond %02d positive boundary" % number)
		var near := state.clone_state()
		var near_player := near.players[&"p1"] as PlayerStateData
		var op := StringName(rule.get("op", ""))
		if op in [&"fact_min", &"action_fact_min"]:
			var key := str(rule.get("key", ""))
			if op == &"action_fact_min":
				key += ":action1"
			near_player.turn_facts[key] = int(rule.get("count", 0)) - 1
		elif op == &"facts_all_min":
			near_player.turn_facts[str((rule.get("keys", []) as Array)[0])] = 0
		elif op == &"spent_purchase_min":
			near_player.spent_purchase_power = 6
		elif op == &"combat_participants_exact":
			context["participant_count"] = 2
		elif op == &"combat_departure_professions":
			context["nonstarter_departure_professions"] = 2
		else:
			var near_party := near.zones[near_player.zone_ids[&"party"]] as ZoneData
			if not near_party.card_instance_ids.is_empty():
				var remove_index := 4 if number == 14 else near_party.card_instance_ids.size() - 1
				var remove_id := near_party.card_instance_ids[remove_index]
				ZoneService.move_card(
					near, remove_id, near_party.zone_id,
					StringName(near_player.zone_ids[&"discard_pile"])
				)
		_expect(not BondService._matches(near, near_player, rule, context, definitions),
			"bond %02d rejects one-below boundary" % number)
		if number == 14:
			var party := state.zones[player.zone_ids[&"party"]] as ZoneData
			var extra := _take_adventurer(state, "mage", definitions)
			if not extra.is_empty():
				party.card_instance_ids.append(extra)
				_expect(BondService._matches(state, player, rule, context, definitions), "bond 14 accepts six-member party")


func _set_party(state: GameStateData, tags: Array, definitions: Dictionary) -> void:
	var player := state.players[&"p1"] as PlayerStateData
	var party := state.zones[player.zone_ids[&"party"]] as ZoneData
	var discard := state.zones[player.zone_ids[&"discard_pile"]] as ZoneData
	for card_id: StringName in party.card_instance_ids.duplicate():
		ZoneService.move_card(state, card_id, party.zone_id, discard.zone_id)
	for raw_tag: Variant in tags:
		var picked := _take_adventurer(state, str(raw_tag), definitions)
		if not picked.is_empty():
			party.card_instance_ids.append(picked)


func _take_adventurer(state: GameStateData, tag: String, definitions: Dictionary) -> StringName:
	for zone_id: StringName in [SupplyService.RECRUIT_DECK_ID, SupplyService.RECRUIT_ROW_ID]:
		var zone := state.zones[zone_id] as ZoneData
		for card_id: StringName in zone.card_instance_ids.duplicate():
			var card := state.cards[card_id] as Dictionary
			var definition := definitions[StringName(card["definition_id"])] as CardDefinition
			if definition.card_type == &"adventurer" and StringName(tag) in definition.tags:
				zone.card_instance_ids.erase(card_id)
				card["owner_id"] = "p1"
				return card_id
	return &""


func _test_completion_and_final_round(definitions: Dictionary) -> void:
	var state := _complete_setup(GameStateData.create_vertical_slice(20071, definitions, false, true), definitions)
	if not state.effect_state.is_empty():
		return
	var player := state.players[&"p1"] as PlayerStateData
	var incomplete := state.zones[player.zone_ids[&"bonds"]] as ZoneData
	var completed := state.zones[player.zone_ids[&"completed_bonds"]] as ZoneData
	var target := &"card-bond-24"
	if target not in incomplete.card_instance_ids:
		var source_id := ZoneService.find_card_zone(state, target)
		var replaced := incomplete.card_instance_ids[0]
		ZoneService.move_card(state, replaced, incomplete.zone_id, source_id)
		(state.cards[replaced] as Dictionary)["owner_id"] = str(
			(state.zones[source_id] as ZoneData).metadata.get("owner_id", "")
		)
		ZoneService.move_card(state, target, source_id, incomplete.zone_id)
		(state.cards[target] as Dictionary)["owner_id"] = "p1"
	player.turn_facts["defeated_monster_count"] = 1
	var events: Array[Dictionary] = []
	BondService.check(state, &"p1", &"after_defeat", {}, events, definitions)
	_expect(StringName(state.effect_state.get("op", "")) == &"complete_bonds", "eligible bond creates optional choice")
	if state.effect_state.is_empty():
		return
	var initial_snapshot := SnapshotCodec.decode(SnapshotCodec.encode(state, "bond-content", "bond-rules"), "bond-content", "bond-rules")
	_expect(bool(initial_snapshot.get("ok", false)), "bond completion pending snapshot round-trip")
	var before := CanonicalJson.sha256(state.to_dictionary())
	var invalid := _dispatch_choice(state, "card-bond-99", false, definitions)
	_expect(not bool(invalid.get("ok", false)) and CanonicalJson.sha256(state.to_dictionary()) == before, "invalid bond candidate is atomic")
	var staged := _dispatch_choice(state, str(target), false, definitions)
	_expect(bool(staged.get("ok", false)), "bond can be staged")
	if not bool(staged.get("ok", false)):
		return
	state = staged["state"] as GameStateData
	incomplete = state.zones[player.zone_ids[&"bonds"]] as ZoneData
	completed = state.zones[player.zone_ids[&"completed_bonds"]] as ZoneData
	_expect(target in incomplete.card_instance_ids and completed.card_instance_ids.is_empty(), "staging does not publicly reveal before batch commit")
	_expect(bool(SnapshotCodec.decode(SnapshotCodec.encode(state, "bond-content", "bond-rules"), "bond-content", "bond-rules").get("ok", false)), "staged bond snapshot round-trip")
	var committed := _dispatch_choice(state, "", true, definitions)
	_expect(bool(committed.get("ok", false)), "bond batch confirmation commits")
	if not bool(committed.get("ok", false)):
		return
	state = committed["state"] as GameStateData
	completed = state.zones[player.zone_ids[&"completed_bonds"]] as ZoneData
	_expect(target in completed.card_instance_ids and state.effect_state.is_empty(), "completed bond public and immutable")
	_expect(int((BondService.score_all(state, definitions)["p1"] as Dictionary)["honor"]) == 3,
		"only completed bond contributes honor")
	var view := PlayerView.project(state, &"p2")
	_expect(str(target) in ((view.get("zones", {}) as Dictionary)[str(player.zone_ids[&"completed_bonds"])] as Dictionary).get("card_instance_ids", []), "completed bond visible to opponent")
	var other := state.zones[player.zone_ids[&"bonds"]] as ZoneData
	for card_id: StringName in other.card_instance_ids.duplicate():
		ZoneService.move_card(state, card_id, other.zone_id, completed.zone_id)
	BondService.update_final_round(state, events)
	_expect(not state.final_round.is_empty() and state.final_round.get("end_player_id") == "p2", "fifth bond starts current-round finish policy")
	_expect(bool(SnapshotCodec.decode(SnapshotCodec.encode(state, "bond-content", "bond-rules"), "bond-content", "bond-rules").get("ok", false)), "final-round snapshot round-trip")
	var simultaneous := state.clone_state()
	(simultaneous.zones[BossService.BOSS_ACTIVE_ID] as ZoneData).metadata["all_bosses_defeated"] = true
	var reason_events: Array[Dictionary] = []
	BondService.update_final_round(simultaneous, reason_events)
	_expect("all_bosses_defeated" in (simultaneous.final_round.get("reasons", []) as Array) \
			and reason_events.size() == 1 \
			and reason_events[0].get("type", "") == "final_round_reasons_updated",
		"simultaneous end reasons reuse one final round and remain auditable")
	for _index in 10:
		if state.status == &"finished":
			break
		var result := RulesEngine.dispatch(state, {
			"protocol_version": 1, "game_id": str(state.game_id),
			"command_id": "bond-final-%06d" % (state.revision + 1),
			"actor_id": str(state.active_player_id), "expected_revision": state.revision,
			"command": {"type": "END_PHASE"},
		}, definitions)
		_expect(bool(result.get("ok", false)), "final round phase advances: %s" % result.get("error", ""))
		if not bool(result.get("ok", false)):
			break
		state = result["state"] as GameStateData
	_expect(state.status == &"finished" and state.active_player_id == &"p2" \
			and state.round_number == 1 and not state.final_scores.is_empty() \
			and RulesEngine.get_legal_commands(state, &"p2", definitions).is_empty(),
		"final round stops after the starting player's right-side seat finishes")


func _test_combat_trigger(definitions: Dictionary) -> void:
	var state := _complete_setup(GameStateData.create_vertical_slice(20424, definitions, false, true), definitions)
	if not state.effect_state.is_empty():
		return
	var player := state.players[&"p1"] as PlayerStateData
	var wanted := &"card-bond-24"
	_install_bond(state, wanted, &"p1")
	state.phase = &"combat"
	var before := CanonicalJson.sha256(state.to_dictionary())
	var envelope := {
		"protocol_version": 1, "game_id": str(state.game_id),
		"command_id": "bond-combat-1", "actor_id": "p1", "expected_revision": state.revision,
		"command": {"type": "ATTACK_TARGET", "target_card_id": "card-monster-skeleton-01",
			"claim_optional_reward": false},
	}
	var attack := RulesEngine.dispatch(state, envelope, definitions)
	_expect(bool(attack.get("ok", false)), "defeat with eligible bond should dispatch: %s" % attack.get("error", ""))
	if not bool(attack.get("ok", false)):
		return
	_expect(str(attack.get("before_hash", "")) == before, "bond combat before hash is stable")
	var replay := _complete_setup(GameStateData.create_vertical_slice(20424, definitions, false, true), definitions)
	_install_bond(replay, wanted, &"p1")
	replay.phase = &"combat"
	var replay_attack := RulesEngine.dispatch(replay, envelope, definitions)
	_expect(bool(replay_attack.get("ok", false)) \
			and replay_attack.get("after_hash", "") == attack.get("after_hash", "") \
			and CanonicalJson.stringify(replay_attack.get("events", [])) == CanonicalJson.stringify(attack.get("events", [])),
		"same seed and command replay identical bond pending hash and events")
	state = attack["state"] as GameStateData
	_expect(StringName(state.effect_state.get("op", "")) == &"complete_bonds" \
			and wanted in (state.effect_state.get("eligible_card_ids", []) as Array),
		"bond completion is offered after enemy defeat")
	var event_types: Array[String] = []
	for event: Dictionary in attack.get("events", []):
		event_types.append(str(event.get("type", "")))
	_expect(event_types.find("enemy_defeated") >= 0 \
			and event_types.find("bond_completion_requested") > event_types.find("enemy_defeated"),
		"bond choice event follows complete enemy defeat")
	var skipped := _dispatch_choice(state, "", true, definitions)
	_expect(bool(skipped.get("ok", false)), "eligible bond can be temporarily skipped")
	if bool(skipped.get("ok", false)):
		var after := skipped["state"] as GameStateData
		_expect(after.effect_state.is_empty() and wanted in (after.zones[player.zone_ids[&"bonds"]] as ZoneData).card_instance_ids,
			"skipped bond stays incomplete and scores no honor")
		if bool(replay_attack.get("ok", false)):
			var replay_skip := _dispatch_choice(replay_attack["state"] as GameStateData, "", true, definitions)
			_expect(bool(replay_skip.get("ok", false)) \
					and replay_skip.get("after_hash", "") == skipped.get("after_hash", ""),
				"resolved bond choice deterministic hash")


func _install_bond(
	state: GameStateData, bond_id: StringName, player_id: StringName
) -> void:
	var player := state.players[player_id] as PlayerStateData
	var destination := state.zones[player.zone_ids[&"bonds"]] as ZoneData
	if bond_id in destination.card_instance_ids:
		return
	var source_id := ZoneService.find_card_zone(state, bond_id)
	var replaced := destination.card_instance_ids[0]
	for existing_id: StringName in destination.card_instance_ids:
		if existing_id not in [&"card-bond-24", &"card-bond-26"]:
			replaced = existing_id
			break
	ZoneService.move_card(state, replaced, destination.zone_id, source_id)
	(state.cards[replaced] as Dictionary)["owner_id"] = str(
		(state.zones[source_id] as ZoneData).metadata.get("owner_id", "")
	)
	ZoneService.move_card(state, bond_id, source_id, destination.zone_id)
	(state.cards[bond_id] as Dictionary)["owner_id"] = str(player_id)


func _test_simultaneous_and_tamper(definitions: Dictionary) -> void:
	var state := _complete_setup(GameStateData.create_vertical_slice(20426, definitions, false, true), definitions)
	if not state.effect_state.is_empty():
		return
	_install_bond(state, &"card-bond-24", &"p1")
	_install_bond(state, &"card-bond-26", &"p1")
	var player := state.players[&"p1"] as PlayerStateData
	player.turn_facts["defeated_monster_count"] = 2
	var events: Array[Dictionary] = []
	BondService.check(state, &"p1", &"after_defeat", {}, events, definitions)
	var eligible := state.effect_state.get("eligible_card_ids", []) as Array
	_expect("card-bond-24" in eligible and "card-bond-26" in eligible,
		"same boundary can offer multiple official bonds in one batch")
	if state.effect_state.is_empty():
		return
	var tampered := state.clone_state()
	var tampered_ids := tampered.effect_state.get("eligible_card_ids", []) as Array
	tampered_ids.erase("card-bond-26")
	var hash_before := CanonicalJson.sha256(tampered.to_dictionary())
	var bad := _dispatch_choice(tampered, "card-bond-24", false, definitions)
	_expect(not bool(bad.get("ok", false)) and CanonicalJson.sha256(tampered.to_dictionary()) == hash_before,
		"tampered locked candidates reject dispatch atomically")
	var moved := state.clone_state()
	var zone := moved.zones[player.zone_ids[&"bonds"]] as ZoneData
	ZoneService.move_card(moved, &"card-bond-24", zone.zone_id, StringName(player.zone_ids[&"discard_pile"]))
	var moved_hash := CanonicalJson.sha256(moved.to_dictionary())
	var moved_result := _dispatch_choice(moved, "card-bond-24", false, definitions)
	_expect(not bool(moved_result.get("ok", false)) \
			and CanonicalJson.sha256(moved.to_dictionary()) == moved_hash,
		"moved bond candidate rejects dispatch atomically")
	var first := _dispatch_choice(state, "card-bond-24", false, definitions)
	_expect(bool(first.get("ok", false)), "first simultaneous bond may be staged")
	if not bool(first.get("ok", false)):
		return
	state = first["state"] as GameStateData
	var repeat := _dispatch_choice(state, "card-bond-24", false, definitions)
	_expect(not bool(repeat.get("ok", false)), "same bond cannot be staged twice")
	var finish := _dispatch_choice(state, "", true, definitions)
	_expect(bool(finish.get("ok", false)), "subset batch can be committed")
	if not bool(finish.get("ok", false)):
		return
	state = finish["state"] as GameStateData
	var completed := state.zones[player.zone_ids[&"completed_bonds"]] as ZoneData
	var incomplete := state.zones[player.zone_ids[&"bonds"]] as ZoneData
	_expect(&"card-bond-24" in completed.card_instance_ids \
			and &"card-bond-26" in incomplete.card_instance_ids \
			and state.final_round.is_empty(),
		"subset claim leaves unselected bond secret and does not start final round")


func _test_scoring_ties(definitions: Dictionary) -> void:
	var state := GameStateData.create_vertical_slice(20999, definitions, false, false)
	var p1 := state.players[&"p1"] as PlayerStateData
	var p2 := state.players[&"p2"] as PlayerStateData
	_expect((BondService.score_all(state, definitions)["winners"] as Array).size() == 2,
		"exact honor and tie-break equality yields joint victory")
	p1.counters["defeated_boss_count"] = 1
	_expect(BondService.score_all(state, definitions)["winners"] == ["p1"],
		"boss wins first honor tie-break")
	p2.counters["defeated_boss_count"] = 1
	p2.counters["defeated_monster_count"] = 2
	_expect(BondService.score_all(state, definitions)["winners"] == ["p2"],
		"monster wins second honor tie-break")


func _test_turn_fact_boundaries(definitions: Dictionary) -> void:
	var state := _complete_setup(GameStateData.create_vertical_slice(20313, definitions, false, true), definitions)
	if not state.effect_state.is_empty():
		return
	_install_bond(state, &"card-bond-13", &"p1")
	for _index in 2:
		var used: Array[Dictionary] = [{"type": "item_used", "actor_id": "p1"}]
		BondService.record_and_check(state, &"action1", used, definitions)
	_expect(state.effect_state.is_empty(), "two items in first action phase do not complete bond 13")
	state.phase = &"action2"
	var one_more: Array[Dictionary] = [{"type": "item_used", "actor_id": "p1"}]
	BondService.record_and_check(state, &"action2", one_more, definitions)
	_expect(state.effect_state.is_empty(), "item counts cannot combine across action phases")
	for _index in 2:
		var used: Array[Dictionary] = [{"type": "item_used", "actor_id": "p1"}]
		BondService.record_and_check(state, &"action2", used, definitions)
	_expect(StringName(state.effect_state.get("op", "")) == &"complete_bonds" \
			and "card-bond-13" in (state.effect_state.get("eligible_card_ids", []) as Array),
		"third item in one action phase offers bond 13")
	var second := _complete_setup(GameStateData.create_vertical_slice(20317, definitions, false, true), definitions)
	if not second.effect_state.is_empty():
		return
	_install_bond(second, &"card-bond-17", &"p1")
	var player := second.players[&"p1"] as PlayerStateData
	var draw_event: Array[Dictionary] = [{
		"type": "card_moved", "reason": "draw", "player_id": "p1",
		"to_zone_id": str(player.zone_ids[&"hand"]),
	}]
	for _index in 5:
		BondService.record_and_check(second, &"rest", draw_event, definitions)
	_expect(int(player.turn_facts.get("extra_cards_drawn", 0)) == 0 \
			and second.effect_state.is_empty(), "rest fixed draw does not count as extra")
	for _index in 3:
		BondService.record_and_check(second, &"action1", draw_event, definitions)
	_expect(int(player.turn_facts.get("extra_cards_drawn", 0)) == 3 \
			and "card-bond-17" in (second.effect_state.get("eligible_card_ids", []) as Array),
		"three effect draws offer bond 17 at actual drawn count")


func _test_combat_start_boundary(definitions: Dictionary) -> void:
	var state := _complete_setup(GameStateData.create_vertical_slice(20010, definitions, false, true), definitions)
	if not state.effect_state.is_empty():
		return
	_install_bond(state, &"card-bond-01", &"p1")
	_set_party(state, ["support", "mage", "support"], definitions)
	var result := RulesEngine.dispatch(state, {
		"protocol_version": 1, "game_id": str(state.game_id),
		"command_id": "bond-combat-start", "actor_id": "p1", "expected_revision": state.revision,
		"command": {"type": "END_PHASE"},
	}, definitions)
	_expect(bool(result.get("ok", false)), "entering combat with start bond is legal")
	if not bool(result.get("ok", false)):
		return
	state = result["state"] as GameStateData
	_expect(state.phase == &"combat" and StringName(state.effect_state.get("op", "")) == &"complete_bonds" \
			and bool(state.effect_state.get("bond_combat_start_continuation", false)),
		"combat-start bond pauses before other start effects")
	var types: Array[String] = []
	for event: Dictionary in result.get("events", []):
		types.append(str(event.get("type", "")))
	_expect(types.find("phase_changed") >= 0 and types.find("bond_completion_requested") > types.find("phase_changed"),
		"combat-start event order is phase then bond prompt")
	_expect(bool(SnapshotCodec.decode(SnapshotCodec.encode(state, "bond-content", "bond-rules"), "bond-content", "bond-rules").get("ok", false)),
		"combat-start continuation survives snapshot")
	var skipped := _dispatch_choice(state, "", true, definitions)
	_expect(bool(skipped.get("ok", false)), "skipping combat-start bond resumes phase-start effects")
