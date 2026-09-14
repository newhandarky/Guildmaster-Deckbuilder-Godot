class_name InvariantService
extends RefCounted

const BossServiceType = preload("res://domain/state/boss_service.gd")


static func validate(state: GameStateData) -> PackedStringArray:
	var errors := PackedStringArray()
	_validate_turn_order(state, errors)
	_validate_players(state, errors)
	_validate_supply_zones(state, errors)
	errors.append_array(BondService.validate_state(state))
	_validate_effect_state(state, errors)
	var locations: Dictionary = {}
	for zone_id: Variant in state.zones:
		var zone := state.zones[zone_id] as ZoneData
		if zone == null:
			errors.append("Invalid zone at %s" % zone_id)
			continue
		if zone.zone_id.is_empty():
			errors.append("Zone ID must not be empty")
		elif StringName(zone_id) != zone.zone_id:
			errors.append("Zone key %s does not match zone_id %s" % [zone_id, zone.zone_id])
		var zone_owner_id := StringName(zone.metadata.get("owner_id", ""))
		if not zone_owner_id.is_empty():
			var owner := state.players.get(zone_owner_id) as PlayerStateData
			if owner == null:
				errors.append("Zone %s references missing owner %s" % [zone_id, zone_owner_id])
			elif not zone.zone_id in owner.zone_ids.values():
				errors.append("Owned zone %s is not referenced by player %s" % [zone_id, zone_owner_id])
		for instance_id: StringName in zone.card_instance_ids:
			if not state.cards.has(instance_id):
				errors.append("Zone %s references missing card %s" % [zone_id, instance_id])
				continue
			if locations.has(instance_id):
				errors.append("Card %s exists in both %s and %s" % [instance_id, locations[instance_id], zone_id])
				continue
			locations[instance_id] = zone_id
	for instance_id: Variant in state.cards:
		var card := state.cards[instance_id] as Dictionary
		if card == null:
			errors.append("Invalid card at %s" % instance_id)
			continue
		if StringName(card.get("instance_id", "")) != StringName(instance_id):
			errors.append("Card key %s does not match instance_id %s" % [instance_id, card.get("instance_id", "")])
		var owner_id := StringName(card.get("owner_id", ""))
		if not owner_id.is_empty() and not state.players.has(owner_id):
			errors.append("Card %s references missing owner %s" % [instance_id, owner_id])
		if not locations.has(instance_id):
			errors.append("Card %s is not in any zone" % instance_id)
	_validate_equipment_attachments(state, locations, errors)
	var command_ids: Dictionary = {}
	for command_id: String in state.processed_command_ids:
		if command_id.is_empty():
			errors.append("Processed command ID must not be empty")
		elif command_ids.has(command_id):
			errors.append("Processed command ID is duplicated: %s" % command_id)
		else:
			command_ids[command_id] = true
	if not state.phase in [&"action1", &"combat", &"action2", &"purchase", &"rest"]:
		errors.append("Invalid phase: %s" % state.phase)
	if state.status == &"active" and state.active_player_id.is_empty():
		errors.append("Active game requires an active player")
	if not state.status in [&"active", &"finished"]:
		errors.append("Invalid game status: %s" % state.status)
	if state.round_number < 1:
		errors.append("Round must be positive")
	if state.revision < 0 or state.event_cursor < 0:
		errors.append("Revision and event cursor must not be negative")
	return errors


