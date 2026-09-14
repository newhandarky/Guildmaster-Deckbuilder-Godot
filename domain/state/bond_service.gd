class_name BondService
extends RefCounted

const SUPPLY_ID := &"shared:bond-supply"
const REMOVED_ID := &"shared:bond-removed"
const PROFESSION_TAGS := [&"support", &"mage", &"tank", &"melee", &"ranged"]


static func setup(state: GameStateData, definitions: Dictionary) -> void:
	var supply := ZoneData.new(SUPPLY_ID, &"ordered_deck", &"hidden")
	var removed := ZoneData.new(REMOVED_ID, &"removed", &"hidden")
	state.zones[supply.zone_id] = supply
	state.zones[removed.zone_id] = removed
	for number in range(1, 31):
		var suffix := "%02d" % number
		var definition_id := StringName("base:bond/bond-%s" % suffix)
		if not definitions.has(definition_id):
			continue
		var card_id := StringName("card-bond-%s" % suffix)
		state.cards[card_id] = {
			"instance_id": str(card_id), "definition_id": str(definition_id),
			"owner_id": "", "state": {},
		}
		supply.card_instance_ids.append(card_id)
	var rng := DeterministicRng.new(state.seed_value, state.rng_state)
	rng.shuffle(supply.card_instance_ids)
	state.rng_state = rng.get_state()
	for player_id: StringName in state.turn_order:
		var player := state.players[player_id] as PlayerStateData
		var candidates := state.zones[player.zone_ids[&"bond_candidates"]] as ZoneData
		for _index in 7:
			if supply.card_instance_ids.is_empty():
				break
			var card_id: StringName = StringName(supply.card_instance_ids.pop_back())
			candidates.card_instance_ids.append(card_id)
			(state.cards[card_id] as Dictionary)["owner_id"] = str(player_id)
	if not state.turn_order.is_empty():
		_request_setup(state, state.turn_order[0], [])


static func _request_setup(
	state: GameStateData, required_actor_id: StringName, events: Array[Dictionary]
) -> void:
	var player := state.players[required_actor_id] as PlayerStateData
	var candidates := state.zones[player.zone_ids[&"bond_candidates"]] as ZoneData
	var eligible: Array[String] = []
	for card_id: StringName in candidates.card_instance_ids:
		eligible.append(str(card_id))
	state.effect_state = {
		"type": "pending_choice", "op": "select_bonds",
		"choice_id": "choice-%06d-bond-setup-%s" % [state.revision + 1, required_actor_id],
		"actor_id": str(state.active_player_id),
		"required_actor_id": str(required_actor_id),
		"source_zone_id": str(candidates.zone_id),
		"destination_zone_id": str(player.zone_ids[&"bonds"]),
		"eligible_card_ids": eligible, "selected_card_ids": [],
		"locked_eligible_hash": CanonicalJson.sha256(eligible),
		"selected_count": 0, "min_selections": 5, "max_selections": 5,
		"prompt": "從 7 張秘密候選羈絆中選擇 5 張保留；其餘 2 張本局移除。",
	}
	events.append({
		"type": "bond_setup_requested", "required_actor_id": str(required_actor_id),
		"choice_id": str(state.effect_state["choice_id"]),
		"private_card_ids": eligible.duplicate(),
	})


