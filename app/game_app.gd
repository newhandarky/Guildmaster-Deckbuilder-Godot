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
	hud.equip_item_requested.connect(_on_equip_item_requested)
	hud.play_adventurer_requested.connect(_on_play_adventurer_requested)
	hud.use_item_requested.connect(_on_use_item_requested)
	hud.attack_target_requested.connect(_on_attack_target_requested)
	hud.buy_card_requested.connect(_on_buy_card_requested)
	hud.refresh_market_requested.connect(_on_refresh_market_requested)
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


func _on_equip_item_requested(card_instance_id: StringName, target_card_id: StringName) -> void:
	session.equip_item(card_instance_id, target_card_id)


func _on_play_adventurer_requested(card_instance_id: StringName) -> void:
	session.play_adventurer(card_instance_id)


func _on_use_item_requested(card_instance_id: StringName) -> void:
	session.use_item(card_instance_id)


func _on_attack_target_requested(target_card_id: StringName, claim_optional_reward: bool) -> void:
	session.attack_target(target_card_id, claim_optional_reward)


func _on_buy_card_requested(card_instance_id: StringName, source_row_id: StringName) -> void:
	session.buy_card(card_instance_id, source_row_id)


func _on_refresh_market_requested(
	discard_card_id: StringName,
	row_id: StringName,
	card_instance_ids: Array[StringName]
) -> void:
	session.refresh_market(discard_card_id, row_id, card_instance_ids)


func _on_events_committed(events: Array[Dictionary]) -> void:
	hud.show_events(events)
	animation_director.play_events(events)