static func _validate_supply_zones(state: GameStateData, errors: PackedStringArray) -> void:
	_validate_boss_zones(state, errors)
	if state.helpers_enabled:
		_validate_helper_zones(state, errors)
	elif state.zones.has(HelperService.DECK_ID) or state.zones.has(HelperService.ACTIVE_ID):
		errors.append("Disabled helper mode cannot contain helper zones")
	for row_zone_id: StringName in [SupplyService.RECRUIT_ROW_ID, SupplyService.SHOP_ROW_ID]:
		var row := state.zones.get(row_zone_id) as ZoneData
		if row == null:
			errors.append("Missing supply row %s" % row_zone_id)
		elif row.kind != &"face_up_row" or row.visibility != &"public":
			errors.append("Supply row %s must be a public face-up row" % row_zone_id)
		elif row.card_instance_ids.size() > SupplyService.ROW_SIZE:
			errors.append("Supply row %s exceeds capacity" % row_zone_id)
	for deck_zone_id: StringName in [SupplyService.RECRUIT_DECK_ID, SupplyService.SHOP_DECK_ID]:
		var deck := state.zones.get(deck_zone_id) as ZoneData
		if deck == null:
			errors.append("Missing supply deck %s" % deck_zone_id)
		elif deck.kind != &"ordered_deck" or deck.visibility != &"hidden":
			errors.append("Supply deck %s must be a hidden ordered deck" % deck_zone_id)
	var resource_draft_row := state.zones.get(SupplyService.RESOURCE_DRAFT_ROW_ID) as ZoneData
	if resource_draft_row == null:
		errors.append("Missing resource draft row")
	elif resource_draft_row.kind != &"face_up_row" \
			or resource_draft_row.visibility != &"public":
		errors.append("Resource draft row must be a public face-up row")
	elif resource_draft_row.card_instance_ids.size() > state.players.size():
		errors.append("Resource draft row exceeds player count")
	elif StringName(state.effect_state.get("op", "")) != &"draft_gain_card" \
			and not resource_draft_row.card_instance_ids.is_empty():
		errors.append("Resource draft row must be empty outside its pending choice")
	var monster_row := state.zones.get(SupplyService.MONSTER_ROW_ID) as ZoneData
	var monster_cycle := state.zones.get(SupplyService.MONSTER_CYCLE_ID) as ZoneData
	if monster_row == null:
		errors.append("Missing monster row")
	elif monster_row.kind != &"face_up_row" or monster_row.visibility != &"public":
		errors.append("Monster row must be a public face-up row")
	elif monster_row.card_instance_ids.size() > SupplyService.MONSTER_ROW_SIZE:
		errors.append("Monster row exceeds capacity")
	if monster_cycle == null:
		errors.append("Missing monster cycle")
	elif monster_cycle.kind != &"ordered_deck" or monster_cycle.visibility != &"hidden":
		errors.append("Monster cycle must be a hidden ordered deck")
	if monster_row != null and monster_cycle != null:
		var anchor_id := StringName(monster_cycle.metadata.get("cycle_anchor", ""))
		if anchor_id.is_empty():
			errors.append("Monster cycle requires an anchor")
		elif anchor_id not in monster_row.card_instance_ids \
				and anchor_id not in monster_cycle.card_instance_ids \
				and not _boss_attachment_contains(state, anchor_id):
			errors.append("Monster cycle anchor is not continuous")


static func _boss_attachment_contains(state: GameStateData, card_id: StringName) -> bool:
	var zone := state.zones.get(BossServiceType.BOSS_ATTACHMENT_ID) as ZoneData
	return zone != null and card_id in zone.card_instance_ids


static func _validate_helper_zones(state: GameStateData, errors: PackedStringArray) -> void:
	for zone_id: StringName in [HelperService.DECK_ID, HelperService.ACTIVE_ID, HelperService.RESERVE_ID, HelperService.REMOVED_ID, HelperService.DRAFT_ROW_ID]:
		if not state.zones.has(zone_id):
			errors.append("Missing helper zone %s" % zone_id)
			return
	var deck := state.zones[HelperService.DECK_ID] as ZoneData
	var active := state.zones[HelperService.ACTIVE_ID] as ZoneData
	var reserve := state.zones[HelperService.RESERVE_ID] as ZoneData
	var removed := state.zones[HelperService.REMOVED_ID] as ZoneData
	var draft := state.zones[HelperService.DRAFT_ROW_ID] as ZoneData
	if deck.kind != &"ordered_deck" or deck.visibility != &"hidden" \
			or reserve.kind != &"ordered_deck" or reserve.visibility != &"hidden" \
			or active.kind != &"face_up_row" or active.visibility != &"public" \
			or removed.kind != &"removed" or draft.kind != &"face_up_row" \
			or draft.visibility != &"public" or not bool(draft.metadata.get("temporary_choice_zone", false)):
		errors.append("Helper zone configuration is invalid")
	if active.card_instance_ids.size() > 1:
		errors.append("Only one helper may be active")
	if draft.card_instance_ids.size() > state.players.size():
		errors.append("Helper draft exceeds player count")
	if StringName(state.effect_state.get("op", "")) != &"draft_gain_card" \
			and not draft.card_instance_ids.is_empty():
		errors.append("Helper draft row must be empty outside draft choice")
	var helper_count := deck.card_instance_ids.size() + active.card_instance_ids.size() \
			+ reserve.card_instance_ids.size() + removed.card_instance_ids.size()
	if helper_count != 12:
		errors.append("Official helper instance count must remain 12")
	for zone: ZoneData in [deck, active, reserve, removed]:
		for card_id: StringName in zone.card_instance_ids:
			if not str(card_id).begins_with("card-helper-"):
				errors.append("Helper zone contains a non-helper card")


