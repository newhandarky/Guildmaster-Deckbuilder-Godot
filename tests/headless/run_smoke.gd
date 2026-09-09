extends SceneTree

var _failures: PackedStringArray = []


func _init() -> void:
	_run()
	if _failures.is_empty():
		print("PASS: Guildmaster vertical-slice smoke suite")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("FAIL: %s" % failure)
		quit(1)


func _run() -> void:
	_test_content_pack()
	_test_content_pack_reload()
	_test_initial_invariants()
	_test_legal_command_and_dispatch()
	_test_command_legality_guards()
	_test_duplicate_command_guard()
	_test_twenty_blank_rounds()
	_test_stale_command_rollback()
	_test_snapshot_round_trip()
	_test_snapshot_rejection_paths()
	_test_seeded_rng()
	_test_rng_state_restore()


func _test_content_pack() -> void:
	var registry := ContentRegistry.new()
	var errors := registry.load_pack("res://content/packs/base_vertical_slice.json")
	_expect(errors.is_empty(), "base content pack should validate: %s" % "; ".join(errors))
	_expect(registry.definitions.size() == 3, "vertical slice should load three definitions")
	_expect(not registry.definitions.has(&"custom:adventurer/melee-01"), "custom adventurers must stay disabled")
	_expect(not registry.pack_fingerprint.is_empty(), "content pack should expose a deterministic fingerprint")


func _test_content_pack_reload() -> void:
	var registry := ContentRegistry.new()
	var first_errors := registry.load_pack("res://content/packs/base_vertical_slice.json")
	var first_fingerprint := registry.pack_fingerprint
	var second_errors := registry.load_pack("res://content/packs/base_vertical_slice.json")
	_expect(first_errors.is_empty() and second_errors.is_empty(), "content pack should be safely reloadable")
	_expect(registry.definitions.size() == 3, "content reload must not retain duplicate definitions")
	_expect(registry.pack_fingerprint == first_fingerprint, "same content should keep the same fingerprint")


func _test_initial_invariants() -> void:
	var state := GameStateData.create_vertical_slice()
	var errors := InvariantService.validate(state)
	_expect(errors.is_empty(), "initial state should satisfy invariants: %s" % "; ".join(errors))


func _test_legal_command_and_dispatch() -> void:
	var state := GameStateData.create_vertical_slice()
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
	var inactive := GameStateData.create_vertical_slice()
	inactive.status = &"finished"
	_expect(RulesEngine.get_legal_commands(inactive, &"p1").is_empty(), "finished game should expose no commands")
	var inactive_result := RulesEngine.dispatch(inactive, _end_phase_envelope(inactive, "cmd-inactive"))
	_expect(str(inactive_result.get("error", "")) == "game_not_active", "dispatcher must reject commands after game end")

	var pending := GameStateData.create_vertical_slice()
	pending.effect_state = {"pending_choice": "test"}
	_expect(RulesEngine.get_legal_commands(pending, &"p1").is_empty(), "pending effect should expose no END_PHASE")
	var pending_result := RulesEngine.dispatch(pending, _end_phase_envelope(pending, "cmd-pending"))
	_expect(str(pending_result.get("error", "")) == "effects_pending", "dispatcher must enforce pending-effect legality")


func _test_duplicate_command_guard() -> void:
	var state := GameStateData.create_vertical_slice()
	var first := RulesEngine.dispatch(state, _end_phase_envelope(state, "cmd-duplicate"))
	_expect(bool(first.get("ok", false)), "first command submission should succeed")
	if bool(first.get("ok", false)):
		var next_state := first["state"] as GameStateData
		var duplicate_envelope := _end_phase_envelope(next_state, "cmd-duplicate")
		var duplicate := RulesEngine.dispatch(next_state, duplicate_envelope)
		_expect(str(duplicate.get("error", "")) == "duplicate_command", "duplicate command ID must be rejected")


func _test_twenty_blank_rounds() -> void:
	var state := GameStateData.create_vertical_slice()
	for index in 100:
		var result := RulesEngine.dispatch(state, _end_phase_envelope(state, "cmd-round-%03d" % index))
		_expect(bool(result.get("ok", false)), "blank-round command %d should succeed" % index)
		if not bool(result.get("ok", false)):
			return
		state = result["state"] as GameStateData
	_expect(state.round_number == 21, "100 phase transitions should complete 20 blank rounds")
	_expect(state.revision == 100, "each blank phase transition should commit one revision")


func _test_stale_command_rollback() -> void:
	var state := GameStateData.create_vertical_slice()
	var before_hash := CanonicalJson.sha256(state.to_dictionary())
	var envelope := _end_phase_envelope(state)
	envelope["expected_revision"] = 99
	var result := RulesEngine.dispatch(state, envelope)
	_expect(not bool(result.get("ok", true)), "stale command should fail")
	_expect(str(result.get("error", "")) == "stale_revision", "stale command should return stable error code")
	_expect(CanonicalJson.sha256(state.to_dictionary()) == before_hash, "failed command must not mutate state")
	_expect(result.get("before_hash") == result.get("after_hash"), "failed command must preserve hash")


func _test_snapshot_round_trip() -> void:
	var state := GameStateData.create_vertical_slice()
	var encoded := SnapshotCodec.encode(state, "content:test", "rules:test")
	var decoded := SnapshotCodec.decode(encoded)
	_expect(bool(decoded.get("ok", false)), "snapshot should decode: %s" % decoded)
	if bool(decoded.get("ok", false)):
		var restored := decoded["state"] as GameStateData
		_expect(
			CanonicalJson.sha256(restored.to_dictionary()) == CanonicalJson.sha256(state.to_dictionary()),
			"snapshot round trip should preserve state hash"
		)


func _test_snapshot_rejection_paths() -> void:
	var state := GameStateData.create_vertical_slice()
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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
