class_name GameSession
extends RefCounted

signal state_changed(public_state: Dictionary)
signal events_committed(events: Array[Dictionary])
signal command_rejected(error_code: String)

const CONTENT_PACK_PATH := "res://content/packs/base_vertical_slice.json"
const RULESET_FINGERPRINT := "ruleset:vertical-slice:0.8.0"

var state: GameStateData
var content_registry := ContentRegistry.new()


func start_new_game(seed_value: int = 20260909) -> PackedStringArray:
	var errors := content_registry.load_pack(CONTENT_PACK_PATH)
	if not errors.is_empty():
		return errors
	state = GameStateData.create_vertical_slice(seed_value)
	errors.append_array(InvariantService.validate(state))
	if errors.is_empty():
		_emit_state_changed()
	return errors


func get_legal_commands(actor_id: StringName = &"") -> Array[Dictionary]:
	if state == null:
		return []
	var resolved_actor_id := state.active_player_id if actor_id.is_empty() else actor_id
	return RulesEngine.get_legal_commands(state, resolved_actor_id, content_registry.definitions)


func end_phase() -> Dictionary:
	if state == null:
		return {"ok": false, "error": "session_not_started", "events": []}
	var envelope := {
		"protocol_version": 1,
		"game_id": str(state.game_id),
		"command_id": "cmd-%06d" % (state.revision + 1),
		"actor_id": str(state.active_player_id),
		"expected_revision": state.revision,
		"command": {"type": "END_PHASE"},
	}
	return submit_command(envelope)


func equip_item(card_instance_id: StringName, target_card_id: StringName) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "session_not_started", "events": []}
	var envelope := {
		"protocol_version": 1,
		"game_id": str(state.game_id),
		"command_id": "cmd-%06d" % (state.revision + 1),
		"actor_id": str(state.active_player_id),
		"expected_revision": state.revision,
		"command": {
			"type": "EQUIP_ITEM",
			"card_instance_id": str(card_instance_id),
			"target_card_id": str(target_card_id),
		},
	}
	return submit_command(envelope)


func play_adventurer(card_instance_id: StringName) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "session_not_started", "events": []}
	return submit_command(_card_command_envelope(&"PLAY_ADVENTURER", card_instance_id))


func use_item(card_instance_id: StringName) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "session_not_started", "events": []}
	return submit_command(_card_command_envelope(&"USE_ITEM", card_instance_id))


func buy_card(card_instance_id: StringName, source_row_id: StringName) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "session_not_started", "events": []}
	var envelope := {
		"protocol_version": 1,
		"game_id": str(state.game_id),
		"command_id": "cmd-%06d" % (state.revision + 1),
		"actor_id": str(state.active_player_id),
		"expected_revision": state.revision,
		"command": {
			"type": "BUY_CARD",
			"card_instance_id": str(card_instance_id),
			"source_row_id": str(source_row_id),
		},
	}
	return submit_command(envelope)


func attack_target(target_card_id: StringName, claim_optional_reward: bool) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "session_not_started", "events": []}
	var envelope := {
		"protocol_version": 1,
		"game_id": str(state.game_id),
		"command_id": "cmd-%06d" % (state.revision + 1),
		"actor_id": str(state.active_player_id),
		"expected_revision": state.revision,
		"command": {
			"type": "ATTACK_TARGET",
			"target_card_id": str(target_card_id),
			"claim_optional_reward": claim_optional_reward,
		},
	}
	return submit_command(envelope)


func resolve_choice(choice_id: String, card_instance_id: StringName, skip: bool) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "session_not_started", "events": []}
	var envelope := {
		"protocol_version": 1,
		"game_id": str(state.game_id),
		"command_id": "cmd-%06d" % (state.revision + 1),
		"actor_id": str(state.active_player_id),
		"expected_revision": state.revision,
		"command": {
			"type": "RESOLVE_CHOICE",
			"choice_id": choice_id,
			"card_instance_id": str(card_instance_id),
			"skip": skip,
		},
	}
	return submit_command(envelope)


func refresh_market(
	discard_card_id: StringName,
	row_id: StringName,
	card_instance_ids: Array[StringName]
) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "session_not_started", "events": []}
	var selected_ids: Array[String] = []
	for card_instance_id: StringName in card_instance_ids:
		selected_ids.append(str(card_instance_id))
	var envelope := {
		"protocol_version": 1,
		"game_id": str(state.game_id),
		"command_id": "cmd-%06d" % (state.revision + 1),
		"actor_id": str(state.active_player_id),
		"expected_revision": state.revision,
		"command": {
			"type": "REFRESH_MARKET",
			"discard_card_id": str(discard_card_id),
			"row_id": str(row_id),
			"card_instance_ids": selected_ids,
		},
	}
	return submit_command(envelope)


func _card_command_envelope(command_type: StringName, card_instance_id: StringName) -> Dictionary:
	return {
		"protocol_version": 1,
		"game_id": str(state.game_id),
		"command_id": "cmd-%06d" % (state.revision + 1),
		"actor_id": str(state.active_player_id),
		"expected_revision": state.revision,
		"command": {
			"type": str(command_type),
			"card_instance_id": str(card_instance_id),
		},
	}


func submit_command(envelope: Dictionary) -> Dictionary:
	if state == null:
		var result := {"ok": false, "error": "session_not_started", "events": []}
		command_rejected.emit(result["error"])
		return result
	var result := RulesEngine.dispatch(state, envelope, content_registry.definitions)
	if not bool(result.get("ok", false)):
		command_rejected.emit(str(result.get("error", "unknown_error")))
		return result
	state = result["state"] as GameStateData
	_emit_state_changed()
	events_committed.emit(result["events"])
	return result


func snapshot() -> Dictionary:
	if state == null:
		return {}
	return {
		"snapshot_schema_version": 1,
		"app_version": "0.8.0",
		"content_fingerprint": content_registry.pack_fingerprint,
		"ruleset_fingerprint": RULESET_FINGERPRINT,
		"state": state.to_dictionary(),
		"state_hash": CanonicalJson.sha256(state.to_dictionary()),
	}


func _emit_state_changed() -> void:
	var public_state := state.to_dictionary()
	public_state["definitions"] = content_registry.to_public_dictionary()
	public_state["legal_commands"] = get_legal_commands()
	public_state["active_resources"] = ResourceService.evaluate_player(
		state,
		state.active_player_id,
		content_registry.definitions
	)
	state_changed.emit(public_state)