static func _validate_boss_zones(state: GameStateData, errors: PackedStringArray) -> void:
	var deck := state.zones.get(BossServiceType.BOSS_DECK_ID) as ZoneData
	var active := state.zones.get(BossServiceType.BOSS_ACTIVE_ID) as ZoneData
	var reserve := state.zones.get(BossServiceType.BOSS_RESERVE_ID) as ZoneData
	var attachments := state.zones.get(BossServiceType.BOSS_ATTACHMENT_ID) as ZoneData
	var removed := state.zones.get(BossServiceType.BOSS_REMOVED_ID) as ZoneData
	if deck == null or deck.kind != &"ordered_deck" or deck.visibility != &"hidden":
		errors.append("Boss deck must be a hidden ordered deck")
	if reserve == null or reserve.kind != &"ordered_deck" or reserve.visibility != &"hidden":
		errors.append("Boss reserve must be a hidden ordered deck")
	if active == null or active.kind != &"face_up_row" or active.visibility != &"public":
		errors.append("Boss active zone must be a public face-up row")
	elif active.card_instance_ids.size() > 1:
		errors.append("Boss active zone exceeds capacity")
	elif active.card_instance_ids.is_empty() \
			and not bool(active.metadata.get("pending_reveal", false)) \
			and not bool(active.metadata.get("all_bosses_defeated", false)):
		errors.append("Empty boss active zone requires a progression marker")
	if attachments == null or attachments.kind != &"attachment" or attachments.visibility != &"public":
		errors.append("Boss attachment zone must be public")
	if removed == null or removed.kind != &"removed" or removed.visibility != &"public":
		errors.append("Boss removed zone must be public")
	if active != null and attachments != null:
		var active_id := active.card_instance_ids[0] if not active.card_instance_ids.is_empty() else &""
		var active_card := state.cards.get(active_id, {}) as Dictionary
		var linked_ids := (
			(active_card.get("state", {}) as Dictionary).get("attachment_ids", []) as Array
			if not active_card.is_empty() else []
		)
		if linked_ids.size() != attachments.card_instance_ids.size():
			errors.append("Boss attachment links must match the attachment zone")
		for attachment_id: StringName in attachments.card_instance_ids:
			var card := state.cards.get(attachment_id, {}) as Dictionary
			if str(attachment_id) not in linked_ids \
					or card.is_empty() \
					or StringName((card.get("state", {}) as Dictionary).get("attached_to", "")) != active_id:
				errors.append("Boss attachment relationship must be bidirectional")


static func _validate_equipment_attachments(
	state: GameStateData,
	locations: Dictionary,
	errors: PackedStringArray
) -> void:
	var occupied_targets: Dictionary = {}
	for instance_id: Variant in state.cards:
		var card := state.cards[instance_id] as Dictionary
		if card == null or not card.get("state", {}) is Dictionary:
			errors.append("Card %s state must be a Dictionary" % instance_id)
			continue
		var card_state := card.get("state", {}) as Dictionary
		var equipment_ids_value: Variant = card_state.get("equipment_ids", [])
		if not equipment_ids_value is Array:
			errors.append("Card %s equipment_ids must be an Array" % instance_id)
		else:
			var seen_equipment: Dictionary = {}
			for raw_equipment_id: Variant in equipment_ids_value as Array:
				var equipment_id := StringName(str(raw_equipment_id))
				if seen_equipment.has(equipment_id):
					errors.append("Card %s lists equipment %s more than once" % [instance_id, equipment_id])
					continue
				seen_equipment[equipment_id] = true
				var equipment_card := state.cards.get(equipment_id) as Dictionary
				if equipment_card == null:
					errors.append("Card %s lists missing equipment %s" % [instance_id, equipment_id])
					continue
				var equipment_state := equipment_card.get("state", {}) as Dictionary
				if StringName(equipment_state.get("equipped_to", "")) != StringName(instance_id):
					errors.append("Card %s and equipment %s attachment is not bidirectional" % [instance_id, equipment_id])
		var target_id := StringName(card_state.get("equipped_to", ""))
		if target_id.is_empty():
			continue
		if not state.cards.has(target_id):
			errors.append("Equipment %s references missing target %s" % [instance_id, target_id])
			continue
		if occupied_targets.has(target_id):
			errors.append("Target %s has more than one equipment" % target_id)
		else:
			occupied_targets[target_id] = instance_id
		var owner_id := StringName(card.get("owner_id", ""))
		var target_card := state.cards[target_id] as Dictionary
		if StringName(target_card.get("owner_id", "")) != owner_id:
			errors.append("Equipment %s and target %s have different owners" % [instance_id, target_id])
		var target_state := target_card.get("state", {}) as Dictionary
		var target_equipment_value: Variant = target_state.get("equipment_ids", [])
		if not target_equipment_value is Array:
			errors.append("Equipment target %s equipment_ids must be an Array" % target_id)
			continue
		var target_equipment_ids := target_equipment_value as Array
		if not str(instance_id) in target_equipment_ids and not StringName(instance_id) in target_equipment_ids:
			errors.append("Equipment %s is not listed by target %s" % [instance_id, target_id])
		var player := state.players.get(owner_id) as PlayerStateData
		if player == null:
			continue
		if StringName(locations.get(instance_id, "")) != StringName(player.zone_ids.get(&"equipment", &"")):
			errors.append("Equipped card %s must be in its owner's equipment zone" % instance_id)
		if StringName(locations.get(target_id, "")) != StringName(player.zone_ids.get(&"party", &"")):
			errors.append("Equipment target %s must be in its owner's party" % target_id)


