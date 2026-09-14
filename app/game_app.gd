class_name GameApp
extends Node


@onready var animation_director: AnimationDirector = %AnimationDirector
@onready var hud: GameHud = %HUD
@onready var player_token: SelectableToken = %PlayerToken
@onready var enemy_token: SelectableToken = %EnemyToken

var session := GameSession.new()
var enable_helpers := true
var enable_cpu := true
var cpu_orchestrator := CpuSessionOrchestrator.new()
var _cpu_advancing := false
var _cpu_advance_scheduled := false


func _ready() -> void:
	animation_director.register_entity(player_token.entity_id, player_token)
	animation_director.register_entity(enemy_token.entity_id, enemy_token)
	player_token.selected.connect(_on_entity_selected)
	enemy_token.selected.connect(_on_entity_selected)
	hud.end_phase_requested.connect(_on_end_phase_requested)
	hud.equip_item_requested.connect(_on_equip_item_requested)
	hud.activate_equipment_effect_requested.connect(_on_activate_equipment_effect_requested)
	hud.play_adventurer_requested.connect(_on_play_adventurer_requested)
	hud.use_item_requested.connect(_on_use_item_requested)
	hud.attack_target_requested.connect(_on_attack_target_requested)
	hud.resolve_choice_requested.connect(_on_resolve_choice_requested)
	hud.buy_card_requested.connect(_on_buy_card_requested)
	hud.refresh_market_requested.connect(_on_refresh_market_requested)
	hud.skip_animation_requested.connect(animation_director.skip_all)
	session.private_view_changed.connect(_on_private_view_changed)
	session.events_committed.connect(_on_events_committed)
	session.state_changed.connect(_schedule_cpu_advance)
	session.command_rejected.connect(hud.show_error)
	var errors := session.start_new_game(
		20260909, enable_helpers, enable_helpers, 4 if enable_cpu else 2
	)
	if not errors.is_empty():
		push_error("Unable to start vertical slice: %s" % "; ".join(errors))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("skip_animation"):
		animation_director.skip_all()
		get_viewport().set_input_as_handled()


func _on_entity_selected(entity_id: StringName, display_name: String, details: String) -> void:
	hud.show_entity(display_name, details)
	animation_director.play_selection(entity_id)


func _on_private_view_changed(_viewer_id: StringName, private_state: Dictionary) -> void:
	if enable_cpu:
		hud.update_state(session.get_ui_view(&"p1"))
	else:
		hud.update_state(private_state)


func _schedule_cpu_advance(_public_state: Dictionary) -> void:
	if not enable_cpu or _cpu_advancing or _cpu_advance_scheduled:
		return
	_cpu_advance_scheduled = true
	_run_cpu_advance.call_deferred()


func _run_cpu_advance() -> void:
	_cpu_advance_scheduled = false
	if _cpu_advancing:
		return
	_cpu_advancing = true
	var result := cpu_orchestrator.advance(session, &"p1")
	_cpu_advancing = false
	if not bool(result.get("ok", false)):
		hud.show_error("CPU 對局暫停：%s" % result.get("error", "unknown"))


func _on_end_phase_requested() -> void:
	if _human_can_act():
		session.end_phase()


func _on_equip_item_requested(card_instance_id: StringName, target_card_id: StringName) -> void:
	if _human_can_act():
		session.equip_item(card_instance_id, target_card_id)


func _on_activate_equipment_effect_requested(
	card_instance_id: StringName, effect_index: int
) -> void:
	if _human_can_act():
		session.activate_equipment_effect(card_instance_id, effect_index)


func _on_play_adventurer_requested(card_instance_id: StringName) -> void:
	if _human_can_act():
		session.play_adventurer(card_instance_id)


func _on_use_item_requested(card_instance_id: StringName) -> void:
	if _human_can_act():
		session.use_item(card_instance_id)


func _on_attack_target_requested(
	target_card_id: StringName,
	claim_optional_reward: bool,
	use_optional_departures: bool
) -> void:
	if _human_can_act():
		session.attack_target(target_card_id, claim_optional_reward, use_optional_departures)


func _on_resolve_choice_requested(
	choice_id: String,
	card_instance_id: StringName,
	skip: bool
) -> void:
	if _human_can_act():
		session.resolve_choice(choice_id, card_instance_id, skip)


func _on_buy_card_requested(card_instance_id: StringName, source_row_id: StringName) -> void:
	if _human_can_act():
		session.buy_card(card_instance_id, source_row_id)


func _on_refresh_market_requested(
	discard_card_id: StringName,
	row_id: StringName,
	card_instance_ids: Array[StringName]
) -> void:
	if _human_can_act():
		session.refresh_market(discard_card_id, row_id, card_instance_ids)


func _human_can_act() -> bool:
	return not enable_cpu or not session.get_legal_commands(&"p1").is_empty()


func _on_events_committed(events: Array[Dictionary]) -> void:
	hud.show_events(events)
	animation_director.play_events(events)
