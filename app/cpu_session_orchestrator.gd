class_name CpuSessionOrchestrator
extends RefCounted

const MAX_AUTONOMOUS_STEPS := CpuProgressGuard.MAX_AUTONOMOUS_STEPS

var _progress_guard := CpuProgressGuard.new()
var _game_id := ""
var _last_revision := -1
var _last_hash := ""


func advance(
	session: GameSession, human_id: StringName = &"p1", pilot_human: bool = false,
	max_steps: int = MAX_AUTONOMOUS_STEPS
) -> Dictionary:
	var trace: Array[Dictionary] = []
	var current_game_id := str(session.get_turn_access().get("game_id", ""))
	if _game_id != current_game_id:
		_game_id = current_game_id
		_progress_guard = CpuProgressGuard.new()
		_last_revision = -1
		_last_hash = ""
	for _step in mini(max_steps, MAX_AUTONOMOUS_STEPS):
		var turn_access := session.get_turn_access()
		if str(turn_access.get("status", "")) == "finished":
			return {"ok": true, "status": "finished", "steps": trace.size(), "trace": trace}
		var actor_id := StringName(turn_access.get("actor_id", ""))
		if actor_id == human_id and not pilot_human:
			return {"ok": true, "status": "waiting_for_human", "steps": trace.size(), "trace": trace}
		var context := session.get_client_context(actor_id)
		var view := context.get("player_view", {}) as Dictionary
		var actor_choice := view.get("effect_state", {}) as Dictionary
		var legal: Array[Dictionary] = []
		legal.assign(context.get("legal_commands", []))
		var features: Array[Dictionary] = []
		features.assign(context.get("action_features", []))
		var definitions := context.get("public_definitions", {}) as Dictionary
		var decision := CpuDecider.decide(view, legal, features, definitions)
		if decision.is_empty():
			return _failure("no_legal_command", trace)
		var fingerprint := str(decision["context_fingerprint"])
		var turn_key := "%s:%s" % [view.get("round", 0), view.get("active_player_id", "")]
		var progress_error := _progress_guard.observe(fingerprint, turn_key)
		if not progress_error.is_empty():
			return _failure(progress_error, trace)
		var command := decision["command"] as Dictionary
		if _last_revision != int(view.get("revision", -1)):
			_last_hash = session.get_state_hash()
			_last_revision = int(view.get("revision", -1))
		var before_hash := _last_hash
		var result := session.submit_command({
			"protocol_version": 1,
			"game_id": str(view.get("game_id", "")),
			"command_id": "cpu-%06d" % (int(view.get("revision", 0)) + 1),
			"actor_id": str(actor_id),
			"expected_revision": int(view.get("revision", -1)),
			"command": command,
		})
		trace.append({
			"round": view.get("round", 0), "phase": view.get("phase", ""),
			"actor_id": str(actor_id), "command": command,
			"pending_op": actor_choice.get("op", ""),
			"pending_choice": {
				"op": actor_choice.get("op", ""),
				"choice_id": actor_choice.get("choice_id", ""),
				"required_actor_id": str(actor_id),
				"selected_count": actor_choice.get("selected_count", 0),
			},
			"before_hash": before_hash,
			"after_hash": result.get("after_hash", before_hash),
			"reason_code": decision.get("reason_code", ""),
			"score": decision.get("score", 0),
			"context_fingerprint": fingerprint,
			"error": result.get("error", ""),
		})
		if not bool(result.get("ok", false)):
			return _failure("command_rejected", trace)
		var transition_error := _progress_guard.observe_result(
			view, session.get_progress_view(actor_id), str(decision["command_key"]),
			before_hash, str(result.get("after_hash", ""))
		)
		if not transition_error.is_empty():
			return _failure(transition_error, trace)
		_last_hash = str(result.get("after_hash", ""))
		_last_revision = int(view.get("revision", -1)) + 1
	if max_steps < MAX_AUTONOMOUS_STEPS:
		return {"ok": true, "status": "yielded", "steps": trace.size(), "trace": trace}
	return _failure("max_autonomous_steps", trace)


static func _failure(code: String, trace: Array[Dictionary]) -> Dictionary:
	return {"ok": false, "error": code, "steps": trace.size(),
		"trace": trace.slice(maxi(0, trace.size() - 16))}
