class_name ContentRegistry
extends RefCounted

const CardDefinitionType = preload("res://content/definitions/card_definition.gd")
const BossRuleEvaluatorType = preload("res://domain/rules/boss_rule_evaluator.gd")
const BOND_PACK_PATH := "res://content/packs/official_bonds.json"

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
	var bond_file := FileAccess.open(BOND_PACK_PATH, FileAccess.READ)
	if bond_file == null:
		errors.append("Unable to open bond pack: %s" % BOND_PACK_PATH)
		return errors
	var bond_pack: Variant = JSON.parse_string(bond_file.get_as_text())
	if not bond_pack is Dictionary or not (bond_pack as Dictionary).get("definitions", []) is Array:
		errors.append("Bond pack requires definitions")
		return errors
	if not root.get("manifest", {}) is Dictionary:
		errors.append("Content pack manifest must be a Dictionary")
		return errors
	if not root.get("definitions", []) is Array:
		errors.append("Content pack definitions must be an Array")
		return errors
	var manifest := root.get("manifest", {}) as Dictionary
	pack_id = StringName(manifest.get("pack_id", ""))
	pack_version = str(manifest.get("version", ""))
	pack_fingerprint = CanonicalJson.sha256({"base": root, "bonds": bond_pack})
	if bool(manifest.get("includes_custom_adventurers", true)):
		errors.append("Vertical slice must not include custom adventurers")
	var all_definitions := (root.get("definitions", []) as Array).duplicate()
	var bond_definitions := (bond_pack as Dictionary).get("definitions", []) as Array
	if bond_definitions.size() != 30:
		errors.append("Official bond pack must contain exactly 30 definitions")
	for index in bond_definitions.size():
		var raw_bond := bond_definitions[index] as Dictionary
		if raw_bond == null or str(raw_bond.get("definition_id", "")) \
				!= "base:bond/bond-%02d" % (index + 1) \
				or str(raw_bond.get("card_type", "")) != "bond" \
				or int(raw_bond.get("copies", 0)) != 1 \
				or raw_bond.get("honor", null) == null \
				or not raw_bond.get("completion_rule", {}) is Dictionary \
				or (raw_bond.get("completion_rule", {}) as Dictionary).is_empty():
			errors.append("Invalid official bond definition at index %d" % index)
	all_definitions.append_array(bond_definitions)
	for raw_definition: Variant in all_definitions:
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
