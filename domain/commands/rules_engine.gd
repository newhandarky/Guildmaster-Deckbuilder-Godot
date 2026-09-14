class_name RulesEngine
extends RefCounted

const PHASES: Array[StringName] = [&"action1", &"combat", &"action2", &"purchase", &"rest"]


static func get_legal_commands(
	state: GameStateData,
	actor_id: StringName,
	definitions: Dictionary = {}
) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	if not InvariantService.validate(state, definitions).is_empty():
		return commands
	if state.status != &"active":
		return commands
	if not state.effect_state.is_empty():
		if actor_id != _required_choice_actor(state.effect_state):
			return commands
		return ChoiceService.get_legal_commands(state, actor_id)
	if actor_id != state.active_player_id:
		return commands
	commands.append({
		"type": "END_PHASE",
		"actor_id": str(actor_id),
		"expected_revision": state.revision,
	})
	commands.append_array(EquipmentService.get_legal_commands(state, actor_id, definitions))
	commands.append_array(PartyService.get_legal_commands(state, actor_id, definitions))
	commands.append_array(ItemService.get_legal_commands(state, actor_id, definitions))
	commands.append_array(CombatService.get_legal_commands(state, actor_id, definitions))
	commands.append_array(PurchaseService.get_legal_commands(state, actor_id, definitions))
	commands.append_array(MarketRefreshService.get_legal_commands(state, actor_id))
	return commands


static func dispatch(
	state: GameStateData,
	envelope: Dictionary,
	definitions: Dictionary = {}
) -> Dictionary:
	var before_hash := CanonicalJson.sha256(state.to_dictionary())
	var state_errors := InvariantService.validate(state, definitions)
	if not state_errors.is_empty():
		return _failure("invalid_state: %s" % "; ".join(state_errors), before_hash)
	var error := _validate_envelope(state, envelope)
	if not error.is_empty():
		return _failure(error, before_hash)

	var command: Dictionary = envelope.get("command", {})
	var actor_id := StringName(envelope.get("actor_id", ""))
	error = _validate_command(state, actor_id, command, definitions)
	if not error.is_empty():
		return _failure(error, before_hash)
	var draft := state.clone_state()
	var events: Array[Dictionary] = []
	match StringName(command.get("type", "")):
		&"END_PHASE":
			error = _apply_end_phase(draft, events, definitions)
		&"EQUIP_ITEM":
			error = EquipmentService.apply(draft, actor_id, command, definitions, events)
		&"ACTIVATE_EQUIPMENT_EFFECT":
			error = EquipmentService.apply(draft, actor_id, command, definitions, events)
		&"PLAY_ADVENTURER":
			error = PartyService.apply(draft, actor_id, command, definitions, events)
		&"USE_ITEM":
			error = ItemService.apply(draft, actor_id, command, definitions, events)
		&"ATTACK_TARGET":
			error = CombatService.apply(draft, actor_id, command, definitions, events)
		&"BUY_CARD":
			error = PurchaseService.apply(draft, actor_id, command, definitions, events)
		&"REFRESH_MARKET":
			error = MarketRefreshService.apply(draft, actor_id, command, events)
		&"RESOLVE_CHOICE":
			error = ChoiceService.apply(draft, actor_id, command, events, definitions)
		_:
			return _failure("unsupported_command", before_hash)
	if not error.is_empty():
		return _failure(error, before_hash)
	BondService.record_and_check(draft, state.phase, events, definitions)
	BondService.update_final_round(draft, events)

	var invariant_errors := InvariantService.validate(draft, definitions)
	if not invariant_errors.is_empty():
		return _failure("invariant_failure: %s" % "; ".join(invariant_errors), before_hash)

	draft.processed_command_ids.append(str(envelope.get("command_id", "")))
	draft.revision += 1
	for event: Dictionary in events:
		draft.event_cursor += 1
		event["sequence"] = draft.event_cursor
		event["revision"] = draft.revision
	return {
		"ok": true,
		"state": draft,
		"events": events,
		"before_hash": before_hash,
		"after_hash": CanonicalJson.sha256(draft.to_dictionary()),
	}


static func _validate_envelope(state: GameStateData, envelope: Dictionary) -> String:
	if int(envelope.get("protocol_version", 0)) != 1:
		return "unsupported_protocol"
	if StringName(envelope.get("game_id", "")) != state.game_id:
		return "wrong_game"
	var command_id := str(envelope.get("command_id", ""))
	if command_id.is_empty():
		return "missing_command_id"
	if command_id in state.processed_command_ids:
		return "duplicate_command"
	if int(envelope.get("expected_revision", -1)) != state.revision:
		return "stale_revision"
	var actor_id := StringName(envelope.get("actor_id", ""))
	var allowed_actor_id := (
		_required_choice_actor(state.effect_state)
		if not state.effect_state.is_empty()
		else state.active_player_id
	)
	if actor_id != allowed_actor_id:
		return "wrong_actor"
	if not envelope.get("command", {}) is Dictionary:
		return "invalid_payload"
	return ""


