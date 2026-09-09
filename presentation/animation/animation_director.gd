class_name AnimationDirector
extends Node

signal queue_finished

var _active_tweens: Array[Tween] = []
var _entity_nodes: Dictionary = {}


func register_entity(entity_id: StringName, node: Node3D) -> void:
	_entity_nodes[entity_id] = node


func play_events(events: Array[Dictionary]) -> void:
	for event: Dictionary in events:
		match StringName(event.get("type", "")):
			&"phase_changed":
				_pulse_all()
			_:
				pass
	if _active_tweens.is_empty():
		queue_finished.emit()


func play_selection(entity_id: StringName) -> void:
	var target := _entity_nodes.get(entity_id) as Node3D
	if target == null:
		return
	var start_position := target.position
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_tweens.append(tween)
	tween.tween_property(target, "position:y", start_position.y + 0.35, 0.16)
	tween.tween_property(target, "position:y", start_position.y, 0.24)
	tween.finished.connect(_on_tween_finished.bind(tween))


func skip_all() -> void:
	for tween: Tween in _active_tweens.duplicate():
		if tween != null and tween.is_valid():
			tween.custom_step(1000.0)
	_active_tweens.clear()
	queue_finished.emit()


func _pulse_all() -> void:
	for entity_id: Variant in _entity_nodes:
		var target := _entity_nodes[entity_id] as Node3D
		var tween := create_tween().set_trans(Tween.TRANS_SINE)
		_active_tweens.append(tween)
		tween.tween_property(target, "scale", Vector3.ONE * 1.12, 0.12)
		tween.tween_property(target, "scale", Vector3.ONE, 0.18)
		tween.finished.connect(_on_tween_finished.bind(tween))


func _on_tween_finished(tween: Tween) -> void:
	_active_tweens.erase(tween)
	if _active_tweens.is_empty():
		queue_finished.emit()
