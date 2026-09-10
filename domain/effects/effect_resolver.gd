class_name EffectResolver
extends RefCounted

const SUPPORTED_OPERATIONS: Array[StringName] = [
	&"grant_purchase_power",
	&"grant_combat",
	&"draw",
	&"discard_hand_and_draw",
	&"conditional_combat",
	&"choose_remove_card",
	&"choose_gain_card",
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
		if operation in [&"choose_remove_card", &"choose_gain_card"] \
				and index != effects.size() - 1:
			errors.append("Pending choice effect must be last at %s[%d]" % [definition_id, index])
		if operation == &"choose_remove_card":
			var removal_amount := int(effect.get("amount", 0))
			if removal_amount < 1 or removal_amount > 2:
				errors.append("Card removal choice amount must be 1 or 2 at %s[%d]" % [definition_id, index])
			var removal_sources := _normalized_removal_sources(effect)
			if removal_sources.is_empty():
				errors.append("Card removal choice requires source zones at %s[%d]" % [definition_id, index])
			for source_zone_key: StringName in removal_sources:
				if source_zone_key not in [&"hand", &"party", &"discard_pile"]:
					errors.append("Unsupported removal source at %s[%d]" % [definition_id, index])
		if operation == &"choose_gain_card" and int(effect.get("amount", 0)) != 1:
			errors.append("Card gain choice amount must be 1 at %s[%d]" % [definition_id, index])
		if operation == &"choose_gain_card" \
				and StringName(effect.get("source_zone_id", "")) \
				not in [SupplyService.RECRUIT_ROW_ID, SupplyService.SHOP_ROW_ID]:
			errors.append("Unsupported gain source at %s[%d]" % [definition_id, index])
		if operation == &"choose_gain_card" and int(effect.get("max_cost", -1)) < 0:
			errors.append("Card gain choice requires a non-negative max_cost at %s[%d]" % [definition_id, index])
		if operation == &"choose_gain_card":
			var allowed_card_types := _normalized_allowed_tags(
				effect.get("allowed_card_types", [])
			)
			var allowed_tags := _normalized_allowed_tags(effect.get("allowed_tags", []))
			if allowed_card_types.is_empty() or allowed_tags.is_empty():
				errors.append("Card gain choice requires type and tag filters at %s[%d]" % [definition_id, index])
			elif not _gain_filter_matches_source(
				StringName(effect.get("source_zone_id", "")), allowed_card_types, allowed_tags
			):
				errors.append("Card gain filters do not match source at %s[%d]" % [definition_id, index])
	return errors


static func resolve(
	state: GameStateData,
	actor_id: StringName,
	effects: Array[Dictionary],
	events: Array[Dictionary],
	definitions: Dictionary = {}
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
			&"draw":
				var draw_result := DeckService.draw_cards(state, actor_id, amount, events)
				if not bool(draw_result.get("ok", false)):
					return str(draw_result.get("error", "draw_failed"))
				events.append({
					"type": "effect_resolved",
					"actor_id": str(actor_id),
					"effect_index": index,
					"op": str(operation),
					"amount": amount,
					"drawn_count": int(draw_result.get("drawn_count", 0)),
				})
				continue
			&"discard_hand_and_draw":
				var hand_zone_id := StringName(player.zone_ids.get(&"hand", &""))
				var discard_zone_id := StringName(player.zone_ids.get(&"discard_pile", &""))
				var draw_zone_id := StringName(player.zone_ids.get(&"draw_pile", &""))
				var hand := state.zones.get(hand_zone_id) as ZoneData
				var discard := state.zones.get(discard_zone_id) as ZoneData
				var draw_pile := state.zones.get(draw_zone_id) as ZoneData
				if hand == null or discard == null or draw_pile == null:
					return "missing_player_card_zone"
				var locked_card_ids := hand.card_instance_ids.duplicate()
				var locked_count := locked_card_ids.size()
				events.append({
					"type": "hand_redraw_started",
					"actor_id": str(actor_id),
					"locked_card_ids": _string_name_array_to_strings(locked_card_ids),
					"locked_count": locked_count,
				})
				for card_instance_id: StringName in locked_card_ids:
					var move_result := ZoneService.move_card(
						state, card_instance_id, hand_zone_id, discard_zone_id
					)
					if not bool(move_result.get("ok", false)):
						return str(move_result.get("error", "hand_redraw_discard_failed"))
					var move_event := (move_result.get("event", {}) as Dictionary).duplicate(true)
					move_event["reason"] = "hand_redraw_discard"
					events.append(move_event)
				var redraw_result := DeckService.draw_cards(
					state, actor_id, locked_count, events
				)
				if not bool(redraw_result.get("ok", false)):
					return str(redraw_result.get("error", "hand_redraw_draw_failed"))
				if int(redraw_result.get("drawn_count", 0)) != locked_count:
					return "hand_redraw_count_mismatch"
				events.append({
					"type": "effect_resolved",
					"actor_id": str(actor_id),
					"effect_index": index,
					"op": str(operation),
					"discarded_count": locked_count,
					"drawn_count": int(redraw_result.get("drawn_count", 0)),
				})
				continue
			&"choose_remove_card":
				var source_zone_keys := _normalized_removal_sources(effect)
				var removed := state.zones.get(player.zone_ids.get(&"removed", &"")) as ZoneData
				if removed == null:
					return "missing_choice_zone"
				var source_zone_ids: Dictionary = {}
				var eligible_card_ids: Array[String] = []
				var eligible_card_sources: Dictionary = {}
				for source_zone_key: StringName in source_zone_keys:
					var source_zone_id := StringName(player.zone_ids.get(source_zone_key, &""))
					var source := state.zones.get(source_zone_id) as ZoneData
					if source == null:
						return "missing_choice_zone"
					source_zone_ids[str(source_zone_key)] = str(source_zone_id)
					for card_instance_id: StringName in source.card_instance_ids:
						eligible_card_ids.append(str(card_instance_id))
						eligible_card_sources[str(card_instance_id)] = {
							"zone_key": str(source_zone_key),
							"zone_id": str(source_zone_id),
						}
				if eligible_card_ids.is_empty() or amount == 0:
					events.append({
						"type": "effect_resolved",
						"actor_id": str(actor_id),
						"effect_index": index,
						"op": str(operation),
						"selected_count": 0,
						"source_zone_ids": source_zone_ids.duplicate(true),
						"source_zone_keys": _string_name_array_to_strings(source_zone_keys),
						"reason": "no_eligible_candidates",
					})
					continue
				if not state.effect_state.is_empty():
					return "effect_state_occupied"
				state.effect_state = {
					"type": "pending_choice",
					"choice_id": "choice-%06d" % (state.revision + 1),
					"actor_id": str(actor_id),
					"op": str(operation),
					"prompt": _removal_prompt(source_zone_keys, amount),
					"source_zone_ids": source_zone_ids,
					"source_zone_keys": _string_name_array_to_strings(source_zone_keys),
					"destination_zone_id": str(removed.zone_id),
					"eligible_card_ids": eligible_card_ids,
					"eligible_card_sources": eligible_card_sources,
					"min_selections": 0 if bool(effect.get("optional", false)) else amount,
					"max_selections": amount,
					"selected_card_ids": [],
					"selected_count": 0,
					"effect_index": index,
					"source_card_instance_id": str(
						effect.get("source_card_instance_id", "")
					),
				}
				events.append({
					"type": "choice_requested",
					"choice_id": str(state.effect_state["choice_id"]),
					"actor_id": str(actor_id),
					"op": str(operation),
					"eligible_card_ids": eligible_card_ids.duplicate(),
					"optional": bool(effect.get("optional", false)),
					"source_zone_ids": source_zone_ids.duplicate(true),
					"source_zone_keys": _string_name_array_to_strings(source_zone_keys),
					"min_selections": int(state.effect_state["min_selections"]),
					"max_selections": amount,
				})
				continue
			&"choose_gain_card":
				var source_zone_id := StringName(effect.get("source_zone_id", ""))
				var source_zone_key := _gain_source_zone_key(source_zone_id)
				var source := state.zones.get(source_zone_id) as ZoneData
				var destination := state.zones.get(
					player.zone_ids.get(&"discard_pile", &"")
				) as ZoneData
				if source == null or destination == null:
					return "missing_choice_zone"
				var max_cost := int(effect.get("max_cost", -1))
				var allowed_card_types := _normalized_allowed_tags(
					effect.get("allowed_card_types", [])
				)
				var allowed_tags := _normalized_allowed_tags(effect.get("allowed_tags", []))
				var eligible_card_ids: Array[String] = []
				for card_instance_id: StringName in source.card_instance_ids:
					var definition := _definition_for_card(state, definitions, card_instance_id)
					if definition == null or definition.cost == null:
						continue
					if definition.card_type not in allowed_card_types \
							or not _definition_has_any_tag(definition, allowed_tags):
						continue
					if int(definition.cost) <= max_cost:
						eligible_card_ids.append(str(card_instance_id))
				if eligible_card_ids.is_empty() or amount == 0:
					events.append({
						"type": "effect_resolved",
						"actor_id": str(actor_id),
						"effect_index": index,
						"op": str(operation),
						"selected_count": 0,
						"source_zone_id": str(source.zone_id),
						"source_zone_key": str(source_zone_key),
						"reason": "no_eligible_candidates",
					})
					continue
				if not state.effect_state.is_empty():
					return "effect_state_occupied"
				state.effect_state = {
					"type": "pending_choice",
					"choice_id": "choice-%06d" % (state.revision + 1),
					"actor_id": str(actor_id),
					"op": str(operation),
					"prompt": "從%s取得 1 張費用不超過 %d 的%s" % [
						_gain_source_label(source_zone_key),
						max_cost,
						_gain_filter_label(allowed_card_types),
					],
					"source_zone_id": str(source.zone_id),
					"source_zone_key": str(source_zone_key),
					"destination_zone_id": str(destination.zone_id),
					"eligible_card_ids": eligible_card_ids,
					"min_selections": 0 if bool(effect.get("optional", false)) else 1,
					"max_selections": amount,
					"effect_index": index,
					"source_card_instance_id": str(effect.get("source_card_instance_id", "")),
					"max_cost": max_cost,
					"allowed_card_types": _string_name_array_to_strings(allowed_card_types),
					"allowed_tags": _string_name_array_to_strings(allowed_tags),
				}
				events.append({
					"type": "choice_requested",
					"choice_id": str(state.effect_state["choice_id"]),
					"actor_id": str(actor_id),
					"op": str(operation),
					"eligible_card_ids": eligible_card_ids.duplicate(),
					"optional": bool(effect.get("optional", false)),
					"source_zone_id": str(source.zone_id),
					"source_zone_key": str(source_zone_key),
					"destination_zone_id": str(destination.zone_id),
					"max_cost": max_cost,
					"allowed_card_types": _string_name_array_to_strings(allowed_card_types),
					"allowed_tags": _string_name_array_to_strings(allowed_tags),
				})
				continue
			_:
				return "effect_not_immediately_resolvable: %s" % operation
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


static func _source_zone_label(source_zone_key: StringName) -> String:
	return {
		&"hand": "手牌",
		&"party": "隊伍",
		&"discard_pile": "棄牌堆",
	}.get(source_zone_key, str(source_zone_key))


static func _normalized_removal_sources(effect: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	var raw_sources: Variant = effect.get("source_zone_keys", [])
	if raw_sources is Array:
		for raw_source: Variant in raw_sources:
			var source_zone_key := StringName(str(raw_source))
			if not source_zone_key.is_empty() and source_zone_key not in result:
				result.append(source_zone_key)
	if result.is_empty():
		var legacy_source := StringName(effect.get("source_zone_key", ""))
		if not legacy_source.is_empty():
			result.append(legacy_source)
	return result


static func _removal_prompt(source_zone_keys: Array[StringName], amount: int) -> String:
	var labels: Array[String] = []
	for source_zone_key: StringName in source_zone_keys:
		labels.append(_source_zone_label(source_zone_key))
	return "可以從自己的%s移除%s" % [
		_join_labels_with_or(labels),
		" 1 張牌" if amount == 1 else "最多 %d 張牌" % amount,
	]


static func _join_labels_with_or(labels: Array[String]) -> String:
	if labels.size() < 2:
		return "" if labels.is_empty() else labels[0]
	return "%s或%s" % ["、".join(labels.slice(0, -1)), labels.back()]


static func _gain_source_zone_key(source_zone_id: StringName) -> StringName:
	return &"recruit_row" if source_zone_id == SupplyService.RECRUIT_ROW_ID else &"shop_row"


static func _gain_source_label(source_zone_key: StringName) -> String:
	return "招募區" if source_zone_key == &"recruit_row" else "商店"


static func _gain_filter_label(allowed_card_types: Array[StringName]) -> String:
	if allowed_card_types == [&"adventurer"]:
		return "冒險者"
	if allowed_card_types == [&"item", &"equipment"]:
		return "道具或裝備"
	if allowed_card_types == [&"item"]:
		return "道具"
	if allowed_card_types == [&"equipment"]:
		return "裝備"
	return "指定類型卡牌"


static func _normalized_allowed_tags(raw_tags: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if not raw_tags is Array:
		return result
	for raw_tag: Variant in raw_tags:
		var tag := StringName(str(raw_tag))
		if tag.is_empty() or tag in result:
			continue
		result.append(tag)
	return result


static func _gain_filter_matches_source(
	source_zone_id: StringName,
	allowed_card_types: Array[StringName],
	allowed_tags: Array[StringName]
) -> bool:
	if source_zone_id == SupplyService.RECRUIT_ROW_ID:
		return _all_values_allowed(allowed_card_types, [&"adventurer"]) \
				and not allowed_tags.is_empty()
	if source_zone_id == SupplyService.SHOP_ROW_ID:
		return _all_values_allowed(allowed_card_types, [&"item", &"equipment"]) \
				and not allowed_tags.is_empty()
	return false


static func _all_values_allowed(
	values: Array[StringName],
	allowed_values: Array[StringName]
) -> bool:
	if values.is_empty():
		return false
	for value: StringName in values:
		if value not in allowed_values:
			return false
	return true


static func _definition_has_any_tag(
	definition: CardDefinition,
	allowed_tags: Array[StringName]
) -> bool:
	for tag: StringName in allowed_tags:
		if tag in definition.tags:
			return true
	return false


static func _definition_for_card(
	state: GameStateData,
	definitions: Dictionary,
	card_instance_id: StringName
) -> CardDefinition:
	var card := state.cards.get(card_instance_id) as Dictionary
	if card == null:
		return null
	return definitions.get(StringName(card.get("definition_id", ""))) as CardDefinition


static func _string_name_array_to_strings(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value: StringName in values:
		result.append(str(value))
	return result
