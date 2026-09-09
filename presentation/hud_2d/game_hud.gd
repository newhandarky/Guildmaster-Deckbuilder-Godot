class_name GameHud
extends Control

signal end_phase_requested
signal skip_animation_requested
signal equip_item_requested(card_instance_id: StringName, target_card_id: StringName)
signal play_adventurer_requested(card_instance_id: StringName)
signal use_item_requested(card_instance_id: StringName)
signal buy_card_requested(card_instance_id: StringName, source_row_id: StringName)

@onready var round_label: Label = %RoundLabel
@onready var phase_label: Label = %PhaseLabel
@onready var active_player_label: Label = %ActivePlayerLabel
@onready var revision_label: Label = %RevisionLabel
@onready var resource_label: Label = %ResourceLabel
@onready var detail_panel: PanelContainer = %DetailPanel
@onready var detail_title: Label = %DetailTitle
@onready var detail_body: Label = %DetailBody
@onready var event_label: Label = %EventLabel
@onready var end_phase_button: Button = %EndPhaseButton
@onready var skip_button: Button = %SkipButton
@onready var hand_summary: Label = %HandSummary
@onready var hand_actions: VBoxContainer = %HandActions
@onready var market_summary: Label = %MarketSummary
@onready var market_actions: VBoxContainer = %MarketActions

var _cards: Dictionary = {}
var _definitions: Dictionary = {}


func _ready() -> void:
	end_phase_button.pressed.connect(end_phase_requested.emit)
	skip_button.pressed.connect(skip_animation_requested.emit)
	end_phase_button.focus_neighbor_right = skip_button.get_path()
	skip_button.focus_neighbor_left = end_phase_button.get_path()
	end_phase_button.grab_focus()
	detail_panel.hide()


func update_state(state: Dictionary) -> void:
	_cards = (state.get("cards", {}) as Dictionary).duplicate(true)
	_definitions = (state.get("definitions", {}) as Dictionary).duplicate(true)
	round_label.text = "回合 %d" % int(state.get("round", 1))
	phase_label.text = "階段：%s" % _localized_phase(str(state.get("phase", "")))
	var active_player_id := str(state.get("active_player_id", ""))
	var players := state.get("players", {}) as Dictionary
	var active_player := players.get(active_player_id, {}) as Dictionary
	active_player_label.text = "目前玩家：%s" % str(active_player.get("display_name", active_player_id))
	revision_label.text = "Revision %d" % int(state.get("revision", 0))
	var resources := state.get("active_resources", {}) as Dictionary
	resource_label.text = "隊伍戰力：%d　購買力：%d" % [
		int(resources.get("combat", 0)),
		int(resources.get("purchase_power", 0)),
	]
	_rebuild_hand(state, active_player_id)
	_rebuild_market(state)


func show_entity(display_name: String, details: String) -> void:
	detail_title.text = display_name
	detail_body.text = details
	detail_panel.show()


func show_events(events: Array[Dictionary]) -> void:
	if events.is_empty():
		return
	for index in range(events.size() - 1, -1, -1):
		var event := events[index] as Dictionary
		if event.get("type") == "item_used":
			event_label.text = "道具已使用：%s" % _card_display_name(
				str(event.get("card_instance_id", ""))
			)
			return
		if event.get("type") == "adventurer_joined_party":
			event_label.text = "冒險者加入：%s" % _card_display_name(
				str(event.get("card_instance_id", ""))
			)
			return
		if event.get("type") == "card_purchased":
			event_label.text = "購買完成：%s（花費 %d）" % [
				_card_display_name(str(event.get("card_instance_id", ""))),
				int(event.get("cost", 0)),
			]
			return
		if event.get("type") == "card_equipped":
			event_label.text = "裝備已配戴：%s → %s" % [
				_card_display_name(str(event.get("card_instance_id", ""))),
				_card_display_name(str(event.get("target_card_id", ""))),
			]
			return
		if event.get("type") == "active_player_changed":
			event_label.text = "%s 結束回合 → %s 開始" % [
				str(event.get("from_player_id", "")),
				str(event.get("to_player_id", "")),
			]
			return
		if event.get("type") == "phase_changed":
			event_label.text = "%s → %s" % [
				_localized_phase(str(event.get("from_phase", ""))),
				_localized_phase(str(event.get("to_phase", ""))),
			]
			return


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


