class_name SnapshotCodec
extends RefCounted


static func encode(state: GameStateData, content_fingerprint: String, ruleset_fingerprint: String) -> String:
	if not InvariantService.validate(state).is_empty():
		return ""
	var state_data := state.to_dictionary()
	return CanonicalJson.stringify({
		"snapshot_schema_version": 1,
		"app_version": "0.18.0",
		"content_fingerprint": content_fingerprint,
		"ruleset_fingerprint": ruleset_fingerprint,
		"state": state_data,
		"state_hash": CanonicalJson.sha256(state_data),
	})


static func decode(
	serialized: String,
	expected_content_fingerprint: String = "",
	expected_ruleset_fingerprint: String = ""
) -> Dictionary:
	var parsed: Variant = JSON.parse_string(serialized)
	if not parsed is Dictionary:
		return {"ok": false, "error": "invalid_json"}
	var snapshot := parsed as Dictionary
	if int(snapshot.get("snapshot_schema_version", 0)) != 1:
		return {"ok": false, "error": "unsupported_schema"}
	if not expected_content_fingerprint.is_empty() \
			and str(snapshot.get("content_fingerprint", "")) != expected_content_fingerprint:
		return {"ok": false, "error": "content_fingerprint_mismatch"}
	if not expected_ruleset_fingerprint.is_empty() \
			and str(snapshot.get("ruleset_fingerprint", "")) != expected_ruleset_fingerprint:
		return {"ok": false, "error": "ruleset_fingerprint_mismatch"}
	if not snapshot.get("state", {}) is Dictionary:
		return {"ok": false, "error": "invalid_state"}
	var state_data := snapshot["state"] as Dictionary
	var shape_error := _validate_state_shape(state_data)
	if not shape_error.is_empty():
		return {"ok": false, "error": "invalid_state", "details": shape_error}
	var state := GameStateData.from_dictionary(state_data)
	if CanonicalJson.sha256(state.to_dictionary()) != str(snapshot.get("state_hash", "")):
		return {"ok": false, "error": "state_hash_mismatch"}
	var errors := InvariantService.validate(state)
	if not errors.is_empty():
		return {"ok": false, "error": "invariant_failure", "details": errors}
	return {"ok": true, "state": state}


static func _validate_state_shape(state_data: Dictionary) -> String:
	if not state_data.get("cards", {}) is Dictionary:
		return "cards must be a Dictionary"
	if not state_data.get("zones", {}) is Dictionary:
		return "zones must be a Dictionary"
	if not state_data.get("players", {}) is Dictionary:
		return "players must be a Dictionary"
	if not state_data.get("turn_order", []) is Array:
		return "turn_order must be an Array"
	if not state_data.get("effect_state", {}) is Dictionary:
		return "effect_state must be a Dictionary"
	if not state_data.get("processed_command_ids", []) is Array:
		return "processed_command_ids must be an Array"
	for card: Variant in (state_data.get("cards", {}) as Dictionary).values():
		if not card is Dictionary:
			return "every card must be a Dictionary"
	for player: Variant in (state_data.get("players", {}) as Dictionary).values():
		if not player is Dictionary:
			return "every player must be a Dictionary"
		var player_data := player as Dictionary
		for field_name: String in ["zone_ids", "turn_resources", "turn_bonuses", "counters", "module_state", "turn_facts"]:
			if not player_data.get(field_name, {}) is Dictionary:
				return "player %s must be a Dictionary" % field_name
	for zone: Variant in (state_data.get("zones", {}) as Dictionary).values():
		if not zone is Dictionary:
			return "every zone must be a Dictionary"
		var zone_data := zone as Dictionary
		if not zone_data.get("card_instance_ids", []) is Array:
			return "zone card_instance_ids must be an Array"
		if not zone_data.get("metadata", {}) is Dictionary:
			return "zone metadata must be a Dictionary"
	return ""
