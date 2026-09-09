class_name GameApp
extends Node

@onready var animation_director: AnimationDirector = %AnimationDirector
@onready var hud: GameHud = %HUD
@onready var player_token: SelectableToken = %PlayerToken
@onready var enemy_token: SelectableToken = %EnemyToken

var session := GameSession.new()


func _ready() -> void:
	animation_director.register_entity(player_token.entity_id, player_token)
	animation_director.register_entity(enemy_token.entity_id, enemy_token)
	player_token.selected.connect(_on_entity_selected)
	enemy_token.selected.connect(_on_entity_selected)
	hud.end_phase_requested.connect(_on_end_phase_requested)
	hud.skip_animation_requested.connect(animation_director.skip_all)
	session.state_changed.connect(hud.update_state)
	session.events_committed.connect(_on_events_committed)
	session.command_rejected.connect(hud.show_error)
	var errors := session.start_new_game()
	if not errors.is_empty():
		push_error("Unable to start vertical slice: %s" % "; ".join(errors))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("skip_animation"):
		animation_director.skip_all()
		get_viewport().set_input_as_handled()


func _on_entity_selected(entity_id: StringName, display_name: String, details: String) -> void:
	hud.show_entity(display_name, details)
	animation_director.play_selection(entity_id)


func _on_end_phase_requested() -> void:
	session.end_phase()


func _on_events_committed(events: Array[Dictionary]) -> void:
	hud.show_events(events)
	animation_director.play_events(events)
