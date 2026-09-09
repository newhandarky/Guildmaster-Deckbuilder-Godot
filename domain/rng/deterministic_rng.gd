class_name DeterministicRng
extends RefCounted

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 1, saved_state: int = 0) -> void:
	_rng.seed = seed_value
	if saved_state != 0:
		_rng.state = saved_state


func roll_die(sides: int = 6) -> int:
	assert(sides > 0)
	return _rng.randi_range(1, sides)


func shuffle(values: Array) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var temporary: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = temporary


func get_state() -> int:
	return _rng.state
