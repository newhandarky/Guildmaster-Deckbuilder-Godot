class_name EffectResolver
extends RefCounted

const SUPPORTED_OPERATIONS: Array[StringName] = [
	&"grant_purchase_power",
	&"grant_combat",
]


static func validate_effects(effects: Array[Dictionary], definition_id: StringName = &"") -> PackedStringArray:
	var errors := PackedStringArray()
	for index in effects.size():
		var effect := effects[index]
		var operation := StringName(effect.get("op", ""))
		if not operation in SUPPORTED_OPERATIONS:
			errors.append("Unsupported effect op %s at %s[%d]" % [operation, definition_id, index])
		if int(effect.get("amount", 0)) < 0:
			errors.append("Effect amount must not be negative at %s[%d]" % [definition_id, index])
	return errors


static func resolve(
	state: GameStateData,
	actor_id: StringName,
	effects: Array[Dictionary],
	events: Array[Dictionary]
) -> String:
	var player := state.players.get(actor_id) as PlayerStateData
	if player == null:
		return "missing_player"
	var validation_errors := validate_effects(effects)
	if not validation_errors.is_empty():
		return "invalid_effect: %s" % "; ".join(validation_errors)

	# Effects resolve FIFO in content order so replay and snapshot results stay deterministic.
	for index in effects.size():
		var effect := effects[index]
		var operation := StringName(effect.get("op", ""))
		var amount := int(effect.get("amount", 0))
		var resource_key: StringName
		match operation:
			&"grant_purchase_power":
				resource_key = &"purchase_power"
			&"grant_combat":
				resource_key = &"combat"
		player.turn_resources[resource_key] = int(player.turn_resources.get(resource_key, 0)) + amount
		events.append({
			"type": "effect_resolved",
			"actor_id": str(actor_id),
			"effect_index": index,
			"op": str(operation),
			"amount": amount,
			"resource": str(resource_key),
			"new_value": int(player.turn_resources[resource_key]),
		})
	return ""
