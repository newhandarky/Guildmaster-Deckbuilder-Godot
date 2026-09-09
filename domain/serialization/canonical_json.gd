class_name CanonicalJson
extends RefCounted


static func stringify(value: Variant) -> String:
	return JSON.stringify(_canonicalize(value))


static func sha256(value: Variant) -> String:
	return stringify(value).sha256_text()


static func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var source := value as Dictionary
		var keys: Array = source.keys()
		keys.sort_custom(func(left: Variant, right: Variant) -> bool: return str(left) < str(right))
		var result: Dictionary = {}
		for key: Variant in keys:
			result[str(key)] = _canonicalize(source[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_canonicalize(item))
		return result
	if value is StringName:
		return str(value)
	return value