func _rebuild_hand(state: Dictionary, active_player_id: String) -> void:
	for child: Node in hand_actions.get_children():
		hand_actions.remove_child(child)
		child.queue_free()
	var players := state.get("players", {}) as Dictionary
	var player := players.get(active_player_id, {}) as Dictionary
	var zone_ids := player.get("zone_ids", {}) as Dictionary
	var zones := state.get("zones", {}) as Dictionary
	var hand := zones.get(str(zone_ids.get("hand", "")), {}) as Dictionary
	var card_ids := hand.get("card_instance_ids", []) as Array
	var cards := state.get("cards", {}) as Dictionary
	var definitions := state.get("definitions", {}) as Dictionary
	var legal_commands := state.get("legal_commands", []) as Array
	var action_buttons: Array[Button] = []
	hand_summary.text = "目前手牌：%d 張" % card_ids.size()

	for raw_card_id: Variant in card_ids:
		var card_id := str(raw_card_id)
		var card := cards.get(card_id, {}) as Dictionary
		var definition := definitions.get(str(card.get("definition_id", "")), {}) as Dictionary
		var card_label := Label.new()
		card_label.text = _hand_card_text(definition)
		card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hand_actions.add_child(card_label)
		var simple_action_added := false
		for raw_command: Variant in legal_commands:
			if not raw_command is Dictionary:
				continue
			var command := raw_command as Dictionary
			if str(command.get("card_instance_id", "")) != card_id:
				continue
			var command_type := str(command.get("type", ""))
			if command_type == "EQUIP_ITEM":
				var target_id := str(command.get("target_card_id", ""))
				var target_card := cards.get(target_id, {}) as Dictionary
				var target_definition := definitions.get(
					str(target_card.get("definition_id", "")), {}
				) as Dictionary
				var equip_button := Button.new()
				equip_button.text = "配戴給 %s" % str(
					target_definition.get("display_name", target_id)
				)
				equip_button.custom_minimum_size = Vector2(0.0, 36.0)
				equip_button.focus_mode = Control.FOCUS_ALL
				equip_button.pressed.connect(
					equip_item_requested.emit.bind(StringName(card_id), StringName(target_id))
				)
				hand_actions.add_child(equip_button)
				action_buttons.append(equip_button)
			elif not simple_action_added and command_type in ["PLAY_ADVENTURER", "USE_ITEM"]:
				var action_button := Button.new()
				action_button.text = "加入隊伍" if command_type == "PLAY_ADVENTURER" else "使用"
				action_button.custom_minimum_size = Vector2(0.0, 36.0)
				action_button.focus_mode = Control.FOCUS_ALL
				if command_type == "PLAY_ADVENTURER":
					action_button.pressed.connect(
						play_adventurer_requested.emit.bind(StringName(card_id))
					)
				else:
					action_button.pressed.connect(
						use_item_requested.emit.bind(StringName(card_id))
					)
				hand_actions.add_child(action_button)
				action_buttons.append(action_button)
				simple_action_added = true

	end_phase_button.focus_neighbor_top = NodePath()
	skip_button.focus_neighbor_top = NodePath()
	for index in action_buttons.size():
		var button := action_buttons[index]
		button.focus_neighbor_top = (
			end_phase_button.get_path()
			if index == 0
			else action_buttons[index - 1].get_path()
		)
		button.focus_neighbor_bottom = (
			end_phase_button.get_path()
			if index == action_buttons.size() - 1
			else action_buttons[index + 1].get_path()
		)
	if not action_buttons.is_empty():
		end_phase_button.focus_neighbor_top = action_buttons.back().get_path()
		skip_button.focus_neighbor_top = action_buttons.back().get_path()


