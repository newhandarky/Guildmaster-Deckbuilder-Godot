class_name CpuDecider
extends RefCounted

# This client-only policy receives no GameStateData, game session, RNG, or scene node.
static func decide(
	player_view: Dictionary, legal_commands: Array[Dictionary],
	action_features: Array[Dictionary], public_definitions: Dictionary,
	profile: Dictionary = {}
) -> Dictionary:
	if profile.is_empty():
		profile = CpuDecisionProfile.balanced()
	var actor_id := str(player_view.get("effect_state", {}).get(
		"required_actor_id", player_view.get("active_player_id", "")
	))
	var feature_by_key: Dictionary = {}
	for feature: Dictionary in action_features:
		feature_by_key[str(feature.get("command_key", ""))] = feature
	var context := _public_context(player_view, actor_id, action_features)
	var fingerprint := CanonicalJson.sha256(context)
	var best: Dictionary = {}
	for legal: Dictionary in legal_commands:
		var key := CpuCommandCodec.key(legal)
		var feature := feature_by_key.get(key, {}) as Dictionary
		if feature.is_empty():
			continue
		var evaluation := _score(feature, player_view, public_definitions, profile)
		var score := int(evaluation.get("score", -100000))
		if best.is_empty() or score > int(best["score"]) \
				or (score == int(best["score"]) and key < str(best["command_key"])):
			best = {
				"command": CpuCommandCodec.payload(legal),
				"command_key": key,
				"reason_code": str(evaluation.get("reason_code", "")),
				"score": score,
				"context_fingerprint": fingerprint,
			}
	return best


