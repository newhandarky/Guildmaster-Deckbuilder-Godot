class_name SelectableToken
extends Area3D

signal selected(entity_id: StringName, display_name: String, details: String)

@export var entity_id: StringName
@export var display_name: String
@export_multiline var details: String
@export var base_color := Color(0.35, 0.75, 1.0)

@onready var mesh_instance: MeshInstance3D = $Mesh


func _ready() -> void:
	input_ray_pickable = true
	var material := StandardMaterial3D.new()
	material.albedo_color = base_color
	material.metallic = 0.25
	material.roughness = 0.35
	mesh_instance.material_override = material
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	input_event.connect(_on_input_event)


func _on_input_event(
	_camera: Node,
	event: InputEvent,
	_event_position: Vector3,
	_normal: Vector3,
	_shape_idx: int
) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			selected.emit(entity_id, display_name, details)


func _set_hovered(hovered: bool) -> void:
	var material := mesh_instance.material_override as StandardMaterial3D
	material.emission_enabled = hovered
	material.emission = base_color.lightened(0.25)
	material.emission_energy_multiplier = 1.8 if hovered else 0.0
