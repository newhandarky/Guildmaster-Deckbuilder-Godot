class_name CpuProgressGuard
extends RefCounted

const MAX_ACTIONS_PER_TURN := 128
const MAX_AUTONOMOUS_STEPS := 512

var repeated_contexts: Dictionary = {}
var actions_by_turn: Dictionary = {}
var _last_command_context := ""
var _repeated_commands := 0


func observe(context_fingerprint: String, turn_key: String) -> String:
	repeated_contexts[context_fingerprint] = int(repeated_contexts.get(context_fingerprint, 0)) + 1
	if int(repeated_contexts[context_fingerprint]) >= 3:
		return "repeated_public_state"
	actions_by_turn[turn_key] = int(actions_by_turn.get(turn_key, 0)) + 1
	if int(actions_by_turn[turn_key]) > MAX_ACTIONS_PER_TURN:
		return "max_actions_per_turn"
	return ""


func observe_result(
	before_view: Dictionary, after_view: Dictionary, command_key: String,
	before_hash: String, after_hash: String
) -> String:
	if before_hash == after_hash:
		return "unchanged_state"
	var command_context := "%s:%s:%s" % [
		before_view.get("active_player_id", ""), before_view.get("phase", ""), command_key
	]
	_repeated_commands = _repeated_commands + 1 if command_context == _last_command_context else 1
	_last_command_context = command_context
	if _repeated_commands >= 3:
		return "repeated_command"
	if command_key.contains("END_PHASE") and before_view.get("status", "") == "active" \
			and after_view.get("status", "") == "active" \
			and before_view.get("active_player_id", "") == after_view.get("active_player_id", "") \
			and before_view.get("phase", "") == after_view.get("phase", "") \
			and (after_view.get("effect_state", {}) as Dictionary).is_empty():
		return "phase_not_advanced"
	var before_choice := before_view.get("effect_state", {}) as Dictionary
	var after_choice := after_view.get("effect_state", {}) as Dictionary
	if command_key.contains("RESOLVE_CHOICE") and not before_choice.is_empty() \
			and before_choice.get("choice_id", "") == after_choice.get("choice_id", "") \
			and before_choice.get("op", "") == after_choice.get("op", "") \
			and before_choice.get("required_actor_id", before_choice.get("actor_id", "")) \
			== after_choice.get("required_actor_id", after_choice.get("actor_id", "")) \
			and before_choice.get("selected_count", 0) == after_choice.get("selected_count", 0) \
			and before_choice.get("remaining_card_ids", []) == after_choice.get("remaining_card_ids", []) \
			and before_choice.get("eligible_card_ids", []) == after_choice.get("eligible_card_ids", []):
		return "choice_not_consumed"
	return ""
