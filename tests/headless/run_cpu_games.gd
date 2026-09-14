extends SceneTree

const SEEDS: Array[int] = [
	21001, 21002, 21003, 21004, 21005,
	21006, 21007, 21008, 21009, 21010,
	21011, 21012, 21013, 21014, 21015,
	21016, 21017, 21018, 21019, 21020,
]


func _init() -> void:
	var requested := 20
	var selected_seed := -1
	var verbose := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			requested = clampi(int(arg.get_slice("=", 1)), 1, SEEDS.size())
		if arg.begins_with("--seed="):
			selected_seed = int(arg.get_slice("=", 1))
		if arg == "--verbose":
			verbose = true
	var failures: Array[String] = []
	var selected: Array[int] = []
	if selected_seed >= 0:
		selected.append(selected_seed)
	else:
		selected.assign(SEEDS.slice(0, requested))
	for seed: int in selected:
		var outcome := _run_seed(seed, verbose)
		if not bool(outcome.get("ok", false)):
			failures.append("seed %d: %s" % [seed, outcome.get("error", "unknown")])
			_save_failure_trace(seed, outcome)
			printerr(failures.back())
		else:
			print("PASS CPU seed %d: %d rounds, %d commands" % [
				seed, outcome.get("rounds", 0), outcome.get("commands", 0)
			])
	if failures.is_empty():
		print("PASS: %d four-player complete games" % selected.size())
		quit(0)
	else:
		quit(1)


func _run_seed(seed: int, verbose: bool = false) -> Dictionary:
	var session := GameSession.new()
	var errors := session.start_new_game(seed, true, true, 4)
	if not errors.is_empty():
		return {"ok": false, "error": "; ".join(errors), "trace": []}
	var controller := CpuSessionOrchestrator.new()
	var total_steps := 0
	var last_trace: Array[Dictionary] = []
	var recorded: Array[Dictionary] = []
	while total_steps < 64000:
		var outcome := controller.advance(session, &"p1", true, 256)
		var trace: Array[Dictionary] = []
		trace.assign(outcome.get("trace", []))
		total_steps += int(outcome.get("steps", 0))
		last_trace = trace.slice(maxi(0, trace.size() - 16))
		if seed == SEEDS[0]:
			recorded.append_array(trace)
		var public_view := session.get_public_view()
		if verbose and total_steps % 1024 == 0:
			var public_zones := public_view.get("zones", {}) as Dictionary
			var boss_deck := public_zones.get(str(BossService.BOSS_DECK_ID), {}) as Dictionary
			var boss_left := int(boss_deck.get("card_count", (boss_deck.get(
				"card_instance_ids", []) as Array).size()))
			var defeated: Array[int] = []
			var boss_zone := session.state.zones[BossService.BOSS_ACTIVE_ID] as ZoneData
			var boss_id := boss_zone.card_instance_ids[0] if not boss_zone.card_instance_ids.is_empty() else &""
			var boss_definition := str((session.state.cards.get(boss_id, {}) as Dictionary).get(
				"definition_id", ""))
			var gaps: Array[int] = []
			for player_id: StringName in [&"p1", &"p2", &"p3", &"p4"]:
				var player := (public_view.get("players", {}) as Dictionary).get(str(player_id), {}) as Dictionary
				defeated.append(int((player.get("counters", {}) as Dictionary).get(
					"defeated_boss_count", 0)))
				gaps.append(int(CombatService.preview_attack(session.state, player_id, boss_id,
					session.content_registry.definitions).get("gap", -1)) if not str(boss_id).is_empty() else -1)
			print("CPU seed %d: round %d, %d commands, bosses left %d, defeated %s, boss %s, gaps %s" % [
				seed, public_view.get("round", 0), total_steps, boss_left, str(defeated),
				boss_definition, str(gaps)
			])
		if int(public_view.get("round", 0)) > 250:
			return {"ok": false, "error": "round_limit_exceeded", "trace": last_trace}
		if not bool(outcome.get("ok", false)):
			return {"ok": false, "error": outcome.get("error", "unknown"), "trace": last_trace}
		if outcome.get("status", "") == "finished":
			var final_scores := public_view.get("final_scores", {}) as Dictionary
			if not final_scores.has("winners") or (final_scores["winners"] as Array).is_empty() \
					or not final_scores.has("p1") or not final_scores.has("p2") \
					or not final_scores.has("p3") or not final_scores.has("p4"):
				return {"ok": false, "error": "incomplete_four_player_scores", "trace": last_trace}
			if seed == SEEDS[0] and not _verify_replay(seed, recorded, session.get_state_hash()):
				return {"ok": false, "error": "replay_final_hash_mismatch", "trace": last_trace}
			return {"ok": true, "rounds": public_view.get("round", 0),
				"commands": total_steps, "final_hash": session.get_state_hash()}
		if int(outcome.get("steps", 0)) == 0:
			return {"ok": false, "error": "zero_step_yield", "trace": last_trace}
	return {"ok": false, "error": "command_limit_exceeded", "trace": last_trace}


func _verify_replay(seed: int, recorded: Array[Dictionary], expected_hash: String) -> bool:
	var replay := GameSession.new()
	if not replay.start_new_game(seed, true, true, 4).is_empty():
		return false
	for entry: Dictionary in recorded:
		var view := replay.get_public_view()
		var revision := int(view.get("revision", -1))
		var result := replay.submit_command({
			"protocol_version": 1, "game_id": str(view.get("game_id", "")),
			"command_id": "cpu-%06d" % (revision + 1),
			"actor_id": str(entry.get("actor_id", "")),
			"expected_revision": revision,
			"command": entry.get("command", {}),
		})
		if not bool(result.get("ok", false)) or str(result.get("after_hash", "")) \
				!= str(entry.get("after_hash", "")):
			return false
	return replay.get_state_hash() == expected_hash


func _save_failure_trace(seed: int, outcome: Dictionary) -> void:
	var directory := ProjectSettings.globalize_path("res://builds/cpu-traces")
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open("%s/seed-%d.json" % [directory, seed], FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(outcome, "  "))
