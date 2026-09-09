class_name GameStateData
extends RefCounted

const ZoneDataType = preload("res://domain/state/zone_data.gd")
const PlayerStateDataType = preload("res://domain/state/player_state_data.gd")

var schema_version: int = 1
var game_id: StringName = &"game-demo-001"
var content_version: String = "0.2.0"
var ruleset_version: String = "0.2.0"
var seed_value: int = 20260909
var rng_state: int = 0
var revision: int = 0
var status: StringName = &"active"
var round_number: int = 1
var phase: StringName = &"action1"
var starting_player_id: StringName = &"p1"
var active_player_id: StringName = &"p1"
var turn_order: Array[StringName] = []
var players: Dictionary = {}
var cards: Dictionary = {}
var zones: Dictionary = {}
var effect_state: Dictionary = {}
var event_cursor: int = 0
var processed_command_ids: Array[String] = []


static func create_vertical_slice(seed: int = 20260909) -> GameStateData:
	var state := GameStateData.new()
	state.seed_value = seed
	state.rng_state = DeterministicRng.new(seed).get_state()
	var player_one := PlayerStateDataType.create(&"p1", 0, "玩家一")
	var player_two := PlayerStateDataType.create(&"p2", 1, "玩家二")
	state.turn_order = [&"p1", &"p2"]
	state.players = {
		player_one.player_id: player_one,
		player_two.player_id: player_two,
	}
	state.cards = {
		&"card-monster-skeleton-01": {
			"instance_id": "card-monster-skeleton-01",
			"definition_id": "base:monster/monster-01",
			"owner_id": "",
			"state": {"target_id": "target-monster-01"},
		},
	}
	for player_id: StringName in state.turn_order:
		var player := state.players[player_id] as PlayerStateData
		_add_player_zones(state, player)
		_add_official_starting_cards(state, player)
	var monsters := ZoneDataType.new(&"shared:monster-row", &"face_up_row", &"public")
	monsters.card_instance_ids.append(&"card-monster-skeleton-01")
	monsters.metadata = {"cycle_anchor": "card-monster-skeleton-01"}
	state.zones[monsters.zone_id] = monsters
	return state


static func from_dictionary(data: Dictionary) -> GameStateData:
	var state := GameStateData.new()
	state.schema_version = int(data.get("schema_version", 1))
	state.game_id = StringName(data.get("game_id", ""))
	state.content_version = str(data.get("content_version", ""))
	state.ruleset_version = str(data.get("ruleset_version", ""))
	state.seed_value = int(data.get("seed", 0))
	state.rng_state = int(data.get("rng_state", 0))
	state.revision = int(data.get("revision", 0))
	state.status = StringName(data.get("status", ""))
	state.round_number = int(data.get("round", 1))
	state.phase = StringName(data.get("phase", "action1"))
	state.starting_player_id = StringName(data.get("starting_player_id", ""))
	state.active_player_id = StringName(data.get("active_player_id", ""))
	for player_id: Variant in data.get("turn_order", []):
		state.turn_order.append(StringName(str(player_id)))
	var serialized_players := data.get("players", {}) as Dictionary
	for player_id: Variant in serialized_players:
		var player := PlayerStateDataType.from_dictionary(serialized_players[player_id])
		state.players[player.player_id] = player
	var serialized_cards := data.get("cards", {}) as Dictionary
	for card_id: Variant in serialized_cards:
		state.cards[StringName(str(card_id))] = (serialized_cards[card_id] as Dictionary).duplicate(true)
	var serialized_zones := data.get("zones", {}) as Dictionary
	for zone_id: Variant in serialized_zones:
		var zone := ZoneDataType.from_dictionary(serialized_zones[zone_id])
		state.zones[zone.zone_id] = zone
	state.effect_state = (data.get("effect_state", {}) as Dictionary).duplicate(true)
	state.event_cursor = int(data.get("event_cursor", 0))
	for command_id: Variant in data.get("processed_command_ids", []):
		state.processed_command_ids.append(str(command_id))
	return state