static func _validate_turn_order(state: GameStateData, errors: PackedStringArray) -> void:
	if state.turn_order.size() < 2 or state.turn_order.size() > 4:
		errors.append("Turn order must contain 2 to 4 players")
	var seen: Dictionary = {}
	for player_id: StringName in state.turn_order:
		if player_id.is_empty():
			errors.append("Turn order contains an empty player ID")
		elif seen.has(player_id):
			errors.append("Turn order contains duplicate player %s" % player_id)
		else:
			seen[player_id] = true
		if not state.players.has(player_id):
			errors.append("Turn order references missing player %s" % player_id)
	if state.players.size() != state.turn_order.size():
		errors.append("Players and turn order must contain the same entries")
	if not state.starting_player_id in state.turn_order:
		errors.append("Starting player must be in turn order")
	if not state.active_player_id in state.turn_order:
		errors.append("Active player must be in turn order")


static func _validate_players(state: GameStateData, errors: PackedStringArray) -> void:
	var seats: Dictionary = {}
	var referenced_zone_ids: Dictionary = {}
	var expected_zone_kinds := {
		&"draw_pile": &"ordered_deck",
		&"hand": &"hand",
		&"discard_pile": &"discard_pile",
		&"party": &"party",
		&"equipment": &"equipment",
		&"play_area": &"play_area",
		&"bonds": &"bonds",
		&"bond_candidates": &"temporary_choice",
		&"completed_bonds": &"bonds",
		&"removed": &"removed",
		&"inspection": &"temporary_choice",
	}
	for player_id: Variant in state.players:
		var player := state.players[player_id] as PlayerStateData
		if player == null:
			errors.append("Invalid player at %s" % player_id)
			continue
		if StringName(player_id) != player.player_id:
			errors.append("Player key %s does not match player_id %s" % [player_id, player.player_id])
		if player.display_name.is_empty():
			errors.append("Player %s requires a display name" % player_id)
		if player.seat_index < 0 or player.seat_index >= state.turn_order.size():
			errors.append("Player %s has invalid seat index %d" % [player_id, player.seat_index])
		elif seats.has(player.seat_index):
			errors.append("Seat index %d is assigned more than once" % player.seat_index)
		else:
			seats[player.seat_index] = player_id
			if state.turn_order[player.seat_index] != player.player_id:
				errors.append("Player %s seat does not match turn order" % player_id)
		for zone_key: StringName in PlayerStateData.REQUIRED_ZONE_KEYS:
			if not player.zone_ids.has(zone_key):
				errors.append("Player %s is missing zone reference %s" % [player_id, zone_key])
				continue
			var zone_id := StringName(player.zone_ids[zone_key])
			if zone_id.is_empty():
				errors.append("Player %s has an empty zone reference for %s" % [player_id, zone_key])
				continue
			if referenced_zone_ids.has(zone_id):
				errors.append("Player zone %s is referenced more than once" % zone_id)
			else:
				referenced_zone_ids[zone_id] = true
			var zone := state.zones.get(zone_id) as ZoneData
			if zone == null:
				errors.append("Player %s references missing zone %s" % [player_id, zone_id])
			elif StringName(zone.metadata.get("owner_id", "")) != player.player_id:
				errors.append("Player zone %s has the wrong owner" % zone_id)
			elif zone.kind != expected_zone_kinds[zone_key]:
				errors.append("Player zone %s has invalid kind %s" % [zone_id, zone.kind])
			var expected_visibility: StringName = &"owner_only" if zone_key in [&"draw_pile", &"hand", &"bonds", &"bond_candidates", &"inspection"] else &"public"
			if zone != null and zone.visibility != expected_visibility:
				errors.append("Player zone %s has invalid visibility %s" % [zone_id, zone.visibility])