static func _score(
	feature: Dictionary, view: Dictionary, definitions: Dictionary, profile: Dictionary
) -> Dictionary:
	var command := feature.get("command", {}) as Dictionary
	var command_type := str(command.get("type", ""))
	var phase := str(view.get("phase", ""))
	var combat := int(feature.get("printed_combat", 0))
	var honor := int(feature.get("printed_honor", 0))
	var cost := int(feature.get("effective_cost", feature.get("printed_cost", 0)))
	var gap_gain := int(feature.get("combat_gain", 0))
	var boss_visible := int(feature.get("boss_gap_before", -1)) >= 0
	match command_type:
		"RESOLVE_CHOICE":
			var choice := view.get("effect_state", {}) as Dictionary
			var operation := str(choice.get("op", ""))
			if bool(command.get("skip", false)):
				return {"score": -20 if operation != "complete_bonds" else 0,
					"reason_code": "END_NO_POSITIVE_ACTION"}
			var value := combat * 12 + honor * 4 + int(feature.get("printed_purchase_power", 0)) * 4
			if operation == "select_bonds":
				return {"score": honor * 100 + 10, "reason_code": "KEEP_HIGHEST_BOND_VALUE"}
			if operation == "complete_bonds":
				return {"score": honor * 100 + 10, "reason_code": "COMPLETE_ELIGIBLE_BONDS"}
			if operation in ["choose_remove_card", "choose_transfer_card", "choose_equipment_replacement"]:
				value = -value
			return {"score": 50 + value, "reason_code": "RESOLVE_HIGHEST_UTILITY_CHOICE"}
		"ATTACK_TARGET":
			var boss := str(feature.get("attack_target_type", "")) == "boss"
			if boss and bool(feature.get("boss_post_departure_cost_required", false)) \
					and int(feature.get("boss_post_departure_cost_available", 0)) == 0:
				return {"score": -1000, "reason_code": "END_NO_POSITIVE_ACTION"}
			var attack_score := int(profile["attack_boss" if boss else "attack_monster"])
			attack_score += honor * int(profile["honor"])
			attack_score -= int(feature.get("participant_loss", 0)) * 3
			if not boss and boss_visible and int(feature.get("boss_gap_before", 0)) <= 6:
				attack_score -= 100 * int(feature.get("participant_loss", 0))
			if bool(feature.get("recirculates_on_defeat", false)):
				# A renewable resource reward is useful only while it improves the
				# next purchase. Diminishing value prevents endless repeat attacks.
				var reward := maxi(1, int(feature.get("immediate_purchase_reward", 0)))
				attack_score -= 45 * int(feature.get("available_purchase_power", 0)) / reward
			if not bool(command.get("claim_optional_reward", true)):
				attack_score -= 12
			if not bool(command.get("use_optional_departures", true)):
				attack_score += 3
			return {"score": attack_score, "reason_code": "ATTACK_BEST_NET_VALUE"}
		"PLAY_ADVENTURER":
			var play_score := 12 + combat * int(profile["party_power"])
			if bool(feature.get("consumes_last_boss_cost_card", false)):
				play_score -= 500
			if boss_visible:
				play_score += gap_gain * int(profile["boss_gap_reduction"])
				play_score += mini(0, int(feature.get("boss_gap_delta", 0))) * 60
				if bool(feature.get("boss_unlocked", false)):
					play_score += int(profile["boss_unlock"])
			return {"score": play_score, "reason_code": "PLAY_FOR_PARTY_POWER"}
		"EQUIP_ITEM":
			var equip_score := 20 + combat * int(profile["equipment_power"])
			if boss_visible:
				equip_score += gap_gain * int(profile["boss_gap_reduction"])
				equip_score += mini(0, int(feature.get("boss_gap_delta", 0))) * 60
				if bool(feature.get("boss_unlocked", false)):
					equip_score += int(profile["boss_unlock"])
			return {"score": equip_score, "reason_code": "EQUIP_FOR_COMBAT_GAIN"}
		"USE_ITEM", "ACTIVATE_EQUIPMENT_EFFECT":
			var item_score := 32 + gap_gain * int(profile["boss_gap_reduction"])
			item_score += mini(0, int(feature.get("boss_gap_delta", 0))) * 60
			if boss_visible and bool(feature.get("boss_unlocked", false)):
				item_score += int(profile["boss_unlock"])
			return {"score": item_score, "reason_code": "USE_ITEM_FOR_IMMEDIATE_VALUE"}
		"BUY_CARD":
			var utility := 25 + combat * int(profile["future_combat"]) \
				+ honor * int(profile["honor"]) - cost * int(profile["purchase_efficiency"])
			if boss_visible and int(feature.get("boss_gap_before", 0)) > 0:
				utility += combat * 4
			return {"score": utility, "reason_code": "BUY_HIGHEST_UTILITY"}
		"REFRESH_MARKET":
			return {"score": -10, "reason_code": "REFRESH_LOW_VALUE_MARKET"}
		"END_PHASE":
			return {"score": 0 if phase != "purchase" else 1,
				"reason_code": "END_NO_POSITIVE_ACTION"}
	return {"score": -100000, "reason_code": "END_NO_POSITIVE_ACTION"}


static func _public_context(
	view: Dictionary, actor_id: String, features: Array[Dictionary]
) -> Dictionary:
	var zone_projection: Dictionary = {}
	for zone_id: Variant in (view.get("zones", {}) as Dictionary):
		var zone := (view["zones"] as Dictionary)[zone_id] as Dictionary
		var visibility := str(zone.get("visibility", ""))
		var owner := str((zone.get("metadata", {}) as Dictionary).get("owner_id", ""))
		if visibility == "public" or owner == actor_id:
			if visibility == "hidden":
				continue
			zone_projection[str(zone_id)] = zone.get("card_instance_ids", [])
	var own_player: Dictionary = (view.get("players", {}) as Dictionary).get(actor_id, {})
	var feature_projection: Array[Dictionary] = []
	for feature: Dictionary in features:
		var compact := feature.duplicate(true)
		compact.erase("target_previews")
		feature_projection.append(compact)
	feature_projection.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("command_key", "")) < str(right.get("command_key", "")))
	return {
		"actor_id": actor_id,
		"phase": view.get("phase", ""),
		"round": view.get("round", 0),
		"effect_state": view.get("effect_state", {}),
		"own_player": own_player,
		"zones": zone_projection,
		"features": feature_projection,
		"target_previews": features[0].get("target_previews", []) if not features.is_empty() else [],
		"ruleset": view.get("ruleset_fingerprint", view.get("ruleset_version", "")),
		"definitions_fingerprint": view.get("content_fingerprint", ""),
	}
