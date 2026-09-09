class_name GameHud
extends Control

signal end_phase_requested
signal skip_animation_requested

@onready var round_label: Label = %RoundLabel
@onready var phase_label: Label = %PhaseLabel
@onready var revision_label: Label = %RevisionLabel
@onready var detail_panel: PanelContainer = %DetailPanel
@onready var detail_title: Label = %DetailTitle
@onready var detail_body: Label = %DetailBody
@onready var event_label: Label = %EventLabel
@onready var end_phase_button: Button = %EndPhaseButton
@onready var skip_button: Button = %SkipButton


func _ready() -> void:
	end_phase_button.pressed.connect(end_phase_requested.emit)
	skip_button.pressed.connect(skip_animation_requested.emit)
	end_phase_button.focus_neighbor_right = skip_button.get_path()
	skip_button.focus_neighbor_left = end_phase_button.get_path()
	end_phase_button.grab_focus()
	detail_panel.hide()


func update_state(state: Dictionary) -> void:
	round_label.text = "回合 %d" % int(state.get("round", 1))
	phase_label.text = "階段：%s" % _localized_phase(str(state.get("phase", "")))
	revision_label.text = "Revision %d" % int(state.get("revision", 0))


func show_entity(display_name: String, details: String) -> void:
	detail_title.text = display_name
	detail_body.text = details
	detail_panel.show()


func show_events(events: Array[Dictionary]) -> void:
	if events.is_empty():
		return
	var event: Dictionary = events.back()
	if event.get("type") == "phase_changed":
		event_label.text = "%s → %s" % [
			_localized_phase(str(event.get("from_phase", ""))),
			_localized_phase(str(event.get("to_phase", ""))),
		]


func show_error(error_code: String) -> void:
	event_label.text = "命令失敗：%s" % error_code


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and detail_panel.visible:
		detail_panel.hide()
		get_viewport().set_input_as_handled()


func _localized_phase(phase_name: String) -> String:
	return {
		"action1": "第一行動",
		"combat": "討伐",
		"action2": "第二行動",
		"purchase": "購買",
		"rest": "休息",
	}.get(phase_name, phase_name)