func _hand_card_text(definition: Dictionary) -> String:
	var text := str(definition.get("display_name", "未知卡片"))
	var purchase_power: Variant = definition.get("purchase_power", null)
	var combat: Variant = definition.get("combat", null)
	if purchase_power != null:
		text += "｜購買力 %d（購買階段自動計算）" % int(purchase_power)
	if combat != null:
		text += "｜戰力 %d" % int(combat)
	return text


func _card_display_name(card_instance_id: String) -> String:
	var card := _cards.get(card_instance_id, {}) as Dictionary
	var definition := _definitions.get(str(card.get("definition_id", "")), {}) as Dictionary
	return str(definition.get("display_name", card_instance_id))


func _rebuild_market(state: Dictionary) -> void:
	for child: Node in market_actions.get_children():
		market_actions.remove_child(child)
		child.queue_free()
	var zones := state.get("zones", {}) as Dictionary
	var legal_commands := state.get("legal_commands", []) as Array
	var market_buttons: Array[Button] = []
	var row_specs := [
		["shared:recruit-row", "招募區"],
		["shared:shop-row", "商店"],
	]
	var total_cards := 0
	for row_spec: Array in row_specs:
		var row_id := str(row_spec[0])
		var row := zones.get(row_id, {}) as Dictionary
		var card_ids := row.get("card_instance_ids", []) as Array
		total_cards += card_ids.size()
		var title := Label.new()
		title.text = "%s（%d/3）" % [str(row_spec[1]), card_ids.size()]
		title.add_theme_color_override("font_color", Color(0.72, 0.88, 1.0))
		market_actions.add_child(title)
		for raw_card_id: Variant in card_ids:
			var card_id := str(raw_card_id)
			var definition := _definition_for_instance(card_id)
			var cost: Variant = definition.get("cost", null)
			var row_box := HBoxContainer.new()
			var label := Label.new()
			label.text = "%s｜費用 %s" % [
				str(definition.get("display_name", card_id)),
				"—" if cost == null else str(int(cost)),
			]
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row_box.add_child(label)
			var legal := _find_buy_command(legal_commands, card_id, row_id)
			if not legal.is_empty():
				var buy_button := Button.new()
				buy_button.text = "購買"
				buy_button.custom_minimum_size = Vector2(78.0, 32.0)
				buy_button.pressed.connect(
					buy_card_requested.emit.bind(StringName(card_id), StringName(row_id))
				)
				row_box.add_child(buy_button)
				market_buttons.append(buy_button)
			market_actions.add_child(row_box)
	market_summary.text = "公開卡：%d　購買只在購買階段開放" % total_cards

	skip_button.focus_neighbor_right = NodePath()
	for index in market_buttons.size():
		var button := market_buttons[index]
		button.focus_neighbor_top = (
			skip_button.get_path() if index == 0 else market_buttons[index - 1].get_path()
		)
		button.focus_neighbor_bottom = (
			skip_button.get_path()
			if index == market_buttons.size() - 1
			else market_buttons[index + 1].get_path()
		)
	if not market_buttons.is_empty():
		skip_button.focus_neighbor_right = market_buttons[0].get_path()
		market_buttons[0].focus_neighbor_left = skip_button.get_path()


func _definition_for_instance(card_instance_id: String) -> Dictionary:
	var card := _cards.get(card_instance_id, {}) as Dictionary
	return _definitions.get(str(card.get("definition_id", "")), {}) as Dictionary


func _find_buy_command(commands: Array, card_instance_id: String, row_id: String) -> Dictionary:
	for raw_command: Variant in commands:
		if not raw_command is Dictionary:
			continue
		var command := raw_command as Dictionary
		if command.get("type") == "BUY_CARD" \
				and str(command.get("card_instance_id", "")) == card_instance_id \
				and str(command.get("source_row_id", "")) == row_id:
			return command
	return {}
