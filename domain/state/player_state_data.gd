class_name PlayerStateData
extends RefCounted

const REQUIRED_ZONE_KEYS: Array[StringName] = [
	&"draw_pile",
	&"hand",
	&"discard_pile",
	&"party",
	&"equipment",
	&"play_area",
	&"bonds",
	&"removed",
]

var player_id: StringName
var seat_index: int
var display_name: String
var zone_ids: Dictionary = {}
var turn_resources: Dictionary = {"combat": 0, "purchase_power": 0}
var spent_purchase_power: int = 0
var turn_bonuses: Dictionary = {}
var counters: Dictionary = {}
var module_state: Dictionary = {}
var turn_facts: Dictionary = {}


static func create(id: StringName, seat: int, name: String) -> PlayerStateData:
	var player := PlayerStateData.new()
	player.player_id = id
	player.seat_index = seat
	player.display_name = name
	player.zone_ids = {
		&"draw_pile": StringName("%s:draw-pile" % id),
		&"hand": StringName("%s:hand" % id),
		&"discard_pile": StringName("%s:discard-pile" % id),
		&"party": StringName("%s:party" % id),
		&"equipment": StringName("%s:equipment" % id),
		&"play_area": StringName("%s:play-area" % id),
		&"bonds": StringName("%s:bonds" % id),
		&"removed": StringName("%s:removed" % id),
	}
	return player


static func from_dictionary(data: Dictionary) -> PlayerStateData:
	var player := PlayerStateData.new()
	player.player_id = StringName(data.get("player_id", ""))
	player.seat_index = int(data.get("seat_index", -1))
	player.display_name = str(data.get("display_name", ""))
	var serialized_zone_ids := data.get("zone_ids", {}) as Dictionary
	for zone_key: Variant in serialized_zone_ids:
		player.zone_ids[StringName(str(zone_key))] = StringName(str(serialized_zone_ids[zone_key]))
	player.turn_resources = (data.get("turn_resources", {}) as Dictionary).duplicate(true)
	player.spent_purchase_power = int(data.get("spent_purchase_power", 0))
	player.turn_bonuses = (data.get("turn_bonuses", {}) as Dictionary).duplicate(true)
	player.counters = (data.get("counters", {}) as Dictionary).duplicate(true)
	player.module_state = (data.get("module_state", {}) as Dictionary).duplicate(true)
	player.turn_facts = (data.get("turn_facts", {}) as Dictionary).duplicate(true)
	return player


func clone_player() -> PlayerStateData:
	return PlayerStateData.from_dictionary(to_dictionary())


func reset_turn_scope() -> void:
	turn_resources = {"combat": 0, "purchase_power": 0}
	spent_purchase_power = 0
	turn_bonuses.clear()
	turn_facts.clear()


func to_dictionary() -> Dictionary:
	var serialized_zone_ids: Dictionary = {}
	for zone_key: Variant in zone_ids:
		serialized_zone_ids[str(zone_key)] = str(zone_ids[zone_key])
	return {
		"player_id": str(player_id),
		"seat_index": seat_index,
		"display_name": display_name,
		"zone_ids": serialized_zone_ids,
		"turn_resources": turn_resources.duplicate(true),
		"spent_purchase_power": spent_purchase_power,
		"turn_bonuses": turn_bonuses.duplicate(true),
		"counters": counters.duplicate(true),
		"module_state": module_state.duplicate(true),
		"turn_facts": turn_facts.duplicate(true),
	}