static func _validate_effect_state(state: GameStateData, errors: PackedStringArray) -> void:
	if state.effect_state.is_empty():
		return
	var choice := state.effect_state
	if StringName(choice.get("type", "")) != &"pending_choice":
		errors.append("Unsupported effect state type")
		return
	var actor_id := StringName(choice.get("actor_id", ""))
	if actor_id != state.active_player_id or not state.players.has(actor_id):
		errors.append("Pending choice must belong to the active player")
	var required_actor_id := StringName(choice.get("required_actor_id", actor_id))
	if not state.players.has(required_actor_id):
		errors.append("Pending choice required actor must be a player")
	var choice_id := str(choice.get("choice_id", ""))
	if choice_id.is_empty():
		errors.append("Pending choice requires a choice ID")
	var locked_source_zone := StringName(choice.get("source_card_zone_id", ""))
	if not locked_source_zone.is_empty() and ZoneService.find_card_zone(
		state, StringName(choice.get("source_card_instance_id", ""))
	) != locked_source_zone:
		errors.append("Pending choice effect source moved from its locked zone")
	var destination_zone_id := StringName(choice.get("destination_zone_id", ""))
	var player := state.players.get(actor_id) as PlayerStateData
	var operation := StringName(choice.get("op", ""))
	if player != null:
		match operation:
			&"select_bonds", &"complete_bonds":
				pass
			&"choose_supply_deck_draft":
				if StringName(choice.get("source_zone_id", "")) != HelperService.DRAFT_ROW_ID \
						or StringName(choice.get("destination_zone_id", "")) != HelperService.DRAFT_ROW_ID:
					errors.append("Pending helper draft source selection zone is invalid")
			&"choose_transfer_card":
				var next_index := (state.turn_order.find(actor_id) + 1) % state.turn_order.size()
				var recipient := state.players[state.turn_order[next_index]] as PlayerStateData
				if StringName(choice.get("source_zone_id", "")) != StringName(player.zone_ids.get(&"hand", &"")) \
						or StringName(choice.get("destination_zone_id", "")) != StringName(recipient.zone_ids.get(&"hand", &"")) \
						or StringName(choice.get("recipient_id", "")) != recipient.player_id:
					errors.append("Pending helper transfer zones are invalid")
			&"choose_equipment_replacement":
				if StringName(choice.get("source_zone_id", "")) \
						!= StringName(player.zone_ids.get(&"equipment", &"")) \
						or destination_zone_id != StringName(player.zone_ids.get(&"discard_pile", &"")):
					errors.append("Pending equipment replacement zones are invalid")
				var target_id := StringName(choice.get("target_card_id", ""))
				if ZoneService.find_card_zone(state, target_id) != StringName(player.zone_ids.get(&"party", &"")):
					errors.append("Pending equipment replacement target moved")
			&"inspect_deck_top", &"order_deck_top":
				if StringName(choice.get("source_zone_id", "")) \
						!= StringName(player.zone_ids.get(&"inspection", &"")):
					errors.append("Pending inspection must use the actor inspection zone")
				var valid_destination := (
					operation == &"inspect_deck_top"
					and destination_zone_id == StringName(player.zone_ids.get(&"removed", &""))
				) or (
					operation == &"order_deck_top"
					and destination_zone_id == StringName(player.zone_ids.get(&"draw_pile", &""))
				)
				if not valid_destination:
					errors.append("Pending inspection destination is invalid")
			&"confirm_effect":
				if StringName(choice.get("source_zone_id", "")).is_empty() \
						or str(choice.get("source_card_instance_id", "")) \
						not in (choice.get("eligible_card_ids", []) as Array):
					errors.append("Pending effect confirmation source is invalid")
			&"choose_move_card":
				var source_zone_key := StringName(choice.get("source_zone_key", ""))
				if StringName(choice.get("source_zone_id", "")) \
						!= StringName(player.zone_ids.get(source_zone_key, &"")) \
						or destination_zone_id not in player.zone_ids.values():
					errors.append("Pending move source or destination is invalid")
			&"choose_target_combat_modifier", &"choose_refresh_row":
				if StringName(choice.get("source_zone_id", "")).is_empty() \
						or not state.zones.has(StringName(choice.get("source_zone_id", ""))):
					errors.append("Pending public-row choice source is invalid")
			&"choose_remove_card":
				_validate_removal_choice_sources(choice, player, errors)
				if destination_zone_id != StringName(player.zone_ids.get(&"removed", &"")):
					errors.append("Pending removal destination must be the actor removed zone")
			&"choose_gain_card":
				var source_zone_id := StringName(choice.get("source_zone_id", ""))
				var source_zone_key := StringName(choice.get("source_zone_key", ""))
				var valid_source := (
					source_zone_key == &"recruit_row"
					and source_zone_id == SupplyService.RECRUIT_ROW_ID
				) or (
					source_zone_key == &"shop_row"
					and source_zone_id == SupplyService.SHOP_ROW_ID
				)
				if not valid_source:
					errors.append("Pending gain source must be an allowed public row")
				if destination_zone_id != StringName(player.zone_ids.get(&"discard_pile", &"")):
					errors.append("Pending gain destination must be the actor discard pile")
				var allowed_card_types := _normalized_choice_tags(
					choice.get("allowed_card_types", [])
				)
				var allowed_tags := _normalized_choice_tags(choice.get("allowed_tags", []))
				var valid_tags := (
					source_zone_key == &"recruit_row"
					and _all_choice_values_allowed(allowed_card_types, [&"adventurer"])
					and not allowed_tags.is_empty()
				) or (
					source_zone_key == &"shop_row"
					and _all_choice_values_allowed(
						allowed_card_types, [&"item", &"equipment"]
					)
					and not allowed_tags.is_empty()
				)
				if int(choice.get("max_cost", -1)) < 0 or not valid_tags:
					errors.append("Pending gain filter is invalid")
				var source_effect := choice.get("source_effect", {}) as Dictionary
				if StringName(source_effect.get("op", "")) != &"choose_gain_card" \
						or StringName(source_effect.get("source_zone_id", "")) != source_zone_id \
						or int(source_effect.get("max_cost", -1)) != int(choice.get("max_cost", -1)) \
						or source_effect.get("allowed_card_types", []) != choice.get("allowed_card_types", []) \
						or source_effect.get("allowed_tags", []) != choice.get("allowed_tags", []):
					errors.append("Pending gain source effect does not match locked rules")
			&"draft_gain_card":
				_validate_draft_choice(state, choice, actor_id, required_actor_id, errors)
			&"pay_post_departure_cost":
				if not choice.get("source_rule", {}) is Dictionary:
					errors.append("Pending post-departure cost is invalid")
				else:
					var source_rule := choice.get("source_rule", {}) as Dictionary
					var source_zone_key := StringName(choice.get("source_zone_key", ""))
					if StringName(choice.get("source_zone_id", "")) != StringName(player.zone_ids.get(source_zone_key, &"")) \
							or destination_zone_id != StringName(player.zone_ids.get(
								StringName(source_rule.get("destination_zone_key", "")), &""
							)) or StringName(source_rule.get("op", "")) != &"post_departure_cost" \
							or StringName(source_rule.get("source_zone_key", "")) != source_zone_key \
							or StringName(source_rule.get("card_type", "")) \
							!= StringName(choice.get("required_card_type", "")):
						errors.append("Pending post-departure cost is invalid")
			_:
				errors.append("Unsupported pending choice operation")
	if choice.has("boss_completion"):
		if not choice.get("boss_completion", {}) is Dictionary:
			errors.append("Pending boss completion must be a Dictionary")
		else:
			_validate_boss_completion(
				state, choice.get("boss_completion", {}) as Dictionary, actor_id, errors
			)
	if not choice.get("eligible_card_ids", []) is Array:
		errors.append("Pending choice eligible cards must be an Array")
		return
	if not choice.get("selected_card_ids", []) is Array:
		errors.append("Pending choice selected cards must be an Array")
		return
	if operation == &"choose_remove_card" \
			and not choice.get("eligible_card_sources", {}) is Dictionary:
		errors.append("Pending removal candidate origins must be a Dictionary")
		return
	var selected_card_ids := choice.get("selected_card_ids", []) as Array
	var selected_seen: Dictionary = {}
	for raw_selected_id: Variant in selected_card_ids:
		var selected_id := StringName(str(raw_selected_id))
		if selected_id.is_empty() or selected_seen.has(selected_id):
			errors.append("Pending choice selected cards must be unique and non-empty")
			continue
		selected_seen[selected_id] = true
	var eligible_seen: Dictionary = {}
	for raw_card_id: Variant in choice.get("eligible_card_ids", []):
		var card_instance_id := StringName(str(raw_card_id))
		if card_instance_id.is_empty() or eligible_seen.has(card_instance_id):
			errors.append("Pending choice eligible cards must be unique and non-empty")
			continue
		eligible_seen[card_instance_id] = true
		if operation == &"choose_remove_card":
			if player != null:
				_validate_removal_candidate(
					state,
					choice,
					player,
					card_instance_id,
					selected_seen.has(card_instance_id),
					errors
				)
		elif operation == &"choose_gain_card":
			var source_zone_id := StringName(choice.get("source_zone_id", ""))
			var expected_zone_id := destination_zone_id if selected_seen.has(card_instance_id) else source_zone_id
			if ZoneService.find_card_zone(state, card_instance_id) != expected_zone_id:
				errors.append("Pending choice card %s is not in its expected zone" % card_instance_id)
			var card := state.cards.get(card_instance_id) as Dictionary
			var expected_owner := actor_id if selected_seen.has(card_instance_id) else &""
			if card == null or StringName(card.get("owner_id", "")) != expected_owner:
				errors.append("Pending gain card %s has invalid ownership" % card_instance_id)
		elif operation in [&"confirm_effect", &"choose_move_card", &"inspect_deck_top", \
				&"order_deck_top", \
				&"choose_target_combat_modifier", &"choose_refresh_row", \
				&"choose_equipment_replacement", &"choose_transfer_card"]:
			var expected_zone_id := StringName(choice.get("source_zone_id", ""))
			if ZoneService.find_card_zone(state, card_instance_id) != expected_zone_id:
				errors.append("Pending choice card %s moved from its locked source" % card_instance_id)
		elif operation == &"pay_post_departure_cost":
			var expected_zone_id := destination_zone_id if selected_seen.has(card_instance_id) else StringName(choice.get("source_zone_id", ""))
			if ZoneService.find_card_zone(state, card_instance_id) != expected_zone_id:
				errors.append("Pending cost card %s is not in its expected zone" % card_instance_id)
			var card := state.cards.get(card_instance_id) as Dictionary
			if card == null or StringName(card.get("owner_id", "")) != actor_id:
				errors.append("Pending cost card %s must belong to the actor" % card_instance_id)
		elif operation == &"draft_gain_card":
			_validate_draft_candidate(
				state, choice, card_instance_id, selected_seen.has(card_instance_id), errors
			)
		elif operation == &"choose_supply_deck_draft":
			if card_instance_id not in [SupplyService.RECRUIT_DECK_ID, SupplyService.SHOP_DECK_ID]:
				errors.append("Pending helper draft has invalid supply option")
	for selected_id: Variant in selected_card_ids:
		if not eligible_seen.has(StringName(str(selected_id))):
			errors.append("Pending choice selected cards must be locked candidates")
	if operation == &"choose_remove_card" \
			and (choice.get("eligible_card_sources", {}) as Dictionary).size() \
			!= eligible_seen.size():
		errors.append("Pending removal candidate origins must match locked candidates")
	var minimum := int(choice.get("min_selections", -1))
	var maximum := int(choice.get("max_selections", -1))
	var maximum_limit := (
		eligible_seen.size()
		if operation in [&"order_deck_top", &"choose_refresh_row", &"select_bonds", &"complete_bonds"]
		else (2 if operation in [&"choose_remove_card", &"choose_gain_card"] else 1)
	)
	if minimum < 0 or maximum < minimum or maximum > maximum_limit:
		errors.append("Pending choice selection bounds are invalid")
	if operation == &"choose_remove_card" \
			and (int(choice.get("selected_count", -1)) != selected_card_ids.size() \
			or selected_card_ids.size() >= maximum):
		errors.append("Pending choice selection progress is invalid")
	if operation in [&"choose_gain_card", &"pay_post_departure_cost"] \
			and (int(choice.get("selected_count", -1)) != selected_card_ids.size() \
			or selected_card_ids.size() >= maximum):
		errors.append("Pending choice selection progress is invalid")
	if operation == &"draft_gain_card" \
			and int(choice.get("selected_count", -1)) != selected_card_ids.size():
		errors.append("Pending draft selection progress is invalid")


