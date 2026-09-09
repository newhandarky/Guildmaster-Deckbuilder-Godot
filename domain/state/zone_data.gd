class_name ZoneData
extends RefCounted

var zone_id: StringName
var kind: StringName
var visibility: StringName
var card_instance_ids: Array[StringName] = []
var metadata: Dictionary = {}


func _init(
	id: StringName = &"",
	zone_kind: StringName = &"",
	zone_visibility: StringName = &"public"
) -> void:
	zone_id = id
	kind = zone_kind
	visibility = zone_visibility


func clone_zone() -> ZoneData:
	var copy := ZoneData.new(zone_id, kind, visibility)
	copy.card_instance_ids.assign(card_instance_ids)
	copy.metadata = metadata.duplicate(true)
	return copy


static func from_dictionary(data: Dictionary) -> ZoneData:
	var zone := ZoneData.new(
		StringName(data.get("zone_id", "")),
		StringName(data.get("kind", "")),
		StringName(data.get("visibility", "public"))
	)
	for instance_id: Variant in data.get("card_instance_ids", []):
		zone.card_instance_ids.append(StringName(str(instance_id)))
	zone.metadata = (data.get("metadata", {}) as Dictionary).duplicate(true)
	return zone


func to_dictionary() -> Dictionary:
	var ids: Array[String] = []
	for instance_id: StringName in card_instance_ids:
		ids.append(str(instance_id))
	return {
		"zone_id": str(zone_id),
		"kind": str(kind),
		"visibility": str(visibility),
		"card_instance_ids": ids,
		"metadata": metadata.duplicate(true),
	}