func clone_state() -> GameStateData:
	var copy := GameStateData.new()
	copy.schema_version = schema_version
	copy.game_id = game_id
	copy.content_version = content_version
	copy.ruleset_version = ruleset_version
	copy.seed_value = seed_value
	copy.rng_state = rng_state
	copy.revision = revision
	copy.status = status
	copy.round_number = round_number
	copy.phase = phase
	copy.starting_player_id = starting_player_id
	copy.active_player_id = active_player_id
	copy.turn_order.assign(turn_order)
	for player_id: Variant in players:
		copy.players[player_id] = (players[player_id] as PlayerStateData).clone_player()
	copy.cards = cards.duplicate(true)
	for zone_id: Variant in zones:
		copy.zones[zone_id] = (zones[zone_id] as ZoneData).clone_zone()
	copy.effect_state = effect_state.duplicate(true)
	copy.event_cursor = event_cursor
	copy.processed_command_ids.assign(processed_command_ids)
	return copy


func to_dictionary() -> Dictionary:
	var serialized_players: Dictionary = {}
	for player_id: Variant in players:
		serialized_players[str(player_id)] = (players[player_id] as PlayerStateData).to_dictionary()
	var serialized_zones: Dictionary = {}
	for zone_id: Variant in zones:
		serialized_zones[str(zone_id)] = (zones[zone_id] as ZoneData).to_dictionary()
	var serialized_cards: Dictionary = {}
	for card_id: Variant in cards:
		serialized_cards[str(card_id)] = (cards[card_id] as Dictionary).duplicate(true)
	return {
		"schema_version": schema_version,
		"game_id": str(game_id),
		"content_version": content_version,
		"ruleset_version": ruleset_version,
		"seed": seed_value,
		# JSON numbers are doubles, so encode the 64-bit RNG state losslessly.
		"rng_state": str(rng_state),
		"revision": revision,
		"status": str(status),
		"round": round_number,
		"phase": str(phase),
		"starting_player_id": str(starting_player_id),
		"active_player_id": str(active_player_id),
		"turn_order": _string_name_array_to_strings(turn_order),
		"players": serialized_players,
		"cards": serialized_cards,
		"zones": serialized_zones,
		"effect_state": effect_state.duplicate(true),
		"event_cursor": event_cursor,
		"processed_command_ids": processed_command_ids.duplicate(),
	}


static func _add_player_zones(state: GameStateData, player: PlayerStateData) -> void:
	var zone_kinds := {
		&"draw_pile": &"ordered_deck",
		&"hand": &"hand",
		&"discard_pile": &"discard_pile",
		&"party": &"party",
		&"play_area": &"play_area",
		&"bonds": &"bonds",
	}
	for zone_key: StringName in PlayerStateData.REQUIRED_ZONE_KEYS:
		var visibility: StringName = &"owner_only" if zone_key in [&"draw_pile", &"hand", &"bonds"] else &"public"
		var zone := ZoneDataType.new(player.zone_ids[zone_key], zone_kinds[zone_key], visibility)
		zone.metadata = {"owner_id": str(player.player_id)}
		state.zones[zone.zone_id] = zone


static func _add_official_starting_cards(state: GameStateData, player: PlayerStateData) -> void:
	var party := state.zones[player.zone_ids[&"party"]] as ZoneData
	for starter_number in range(1, 6):
		var suffix := "%02d" % starter_number
		var instance_id := StringName("card-%s-starter-adventurer-%s" % [player.player_id, suffix])
		state.cards[instance_id] = {
			"instance_id": str(instance_id),
			"definition_id": "base:starter/adventurer-%s" % suffix,
			"owner_id": str(player.player_id),
			"state": {},
		}
		party.card_instance_ids.append(instance_id)

	var hand := state.zones[player.zone_ids[&"hand"]] as ZoneData
	for stone_number in range(1, 5):
		var instance_id := StringName("card-%s-summoning-stone-%02d" % [player.player_id, stone_number])
		state.cards[instance_id] = {
			"instance_id": str(instance_id),
			"definition_id": "base:starter/summoning-stone",
			"owner_id": str(player.player_id),
			"state": {},
		}
		hand.card_instance_ids.append(instance_id)
	var crystal_id := StringName("card-%s-spirit-crystal-01" % player.player_id)
	state.cards[crystal_id] = {
		"instance_id": str(crystal_id),
		"definition_id": "base:starter/spirit-crystal",
		"owner_id": str(player.player_id),
		"state": {},
	}
	hand.card_instance_ids.append(crystal_id)


static func _string_name_array_to_strings(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value: StringName in values:
		result.append(str(value))
	return result