static func _validate_command(
	state: GameStateData,
	actor_id: StringName,
	command: Dictionary,
	definitions: Dictionary
) -> String:
	if state.status != &"active":
		return "game_not_active"
	if not state.effect_state.is_empty():
		if StringName(command.get("type", "")) == &"RESOLVE_CHOICE":
			return ChoiceService.validate(state, actor_id, command, definitions)
		return "effects_pending"
	match StringName(command.get("type", "")):
		&"END_PHASE":
			return ""
		&"EQUIP_ITEM":
			return EquipmentService.validate(state, actor_id, command, definitions)
		&"ACTIVATE_EQUIPMENT_EFFECT":
			return EquipmentService.validate(state, actor_id, command, definitions)
		&"PLAY_ADVENTURER":
			return PartyService.validate(state, actor_id, command, definitions)
		&"USE_ITEM":
			return ItemService.validate(state, actor_id, command, definitions)
		&"ATTACK_TARGET":
			return CombatService.validate(state, actor_id, command, definitions)
		&"BUY_CARD":
			return PurchaseService.validate(state, actor_id, command, definitions)
		&"REFRESH_MARKET":
			return MarketRefreshService.validate(state, actor_id, command)
		&"RESOLVE_CHOICE":
			return "no_pending_choice"
		_:
			return "unsupported_command"


static func _apply_end_phase(
	state: GameStateData, events: Array[Dictionary], definitions: Dictionary
) -> String:
	var old_phase := state.phase
	var old_player_id := state.active_player_id
	var phase_index := PHASES.find(state.phase)
	if phase_index == PHASES.size() - 1:
		var supply_error := SupplyService.refill_vertical_slice_rows(state, events, definitions)
		if not supply_error.is_empty():
			return supply_error
		var cleanup_error := DeckService.discard_hand_and_play_area(state, old_player_id, events)
		if not cleanup_error.is_empty():
			return cleanup_error
		var helper_error := HelperService.trigger(state, old_player_id, &"on_rest_before_draw", events, definitions)
		if not helper_error.is_empty():
			return helper_error
		if not state.effect_state.is_empty():
			state.effect_state["helper_rest_boundary"] = true
			return ""
		return finish_rest_phase(state, events, definitions)
	else:
		state.phase = PHASES[phase_index + 1]
		if old_phase == &"action1":
			var phase_player := state.players.get(old_player_id) as PlayerStateData
			if phase_player != null and bool(phase_player.turn_facts.get("skip_combat", false)):
				state.phase = &"action2"
	events.append({
		"type": "phase_changed",
		"actor_id": str(old_player_id),
		"from_phase": str(old_phase),
		"to_phase": str(state.phase),
		"round": state.round_number,
	})
	if old_player_id != state.active_player_id:
		events.append({
			"type": "active_player_changed",
			"from_player_id": str(old_player_id),
			"to_player_id": str(state.active_player_id),
			"round": state.round_number,
		})
		if state.active_player_id == state.starting_player_id:
			events.append({"type": "round_started", "round": state.round_number})
	var trigger_timing := &""
	if old_phase == &"action1" and state.phase == &"combat":
		trigger_timing = &"on_combat_start"
	elif old_phase == &"combat" and state.phase == &"action2":
		trigger_timing = &"on_combat_end"
	elif old_phase == &"action2" and state.phase == &"purchase":
		trigger_timing = &"on_purchase_start"
	if not trigger_timing.is_empty():
		if trigger_timing == &"on_combat_start" and state.bonds_enabled:
			BondService.check(state, old_player_id, &"combat_start", {}, events, definitions)
			if not state.effect_state.is_empty():
				state.effect_state["bond_combat_start_continuation"] = true
				return ""
		var trigger_error := EffectResolver.resolve_party_trigger(
			state, old_player_id, trigger_timing, events, definitions
		)
		if not trigger_error.is_empty():
			return trigger_error
		if trigger_timing == &"on_purchase_start":
			if not state.effect_state.is_empty():
				state.effect_state["helper_purchase_boundary"] = true
				return ""
			return HelperService.trigger(state, old_player_id, trigger_timing, events, definitions)
	return ""


static func finish_rest_phase(
	state: GameStateData, events: Array[Dictionary], definitions: Dictionary
) -> String:
	if state.phase != &"rest" or not state.effect_state.is_empty():
		return "invalid_rest_boundary"
	var old_player_id := state.active_player_id
	var outgoing_player := state.players[old_player_id] as PlayerStateData
	var hand_size := HelperService.rule_amount(state, definitions, &"rest_hand_size", 5)
	var draw_result := DeckService.draw_cards(state, old_player_id, hand_size, events)
	if not bool(draw_result.get("ok", false)):
		return str(draw_result.get("error", "draw_failed"))
	events.append({"type":"hand_restocked","player_id":str(old_player_id),"requested_count":hand_size,"drawn_count":int(draw_result.get("drawn_count", 0))})
	outgoing_player.reset_turn_scope()
	events.append({"type":"turn_resources_reset","player_id":str(old_player_id)})
	if BondService.finish_if_boundary(state, old_player_id, events, definitions):
		return ""
	state.phase = &"action1"
	var player_index := state.turn_order.find(old_player_id)
	state.active_player_id = state.turn_order[(player_index + 1) % state.turn_order.size()]
	var next_player := state.players[state.active_player_id] as PlayerStateData
	next_player.reset_turn_scope()
	if state.active_player_id == state.starting_player_id:
		state.round_number += 1
	events.append({"type":"phase_changed","actor_id":str(old_player_id),"from_phase":"rest","to_phase":"action1","round":state.round_number})
	events.append({"type":"active_player_changed","from_player_id":str(old_player_id),"to_player_id":str(state.active_player_id),"round":state.round_number})
	if state.active_player_id == state.starting_player_id:
		events.append({"type":"round_started","round":state.round_number})
	return HelperService.trigger(state, state.active_player_id, &"on_turn_start", events, definitions)


static func _failure(code: String, state_hash: String) -> Dictionary:
	return {
		"ok": false,
		"error": code,
		"events": [],
		"before_hash": state_hash,
		"after_hash": state_hash,
	}


static func _required_choice_actor(choice: Dictionary) -> StringName:
	return StringName(choice.get("required_actor_id", choice.get("actor_id", "")))
