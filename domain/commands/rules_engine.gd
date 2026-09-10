class_name RulesEngine
extends RefCounted

const PHASES: Array[StringName] = [&"action1", &"combat", &"action2", &"purchase", &"rest"]


static func get_legal_commands(
	state: GameStateData,
	actor_id: StringName,
	definitions: Dictionary = {}
) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	if not InvariantService.validate(state).is_empty():
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
	var state_errors := InvariantService.validate(state)
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
			error = _apply_end_phase(draft, events)
		&"EQUIP_ITEM":
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

	var invariant_errors := InvariantService.validate(draft)
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


static func _apply_end_phase(state: GameStateData, events: Array[Dictionary]) -> String:
	var old_phase := state.phase
	var old_player_id := state.active_player_id
	var phase_index := PHASES.find(state.phase)
	if phase_index == PHASES.size() - 1:
		var supply_error := SupplyService.refill_vertical_slice_rows(state, events)
		if not supply_error.is_empty():
			return supply_error
		var outgoing_player := state.players[old_player_id] as PlayerStateData
		outgoing_player.reset_turn_scope()
		events.append({"type": "turn_resources_reset", "player_id": str(old_player_id)})
		var rest_error := DeckService.restock_hand(state, old_player_id, 5, events)
		if not rest_error.is_empty():
			return rest_error
		state.phase = PHASES[0]
		var player_index := state.turn_order.find(state.active_player_id)
		state.active_player_id = state.turn_order[(player_index + 1) % state.turn_order.size()]
		var next_player := state.players[state.active_player_id] as PlayerStateData
		next_player.reset_turn_scope()
		if state.active_player_id == state.starting_player_id:
			state.round_number += 1
	else:
		state.phase = PHASES[phase_index + 1]
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
	return ""


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
