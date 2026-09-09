class_name GameSession
extends RefCounted

signal state_changed(public_state: Dictionary)
signal events_committed(events: Array[Dictionary])
signal command_rejected(error_code: String)

const CONTENT_PACK_PATH := "res://content/packs/base_vertical_slice.json"

var state: GameStateData
var content_registry := ContentRegistry.new()


func start_new_game(seed_value: int = 20260909) -> PackedStringArray:
	var errors := content_registry.load_pack(CONTENT_PACK_PATH)
	if not errors.is_empty():
		return errors
	state = GameStateData.create_vertical_slice(seed_value)
	errors.append_array(InvariantService.validate(state))
	if errors.is_empty():
		state_changed.emit(state.to_dictionary())
	return errors


func get_legal_commands(actor_id: StringName = &"") -> Array[Dictionary]:
	if state == null:
		return []
	var resolved_actor_id := state.active_player_id if actor_id.is_empty() else actor_id
	return RulesEngine.get_legal_commands(state, resolved_actor_id)


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


func submit_command(envelope: Dictionary) -> Dictionary:
	if state == null:
		var result := {"ok": false, "error": "session_not_started", "events": []}
		command_rejected.emit(result["error"])
		return result
	var result := RulesEngine.dispatch(state, envelope)
	if not bool(result.get("ok", false)):
		command_rejected.emit(str(result.get("error", "unknown_error")))
		return result
	state = result["state"] as GameStateData
	state_changed.emit(state.to_dictionary())
	events_committed.emit(result["events"])
	return result


func snapshot() -> Dictionary:
	if state == null:
		return {}
	return {
		"snapshot_schema_version": 1,
		"app_version": "0.2.0",
		"content_fingerprint": content_registry.pack_fingerprint,
		"ruleset_fingerprint": "ruleset:vertical-slice:0.2.0",
		"state": state.to_dictionary(),
		"state_hash": CanonicalJson.sha256(state.to_dictionary()),
	}