static func _validate_boss_completion(
	state: GameStateData,
	completion: Dictionary,
	expected_actor_id: StringName,
	errors: PackedStringArray
) -> void:
	var target_card_id := StringName(completion.get("target_card_id", ""))
	var active := state.zones.get(BossServiceType.BOSS_ACTIVE_ID) as ZoneData
	if active == null or target_card_id not in active.card_instance_ids:
		errors.append("Pending boss completion target must remain active")
	if StringName(completion.get("actor_id", "")) != expected_actor_id:
		errors.append("Pending boss completion actor must match its choice")
	if not completion.get("participant_ids", []) is Array \
			or not completion.get("remaining_effects", []) is Array:
		errors.append("Pending boss completion payload is invalid")


static func _validate_draft_choice(
	state: GameStateData,
	choice: Dictionary,
	defeated_by_actor_id: StringName,
	required_actor_id: StringName,
	errors: PackedStringArray
) -> void:
	if StringName(choice.get("defeated_by_actor_id", "")) != defeated_by_actor_id:
		errors.append("Pending draft defeater must match its actor")
	if not choice.get("source_effect", {}) is Dictionary:
		errors.append("Pending draft source effect must be a Dictionary")
		return
	var source_effect := choice.get("source_effect", {}) as Dictionary
	if StringName(source_effect.get("op", "")) != &"draft_gain_card" \
			or StringName(source_effect.get("source_deck_zone_id", "")) \
			!= StringName(choice.get("source_deck_zone_id", "")) \
			or StringName(source_effect.get("choice_zone_id", "")) \
			!= StringName(choice.get("choice_zone_id", "")) \
			or StringName(source_effect.get("destination_zone_key", "")) \
			!= StringName(choice.get("destination_zone_key", "")):
		errors.append("Pending draft source effect does not match its locked rules")
	var source_deck := state.zones.get(
		StringName(choice.get("source_deck_zone_id", ""))
	) as ZoneData
	var choice_zone := state.zones.get(StringName(choice.get("choice_zone_id", ""))) as ZoneData
	if source_deck == null or source_deck.kind != &"ordered_deck" \
			or source_deck.visibility != &"hidden" or choice_zone == null \
			or choice_zone.kind != &"face_up_row" or choice_zone.visibility != &"public" \
			or not bool(choice_zone.metadata.get("temporary_choice_zone", false)) \
			or StringName(choice.get("source_zone_id", "")) != choice_zone.zone_id:
		errors.append("Pending draft zones are invalid")
	if StringName(choice.get("destination_zone_key", "")) != &"hand":
		errors.append("Pending draft destination rule must be player hand")
	for field_name: String in ["remaining_card_ids", "selection_order", "completed_selections"]:
		if not choice.get(field_name, []) is Array:
			errors.append("Pending draft %s must be an Array" % field_name)
			return
	var remaining := choice.get("remaining_card_ids", []) as Array
	if remaining.is_empty():
		errors.append("Pending draft requires remaining candidates")
	var order := choice.get("selection_order", []) as Array
	var selection_index := int(choice.get("selection_index", -1))
	if selection_index < 0 or selection_index >= order.size() \
			or StringName(str(order[selection_index])) != required_actor_id:
		errors.append("Pending draft required actor must match selection order")
	if order.is_empty() or order.size() != (choice.get("eligible_card_ids", []) as Array).size():
		errors.append("Pending draft selection order must match revealed cards")
	var expected_order: Array[String] = []
	var start_index := state.turn_order.find(defeated_by_actor_id)
	for offset in order.size():
		expected_order.append(str(state.turn_order[(start_index + offset) % state.turn_order.size()]))
	if order != expected_order:
		errors.append("Pending draft selection order must follow turn order")


