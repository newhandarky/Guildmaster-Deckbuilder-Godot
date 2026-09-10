class_name ContentRegistry
extends RefCounted

const CardDefinitionType = preload("res://content/definitions/card_definition.gd")
const BossRuleEvaluatorType = preload("res://domain/rules/boss_rule_evaluator.gd")

var pack_id: StringName
var pack_version: String
var pack_fingerprint: String
var definitions: Dictionary = {}


func load_pack(path: String) -> PackedStringArray:
	var errors := PackedStringArray()
	pack_id = &""
	pack_version = ""
	pack_fingerprint = ""
	definitions.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Unable to open content pack: %s" % path)
		return errors
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		errors.append("Content pack root must be a Dictionary")
		return errors
	var root := parsed as Dictionary
	if not root.get("manifest", {}) is Dictionary:
		errors.append("Content pack manifest must be a Dictionary")
		return errors
	if not root.get("definitions", []) is Array:
		errors.append("Content pack definitions must be an Array")
		return errors
	var manifest := root.get("manifest", {}) as Dictionary
	pack_id = StringName(manifest.get("pack_id", ""))
	pack_version = str(manifest.get("version", ""))
	pack_fingerprint = CanonicalJson.sha256(root)
	if bool(manifest.get("includes_custom_adventurers", true)):
		errors.append("Vertical slice must not include custom adventurers")
	for raw_definition: Variant in root.get("definitions", []):
		if not raw_definition is Dictionary:
			errors.append("Card definition must be a Dictionary")
			continue
		var definition: CardDefinition = CardDefinitionType.from_dictionary(raw_definition)
		errors.append_array(definition.validate())
		errors.append_array(EffectResolver.validate_effects(definition.effects, definition.definition_id))
		errors.append_array(BossRuleEvaluatorType.validate_rules(definition))
		if definitions.has(definition.definition_id):
			errors.append("Duplicate definition_id: %s" % definition.definition_id)
		else:
			definitions[definition.definition_id] = definition
	if pack_id.is_empty():
		errors.append("Content pack requires pack_id")
	if pack_version.is_empty():
		errors.append("Content pack requires version")
	return errors


func get_definition(definition_id: StringName) -> CardDefinition:
	return definitions.get(definition_id) as CardDefinition


func to_public_dictionary() -> Dictionary:
	var result: Dictionary = {}
	for definition_id: Variant in definitions:
		result[str(definition_id)] = (definitions[definition_id] as CardDefinition).to_dictionary()
	return result
