class_name GameStateData
extends RefCounted

const ZoneDataType = preload("res://domain/state/zone_data.gd")

var schema_version: int = 1
var game_id: StringName = &"game-demo-001"
var content_version: String = "0.1.0"
var ruleset_version: String = "0.1.0"
var seed_value: int = 20260909
var rng_state: int = 0
var revision: int = 0
var status: StringName = &"active"
var round_number: int = 1
var phase: StringName = &"action1"
var starting_player_id: StringName = &"p1"
var active_player_id: StringName = &"p1"
var cards: Dictionary = {}
var zones: Dictionary = {}
var effect_state: Dictionary = {}
var event_cursor: int = 0
var processed_command_ids: Array[String] = []


static func create_vertical_slice(seed: int = 20260909) -> GameStateData:
	var state := GameStateData.new()
	state.seed_value = seed
	state.rng_state = seed
	state.cards = {
		&"card-starter-melee-01": {
			"instance_id": "card-starter-melee-01",
			"definition_id": "base:starter/adventurer-01",
			"owner_id": "p1",
			"state": {},
		},
		&"card-monster-skeleton-01": {
			"instance_id": "card-monster-skeleton-01",
			"definition_id": "base:monster/monster-01",
			"owner_id": "",
			"state": {"target_id": "target-monster-01"},
		},
	}
	var party := ZoneDataType.new(&"p1:party", &"party", &"public")
	party.card_instance_ids.append(&"card-starter-melee-01")
	var monsters := ZoneDataType.new(&"shared:monster-row", &"face_up_row", &"public")
	monsters.card_instance_ids.append(&"card-monster-skeleton-01")
	monsters.metadata = {"cycle_anchor": "card-monster-skeleton-01"}
	state.zones = {
		party.zone_id: party,
		monsters.zone_id: monsters,
	}
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
	copy.cards = cards.duplicate(true)
	for zone_id: Variant in zones:
		copy.zones[zone_id] = (zones[zone_id] as ZoneData).clone_zone()
	copy.effect_state = effect_state.duplicate(true)
	copy.event_cursor = event_cursor
	copy.processed_command_ids.assign(processed_command_ids)
	return copy


func to_dictionary() -> Dictionary:
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
		"rng_state": rng_state,
		"revision": revision,
		"status": str(status),
		"round": round_number,
		"phase": str(phase),
		"starting_player_id": str(starting_player_id),
		"active_player_id": str(active_player_id),
		"cards": serialized_cards,
		"zones": serialized_zones,
		"effect_state": effect_state.duplicate(true),
		"event_cursor": event_cursor,
		"processed_command_ids": processed_command_ids.duplicate(),
	}