static func _validate_draft_candidate(
	state: GameStateData,
	choice: Dictionary,
	card_instance_id: StringName,
	is_selected: bool,
	errors: PackedStringArray
) -> void:
	var remaining := choice.get("remaining_card_ids", []) as Array
	var location := ZoneService.find_card_zone(state, card_instance_id)
	var card := state.cards.get(card_instance_id) as Dictionary
	if not is_selected:
		if str(card_instance_id) not in remaining \
				or location != StringName(choice.get("choice_zone_id", "")):
			errors.append("Pending draft card %s must remain in its choice zone" % card_instance_id)
		if card == null or not StringName(card.get("owner_id", "")).is_empty():
			errors.append("Pending draft candidate %s must be unowned" % card_instance_id)
		return
	if str(card_instance_id) in remaining:
		errors.append("Pending draft selected card %s cannot remain available" % card_instance_id)
		return
	var completed := choice.get("completed_selections", []) as Array
	var matched := false
	for raw_record: Variant in completed:
		if not raw_record is Dictionary:
			continue
		var record := raw_record as Dictionary
		if StringName(record.get("card_instance_id", "")) != card_instance_id:
			continue
		var owner_id := StringName(record.get("actor_id", ""))
		var owner := state.players.get(owner_id) as PlayerStateData
		matched = owner != null \
				and location == StringName(owner.zone_ids.get(&"hand", &"")) \
				and card != null and StringName(card.get("owner_id", "")) == owner_id
		break
	if not matched:
		errors.append("Pending draft selected card %s must be in its chooser hand" % card_instance_id)


