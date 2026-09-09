class_name RulesEngine
extends RefCounted

const PHASES: Array[StringName] = [&"action1", &"combat", &"action2", &"purchase", &"rest"]


static func get_legal_commands(state: GameStateData, actor_id: StringName) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	if state.status != &"active":
		return commands
	if actor_id != state.active_player_id:
		return commands
	if not state.effect_state.is_empty():
		return commands
	commands.append({
		"type": "END_PHASE",
		"actor_id": str(actor_id),
		"expected_revision": state.revision,
	})
	return commands


static func dispatch(state: GameStateData, envelope: Dictionary) -> Dictionary:
	var before_hash := CanonicalJson.sha256(state.to_dictionary())
	var state_errors := InvariantService.validate(state)
	if not state_errors.is_empty():
		return _failure("invalid_state: %s" % "; ".join(state_errors), before_hash)
	var error := _validate_envelope(state, envelope)
	if not error.is_empty():
		return _failure(error, before_hash)

	var command: Dictionary = envelope.get("command", {})
	error = _validate_command(state, command)
	if not error.is_empty():
		return _failure(error, before_hash)
	var draft := state.clone_state()
	var events: Array[Dictionary] = []
	match StringName(command.get("type", "")):
		&"END_PHASE":
			_apply_end_phase(draft, events)
		_:
			return _failure("unsupported_command", before_hash)

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
	if StringName(envelope.get("actor_id", "")) != state.active_player_id:
		return "wrong_actor"
	if not envelope.get("command", {}) is Dictionary:
		return "invalid_payload"
	return ""


static func _validate_command(state: GameStateData, command: Dictionary) -> String:
	if state.status != &"active":
		return "game_not_active"
	if not state.effect_state.is_empty():
		return "effects_pending"
	if StringName(command.get("type", "")) != &"END_PHASE":
		return "unsupported_command"
	return ""


static func _apply_end_phase(state: GameStateData, events: Array[Dictionary]) -> void:
	var old_phase := state.phase
	var phase_index := PHASES.find(state.phase)
	if phase_index == PHASES.size() - 1:
		state.phase = PHASES[0]
		state.round_number += 1
	else:
		state.phase = PHASES[phase_index + 1]
	events.append({
		"type": "phase_changed",
		"actor_id": str(state.active_player_id),
		"from_phase": str(old_phase),
		"to_phase": str(state.phase),
		"round": state.round_number,
	})


static func _failure(code: String, state_hash: String) -> Dictionary:
	return {
		"ok": false,
		"error": code,
		"events": [],
		"before_hash": state_hash,
		"after_hash": state_hash,
	}
