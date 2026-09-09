class_name CardDefinition
extends Resource

@export var definition_id: StringName
@export var display_name: String
@export var card_type: StringName
@export var copies: int = 1
@export var cost: Variant = null
@export var combat: Variant = null
@export var purchase_power: Variant = null
@export var honor: Variant = null
@export var tags: Array[StringName] = []
@export var effects: Array[Dictionary] = []
@export var presentation_id: StringName


static func from_dictionary(data: Dictionary) -> CardDefinition:
	var definition := CardDefinition.new()
	definition.definition_id = StringName(data.get("definition_id", ""))
	definition.display_name = str(data.get("display_name", ""))
	definition.card_type = StringName(data.get("card_type", ""))
	definition.copies = int(data.get("copies", 1))
	definition.cost = data.get("cost", null)
	definition.combat = data.get("combat", null)
	definition.purchase_power = data.get("purchase_power", null)
	definition.honor = data.get("honor", null)
	for tag: Variant in data.get("tags", []):
		definition.tags.append(StringName(str(tag)))
	for effect: Variant in data.get("effects", []):
		if effect is Dictionary:
			definition.effects.append((effect as Dictionary).duplicate(true))
	definition.presentation_id = StringName(data.get("presentation_id", ""))
	return definition


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if definition_id.is_empty():
		errors.append("definition_id is required")
	if display_name.is_empty():
		errors.append("display_name is required for %s" % definition_id)
	if card_type.is_empty():
		errors.append("card_type is required for %s" % definition_id)
	if copies < 1:
		errors.append("copies must be positive for %s" % definition_id)
	if presentation_id.is_empty():
		errors.append("presentation_id is required for %s" % definition_id)
	return errors