static func _validate_removal_choice_sources(
	choice: Dictionary,
	player: PlayerStateData,
	errors: PackedStringArray
) -> void:
	if not choice.get("source_zone_keys", []) is Array \
			or not choice.get("source_zone_ids", {}) is Dictionary:
		errors.append("Pending removal requires source zone keys and IDs")
		return
	var source_zone_keys := choice.get("source_zone_keys", []) as Array
	var source_zone_ids := choice.get("source_zone_ids", {}) as Dictionary
	var seen: Dictionary = {}
	for raw_zone_key: Variant in source_zone_keys:
		var zone_key := StringName(str(raw_zone_key))
		if zone_key not in [&"hand", &"party", &"discard_pile"] or seen.has(zone_key):
			errors.append("Pending removal has invalid source zone keys")
			continue
		seen[zone_key] = true
		if StringName(source_zone_ids.get(str(zone_key), "")) \
				!= StringName(player.zone_ids.get(zone_key, &"")):
			errors.append("Pending removal sources must belong to the actor")
	if source_zone_keys.is_empty() or source_zone_ids.size() != source_zone_keys.size():
		errors.append("Pending removal source zones must be complete")


static func _validate_removal_candidate(
	state: GameStateData,
	choice: Dictionary,
	player: PlayerStateData,
	card_instance_id: StringName,
	is_selected: bool,
	errors: PackedStringArray
) -> void:
	var candidate_sources := choice.get("eligible_card_sources", {}) as Dictionary
	var source_record := candidate_sources.get(str(card_instance_id), {}) as Dictionary
	var source_zone_key := StringName(source_record.get("zone_key", ""))
	var source_zone_id := StringName(source_record.get("zone_id", ""))
	if source_zone_key not in [&"hand", &"party", &"discard_pile"] \
			or source_zone_id != StringName(player.zone_ids.get(source_zone_key, &"")):
		errors.append("Pending removal candidate %s has invalid origin" % card_instance_id)
		return
	var expected_zone_id := (
		StringName(player.zone_ids.get(&"removed", &"")) if is_selected else source_zone_id
	)
	if ZoneService.find_card_zone(state, card_instance_id) != expected_zone_id:
		errors.append("Pending removal card %s is not in its expected zone" % card_instance_id)
	var card := state.cards.get(card_instance_id) as Dictionary
	if card == null or StringName(card.get("owner_id", "")) != player.player_id:
		errors.append("Pending removal card %s must belong to the actor" % card_instance_id)


static func _normalized_choice_tags(raw_tags: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if not raw_tags is Array:
		return result
	for raw_tag: Variant in raw_tags:
		var tag := StringName(str(raw_tag))
		if not tag.is_empty() and tag not in result:
			result.append(tag)
	return result


static func _all_choice_values_allowed(
	values: Array[StringName],
	allowed_values: Array[StringName]
) -> bool:
	if values.is_empty():
		return false
	for value: StringName in values:
		if value not in allowed_values:
			return false
	return true