static func legal_commands(state: GameStateData, actor_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var choice := state.effect_state
	if StringName(choice.get("required_actor_id", "")) != actor_id:
		return result
	var selected := choice.get("selected_card_ids", []) as Array
	for raw_id: Variant in choice.get("eligible_card_ids", []):
		if str(raw_id) in selected:
			continue
		result.append({
			"type": "RESOLVE_CHOICE", "actor_id": str(actor_id),
			"expected_revision": state.revision,
			"choice_id": str(choice.get("choice_id", "")),
			"card_instance_id": str(raw_id), "skip": false,
		})
	if StringName(choice.get("op", "")) == &"complete_bonds":
		result.append({
			"type": "RESOLVE_CHOICE", "actor_id": str(actor_id),
			"expected_revision": state.revision,
			"choice_id": str(choice.get("choice_id", "")),
			"card_instance_id": "", "skip": true,
		})
	return result


static func validate_choice(
	state: GameStateData, actor_id: StringName, command: Dictionary
) -> String:
	var choice := state.effect_state
	var op := StringName(choice.get("op", ""))
	if op not in [&"select_bonds", &"complete_bonds"]:
		return "unsupported_choice_operation"
	if StringName(choice.get("required_actor_id", "")) != actor_id:
		return "wrong_choice_actor"
	if str(command.get("choice_id", "")) != str(choice.get("choice_id", "")):
		return "wrong_choice_id"
	if not command.get("skip", false) is bool:
		return "invalid_choice_skip"
	var skip := bool(command.get("skip", false))
	var card_id := StringName(command.get("card_instance_id", ""))
	if skip:
		if op == &"select_bonds":
			return "choice_required"
		return "" if card_id.is_empty() else "invalid_skipped_choice"
	if card_id.is_empty() or str(card_id) not in (choice.get("eligible_card_ids", []) as Array):
		return "ineligible_choice_card"
	if str(card_id) in (choice.get("selected_card_ids", []) as Array):
		return "choice_card_already_selected"
	var player := state.players.get(actor_id) as PlayerStateData
	if player == null:
		return "missing_player"
	var required_source := StringName(player.zone_ids[
		&"bond_candidates" if op == &"select_bonds" else &"bonds"
	])
	var required_destination := StringName(player.zone_ids[
		&"bonds" if op == &"select_bonds" else &"completed_bonds"
	])
	if StringName(choice.get("source_zone_id", "")) != required_source \
			or StringName(choice.get("destination_zone_id", "")) != required_destination:
		return "invalid_bond_choice_zone"
	if ZoneService.find_card_zone(state, card_id) != required_source:
		return "choice_card_moved"
	var card := state.cards.get(card_id) as Dictionary
	if card == null or StringName(card.get("owner_id", "")) != actor_id:
		return "choice_card_not_owned"
	return ""


static func apply_choice(
	state: GameStateData, actor_id: StringName, command: Dictionary,
	events: Array[Dictionary], definitions: Dictionary
) -> String:
	var error := validate_choice(state, actor_id, command)
	if not error.is_empty():
		return error
	var choice := state.effect_state.duplicate(true)
	var op := StringName(choice.get("op", ""))
	var skip := bool(command.get("skip", false))
	var card_id := StringName(command.get("card_instance_id", ""))
	var selected := choice.get("selected_card_ids", []) as Array
	if not skip:
		selected.append(str(card_id))
		choice["selected_card_ids"] = selected
		choice["selected_count"] = selected.size()
		if op == &"select_bonds":
			var moved := ZoneService.move_card(
				state, card_id, StringName(choice["source_zone_id"]),
				StringName(choice["destination_zone_id"])
			)
			if not bool(moved.get("ok", false)):
				return str(moved.get("error", "bond_setup_move_failed"))
		state.effect_state = choice
		events.append({
			"type": "bond_choice_progressed", "actor_id": str(actor_id),
			"op": str(op), "selected_count": selected.size(),
			"card_instance_id": str(card_id),
		})
		if op == &"complete_bonds" or selected.size() < 5:
			return ""
	if op == &"select_bonds":
		var source := state.zones[StringName(choice["source_zone_id"])] as ZoneData
		for unused_id: StringName in source.card_instance_ids.duplicate():
			var moved := ZoneService.move_card(state, unused_id, source.zone_id, REMOVED_ID)
			if not bool(moved.get("ok", false)):
				return str(moved.get("error", "bond_setup_remove_failed"))
			(state.cards[unused_id] as Dictionary)["owner_id"] = ""
		state.effect_state.clear()
		events.append({"type": "bond_setup_completed", "actor_id": str(actor_id), "selected_count": 5})
		var index := state.turn_order.find(actor_id)
		if index + 1 < state.turn_order.size():
			_request_setup(state, state.turn_order[index + 1], events)
		return ""
	var player := state.players[actor_id] as PlayerStateData
	for raw_id: Variant in selected:
		var selected_id := StringName(str(raw_id))
		var moved := ZoneService.move_card(
			state, selected_id, StringName(player.zone_ids[&"bonds"]),
			StringName(player.zone_ids[&"completed_bonds"])
		)
		if not bool(moved.get("ok", false)):
			return str(moved.get("error", "bond_completion_move_failed"))
	state.effect_state.clear()
	events.append({
		"type": "bonds_completed", "actor_id": str(actor_id),
		"card_instance_ids": selected.duplicate(), "count": selected.size(),
	})
	if bool(choice.get("bond_combat_start_continuation", false)):
		return EffectResolver.resolve_party_trigger(
			state, actor_id, &"on_combat_start", events, definitions
		)
	return ""


static func check(
	state: GameStateData, actor_id: StringName, timing: StringName,
	context: Dictionary, events: Array[Dictionary], definitions: Dictionary
) -> void:
	check_many(state, actor_id, [timing], context, events, definitions)


static func check_many(
	state: GameStateData, actor_id: StringName, timings: Array[StringName],
	context: Dictionary, events: Array[Dictionary], definitions: Dictionary
) -> void:
	if not state.bonds_enabled or not state.effect_state.is_empty():
		return
	var player := state.players.get(actor_id) as PlayerStateData
	if player == null:
		return
	var zone := state.zones.get(player.zone_ids[&"bonds"]) as ZoneData
	var eligible: Array[String] = []
	for card_id: StringName in zone.card_instance_ids:
		var card := state.cards.get(card_id) as Dictionary
		var definition := definitions.get(StringName(card.get("definition_id", ""))) as CardDefinition
		if definition == null:
			continue
		var rule := definition.completion_rule
		if StringName(rule.get("timing", "")) in timings \
				and _matches(state, player, rule, context, definitions):
			eligible.append(str(card_id))
	if eligible.is_empty():
		return
	state.effect_state = {
		"type": "pending_choice", "op": "complete_bonds",
		"choice_id": "choice-%06d-bond-complete" % (state.revision + 1),
		"actor_id": str(state.active_player_id),
		"required_actor_id": str(actor_id),
		"source_zone_id": str(zone.zone_id),
		"destination_zone_id": str(player.zone_ids[&"completed_bonds"]),
		"eligible_card_ids": eligible, "selected_card_ids": [],
		"locked_eligible_hash": CanonicalJson.sha256(eligible),
		"selected_count": 0, "min_selections": 0,
		"max_selections": eligible.size(),
		"prompt": "可完成符合條件的羈絆；選好後確認，或全部暫不完成。",
		"timing": str(timings[0]) if not timings.is_empty() else "",
	}
	events.append({
		"type": "bond_completion_requested", "actor_id": str(actor_id),
		"choice_id": str(state.effect_state["choice_id"]),
		"private_card_ids": eligible.duplicate(),
		"timings": timings.map(func(value: StringName) -> String: return str(value)),
	})


static func record_and_check(
	state: GameStateData, old_phase: StringName, events: Array[Dictionary],
	definitions: Dictionary
) -> void:
	if not state.bonds_enabled:
		return
	var actor_id := state.active_player_id
	var player := state.players.get(actor_id) as PlayerStateData
	if player == null:
		return
	var facts := player.turn_facts
	var fact_changed := false
	var party_changed := false
	var departing_professions := {}
	for event: Dictionary in events:
		if (event.has("actor_id") and str(event.get("actor_id", "")) != str(actor_id)) \
				or (event.has("player_id") and str(event.get("player_id", "")) != str(actor_id)):
			continue
		match StringName(event.get("type", "")):
			&"card_purchased":
				var bought := _definition(state, StringName(event.get("card_instance_id", "")), definitions)
				if bought != null and bought.card_type == &"adventurer" \
						and StringName(event.get("source_row_id", "")) == SupplyService.RECRUIT_ROW_ID:
					_inc(facts, "recruited_adventurer")
					fact_changed = true
				if bought != null and bought.card_type in [&"item", &"equipment"] \
						and StringName(event.get("source_row_id", "")) == SupplyService.SHOP_ROW_ID:
					_inc(facts, "bought_resource")
					if bought.card_type == &"equipment":
						_inc(facts, "bought_equipment")
					fact_changed = true
				var hand := state.zones.get(player.zone_ids[&"hand"]) as ZoneData
				if hand != null:
					var monster_count := 0
					for hand_id: StringName in hand.card_instance_ids:
						var hand_def := _definition(state, hand_id, definitions)
						if hand_def != null and hand_def.card_type == &"monster" \
								and hand_def.purchase_power != null \
								and int(hand_def.purchase_power) > 0:
							monster_count += 1
					facts["monster_cards_used_for_purchase"] = maxi(
						int(facts.get("monster_cards_used_for_purchase", 0)), monster_count
					)
					fact_changed = true
			&"adventurer_joined_party":
				var joined := _definition(state, StringName(event.get("card_instance_id", "")), definitions)
				if joined != null and &"starter" not in joined.tags:
					var entered_ids := facts.get("nonstarter_party_entry_ids", []) as Array
					var entered_id := str(event.get("card_instance_id", ""))
					if entered_id not in entered_ids:
						entered_ids.append(entered_id)
						facts["nonstarter_party_entry_ids"] = entered_ids
						facts["nonstarter_party_entries"] = entered_ids.size()
						fact_changed = true
				party_changed = true
			&"item_used":
				_inc(facts, "items_used:%s" % state.phase)
				fact_changed = true
			&"enemy_defeated":
				facts["_bond_defeat_context"] = {
					"participant_count": (event.get("participant_ids", []) as Array).size(),
					"target_type": str(event.get("target_type", "monster")),
				}
			&"card_moved":
				var to_zone := StringName(event.get("to_zone_id", ""))
				var from_zone := StringName(event.get("from_zone_id", ""))
				var reason := StringName(event.get("reason", ""))
				if from_zone == StringName(player.zone_ids[&"party"]):
					party_changed = true
				if reason == &"draw" and old_phase != &"rest" \
						and to_zone == StringName(player.zone_ids[&"hand"]):
						_inc(facts, "extra_cards_drawn")
						fact_changed = true
				if reason in [
					&"combat_departure", &"boss_combat_departure_replaced",
					&"combat_departure_equipment", &"boss_combat_departure_replaced_equipment"
				] \
						and to_zone == StringName(player.zone_ids[&"discard_pile"]):
						var departed := _definition(state, StringName(event.get("card_instance_id", "")), definitions)
						if departed != null and from_zone == StringName(player.zone_ids[&"party"]) \
								and &"starter" not in departed.tags:
							departing_professions[_profession(departed)] = true
						if from_zone == StringName(player.zone_ids[&"equipment"]):
							var departed_ids := facts.get("combat_equipment_discarded_ids", []) as Array
							var equipment_id := str(event.get("card_instance_id", ""))
							if equipment_id not in departed_ids:
								departed_ids.append(equipment_id)
								facts["combat_equipment_discarded_ids"] = departed_ids
								facts["combat_equipment_discarded"] = departed_ids.size()
								fact_changed = true
	if not departing_professions.is_empty():
		facts["_bond_departure_context"] = {
			"nonstarter_departure_professions": departing_professions.size()
		}
	if fact_changed:
		facts["_bond_turn_fact_pending"] = true
	if party_changed:
		facts["_bond_party_state_pending"] = true
	if not state.effect_state.is_empty():
		return
	var timings: Array[StringName] = []
	var context: Dictionary = {}
	if facts.has("_bond_departure_context"):
		timings.append(&"combat_departure")
		context.merge(facts["_bond_departure_context"] as Dictionary, true)
		facts.erase("_bond_departure_context")
	if facts.has("_bond_defeat_context"):
		timings.append(&"after_defeat")
		context.merge(facts["_bond_defeat_context"] as Dictionary, true)
		facts.erase("_bond_defeat_context")
	if bool(facts.get("_bond_turn_fact_pending", false)):
		timings.append(&"turn_fact")
		facts.erase("_bond_turn_fact_pending")
	if bool(facts.get("_bond_party_state_pending", false)):
		timings.append(&"party_state")
		facts.erase("_bond_party_state_pending")
	if not timings.is_empty():
		check_many(state, actor_id, timings, context, events, definitions)


static func _inc(facts: Dictionary, key: String) -> void:
	facts[key] = int(facts.get(key, 0)) + 1


static func update_final_round(
	state: GameStateData, events: Array[Dictionary]
) -> void:
	if not state.bonds_enabled:
		return
	var reasons: Array[String] = []
	var boss_active := state.zones.get(BossService.BOSS_ACTIVE_ID) as ZoneData
	if boss_active != null and bool(boss_active.metadata.get("all_bosses_defeated", false)):
		reasons.append("all_bosses_defeated")
	for player_id: StringName in state.turn_order:
		var player := state.players[player_id] as PlayerStateData
		var completed := state.zones.get(player.zone_ids[&"completed_bonds"]) as ZoneData
		if completed != null and completed.card_instance_ids.size() >= 5:
			reasons.append("five_bonds:%s" % player_id)
	if reasons.is_empty():
		return
	if state.final_round.is_empty():
		var starting_index := state.turn_order.find(state.starting_player_id)
		var end_player := state.turn_order[
			(starting_index - 1 + state.turn_order.size()) % state.turn_order.size()
		]
		state.final_round = {
			"trigger_round": state.round_number,
			"end_player_id": str(end_player),
			"reasons": reasons,
		}
		events.append({
			"type": "final_round_started", "round": state.round_number,
			"end_player_id": str(end_player), "reasons": reasons.duplicate(),
		})
		return
	var recorded := state.final_round.get("reasons", []) as Array
	var added: Array[String] = []
	for reason: String in reasons:
		if reason not in recorded:
			recorded.append(reason)
			added.append(reason)
	state.final_round["reasons"] = recorded
	if not added.is_empty():
		events.append({
			"type": "final_round_reasons_updated", "added": added,
			"reasons": recorded.duplicate(),
		})


static func finish_if_boundary(
	state: GameStateData, outgoing_player_id: StringName,
	events: Array[Dictionary], definitions: Dictionary
) -> bool:
	if state.final_round.is_empty() or state.round_number != int(state.final_round.get("trigger_round", -1)) \
			or str(outgoing_player_id) != str(state.final_round.get("end_player_id", "")):
		return false
	state.status = &"finished"
	state.final_scores = score_all(state, definitions)
	events.append({
		"type": "game_finished", "round": state.round_number,
		"reasons": (state.final_round.get("reasons", []) as Array).duplicate(),
		"scores": state.final_scores.duplicate(true),
	})
	return true


static func score_all(state: GameStateData, definitions: Dictionary) -> Dictionary:
	var scores := {}
	for player_id: StringName in state.turn_order:
		var player := state.players[player_id] as PlayerStateData
		var honor := 0
		for zone_key: StringName in [
			&"draw_pile", &"hand", &"discard_pile", &"party", &"equipment",
			&"play_area", &"completed_bonds"
		]:
			var zone := state.zones.get(player.zone_ids[zone_key]) as ZoneData
			if zone == null:
				continue
			for card_id: StringName in zone.card_instance_ids:
				var definition := _definition(state, card_id, definitions)
				if definition != null and definition.honor != null:
					honor += int(definition.honor)
		scores[str(player_id)] = {
			"honor": honor,
			"bosses": int(player.counters.get("defeated_boss_count", 0)),
			"monsters": int(player.counters.get("defeated_monster_count", 0)),
		}
	var leaders: Array[String] = []
	var best := [-999999, -999999, -999999]
	for player_id: StringName in state.turn_order:
		var score := scores[str(player_id)] as Dictionary
		var rank := [int(score["honor"]), int(score["bosses"]), int(score["monsters"])]
		if _rank_greater(rank, best):
			best = rank
			leaders = [str(player_id)]
		elif rank == best:
			leaders.append(str(player_id))
	scores["winners"] = leaders
	return scores


static func _rank_greater(left: Array, right: Array) -> bool:
	for index in 3:
		if int(left[index]) > int(right[index]):
			return true
		if int(left[index]) < int(right[index]):
			return false
	return false


static func validate_state(state: GameStateData) -> PackedStringArray:
	var errors := PackedStringArray()
	if not state.bonds_enabled:
		return errors
	var supply := state.zones.get(SUPPLY_ID) as ZoneData
	var removed := state.zones.get(REMOVED_ID) as ZoneData
	if supply == null or supply.kind != &"ordered_deck" or supply.visibility != &"hidden":
		errors.append("Bond supply must be a hidden ordered deck")
	if removed == null or removed.kind != &"removed" or removed.visibility != &"hidden":
		errors.append("Bond removed zone must be hidden")
	var bond_count := 0
	for card_id: Variant in state.cards:
		if str(card_id).begins_with("card-bond-"):
			bond_count += 1
	if bond_count != 30:
		errors.append("Official bond instance count must remain 30")
	var allowed_zones: Array[StringName] = [SUPPLY_ID, REMOVED_ID]
	for player_id: StringName in state.turn_order:
		var player := state.players[player_id] as PlayerStateData
		if player == null:
			continue
		var candidates := state.zones.get(player.zone_ids.get(&"bond_candidates", &"")) as ZoneData
		var incomplete := state.zones.get(player.zone_ids.get(&"bonds", &"")) as ZoneData
		var completed := state.zones.get(player.zone_ids.get(&"completed_bonds", &"")) as ZoneData
		if candidates == null or incomplete == null or completed == null:
			errors.append("Player bond zones are missing")
			continue
		allowed_zones.append(candidates.zone_id)
		allowed_zones.append(incomplete.zone_id)
		allowed_zones.append(completed.zone_id)
		if candidates.card_instance_ids.size() + incomplete.card_instance_ids.size() \
				+ completed.card_instance_ids.size() > 7:
			errors.append("Player holds too many bond cards")
		if completed.card_instance_ids.size() > 5:
			errors.append("Player completed more than five bonds")
		for zone: ZoneData in [candidates, incomplete, completed]:
			for card_id: StringName in zone.card_instance_ids:
				var card := state.cards.get(card_id) as Dictionary
				if card == null or not str(card_id).begins_with("card-bond-") \
						or StringName(card.get("owner_id", "")) != player_id:
					errors.append("Player bond zone has invalid card or owner")
		if StringName(state.effect_state.get("op", "")) != &"select_bonds" \
				and (not candidates.card_instance_ids.is_empty() \
				or incomplete.card_instance_ids.size() + completed.card_instance_ids.size() != 5):
			errors.append("Player must hold exactly five chosen bonds after setup")
	for card_id: Variant in state.cards:
		if not str(card_id).begins_with("card-bond-"):
			continue
		var actual_zone := ZoneService.find_card_zone(state, StringName(str(card_id)))
		if actual_zone not in allowed_zones:
			errors.append("Bond card is outside formal bond zones")
		elif actual_zone in [SUPPLY_ID, REMOVED_ID] \
				and not str((state.cards[card_id] as Dictionary).get("owner_id", "")).is_empty():
			errors.append("Unassigned bond has a player owner")
	var choice := state.effect_state
	if StringName(choice.get("op", "")) in [&"select_bonds", &"complete_bonds"]:
		var actor_id := StringName(choice.get("required_actor_id", ""))
		var player := state.players.get(actor_id) as PlayerStateData
		if player == null:
			errors.append("Bond choice requires a valid actor")
		else:
			var setup := StringName(choice.get("op", "")) == &"select_bonds"
			var source_key := &"bond_candidates" if setup else &"bonds"
			var destination_key := &"bonds" if setup else &"completed_bonds"
			if StringName(choice.get("source_zone_id", "")) != StringName(player.zone_ids[source_key]) \
					or StringName(choice.get("destination_zone_id", "")) != StringName(player.zone_ids[destination_key]):
				errors.append("Bond choice zones do not match required actor")
			var selected := choice.get("selected_card_ids", []) as Array
			if str(choice.get("locked_eligible_hash", "")) != CanonicalJson.sha256(
				choice.get("eligible_card_ids", [])
			):
				errors.append("Bond choice candidates differ from locked set")
			if int(choice.get("selected_count", -1)) != selected.size():
				errors.append("Bond choice selected count mismatch")
			for raw_id: Variant in choice.get("eligible_card_ids", []):
				var card_id := StringName(str(raw_id))
				var expected_zone := StringName(player.zone_ids[
					destination_key if setup and str(card_id) in selected else source_key
				])
				if ZoneService.find_card_zone(state, card_id) != expected_zone:
					errors.append("Bond choice candidate moved from locked zone")
	return errors


static func _matches(
	state: GameStateData, player: PlayerStateData, rule: Dictionary,
	context: Dictionary, definitions: Dictionary
) -> bool:
	var party := state.zones.get(player.zone_ids[&"party"]) as ZoneData
	var cards := party.card_instance_ids if party != null else []
	var count := int(rule.get("count", 0))
	var op := StringName(rule.get("op", ""))
	match op:
		&"party_exact_all_tags":
			if cards.size() != count:
				return false
			for card_id: StringName in cards:
				if not _has_any(_definition(state, card_id, definitions), rule.get("tags", [])):
					return false
			return true
		&"party_exact":
			return cards.size() == count
		&"party_edge_tags":
			if cards.size() < count:
				return false
			for index in count:
				var at := cards[index] if str(rule.get("edge", "")) == "front" else cards[cards.size() - count + index]
				if not _has_any(_definition(state, at, definitions), [rule.get("tag", "")]):
					return false
			return true
		&"party_tag_count":
			var matched := 0
			for card_id: StringName in cards:
				if _has_any(_definition(state, card_id, definitions), rule.get("tags", [])):
					matched += 1
			return matched >= count
		&"party_profession_set":
			var present := {}
			var nonstarter := 0
			for card_id: StringName in cards:
				var definition := _definition(state, card_id, definitions)
				if definition == null:
					continue
				for tag: StringName in PROFESSION_TAGS:
					if tag in definition.tags:
						present[tag] = true
				if &"starter" not in definition.tags:
					nonstarter += 1
			for raw_tag: Variant in rule.get("tags", []):
				if not present.has(StringName(str(raw_tag))):
					return false
			return nonstarter >= int(rule.get("nonstarter_min", 0))
		&"party_same_profession_min", &"party_all_same_profession_min":
			var counts := {}
			for card_id: StringName in cards:
				var profession := _profession(_definition(state, card_id, definitions))
				if not profession.is_empty():
					counts[profession] = int(counts.get(profession, 0)) + 1
			if op == &"party_same_profession_min":
				for value: Variant in counts.values():
					if int(value) >= count:
						return true
				return false
			return cards.size() >= count and counts.size() == 1
		&"party_nonstarter_professions_min":
			var professions := {}
			for card_id: StringName in cards:
				var definition := _definition(state, card_id, definitions)
				if definition != null and &"starter" not in definition.tags:
					var profession := _profession(definition)
					if not profession.is_empty():
						professions[profession] = true
			return professions.size() >= count
		&"combat_participants_exact":
			return int(context.get("participant_count", -1)) == count \
				and str(context.get("target_type", "")) == str(rule.get("target_type", ""))
		&"combat_departure_professions":
			return int(context.get("nonstarter_departure_professions", 0)) >= count
		&"fact_min":
			return int(player.turn_facts.get(str(rule.get("key", "")), 0)) >= count
		&"facts_all_min":
			for raw_key: Variant in rule.get("keys", []):
				if int(player.turn_facts.get(str(raw_key), 0)) < count:
					return false
			return true
		&"action_fact_min":
			return int(player.turn_facts.get(
				"%s:%s" % [rule.get("key", ""), state.phase], 0
			)) >= count
		&"spent_purchase_min":
			return player.spent_purchase_power >= count
	return false


static func _definition(
	state: GameStateData, card_id: StringName, definitions: Dictionary
) -> CardDefinition:
	var card := state.cards.get(card_id) as Dictionary
	return definitions.get(StringName(card.get("definition_id", ""))) as CardDefinition \
		if card != null else null


static func _has_any(definition: CardDefinition, raw_tags: Array) -> bool:
	if definition == null:
		return false
	for raw_tag: Variant in raw_tags:
		if StringName(str(raw_tag)) in definition.tags:
			return true
	return false


static func _profession(definition: CardDefinition) -> StringName:
	if definition != null:
		for tag: StringName in PROFESSION_TAGS:
			if tag in definition.tags:
				return tag
	return &""
