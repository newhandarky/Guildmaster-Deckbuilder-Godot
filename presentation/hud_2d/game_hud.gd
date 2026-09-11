class_name GameHud
extends Control

signal end_phase_requested
signal skip_animation_requested
signal equip_item_requested(card_instance_id: StringName, target_card_id: StringName)
signal play_adventurer_requested(card_instance_id: StringName)
signal use_item_requested(card_instance_id: StringName)
signal attack_target_requested(
	target_card_id: StringName,
	claim_optional_reward: bool,
	use_optional_departures: bool
)
signal resolve_choice_requested(choice_id: String, card_instance_id: StringName, skip: bool)
signal buy_card_requested(card_instance_id: StringName, source_row_id: StringName)
signal refresh_market_requested(
	discard_card_id: StringName,
	row_id: StringName,
	card_instance_ids: Array[StringName]
)

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
@onready var hand_title: Label = %HandTitle
@onready var hand_summary: Label = %HandSummary
@onready var hand_actions: VBoxContainer = %HandActions
@onready var market_summary: Label = %MarketSummary
@onready var market_actions: VBoxContainer = %MarketActions

var _cards: Dictionary = {}
var _definitions: Dictionary = {}
var _current_state: Dictionary = {}
var _refresh_revision := -1
var _refresh_discard_id := &""
var _refresh_row_id := &""
var _refresh_selected_ids: Array[StringName] = []


func _ready() -> void:
	end_phase_button.pressed.connect(end_phase_requested.emit)
	skip_button.pressed.connect(skip_animation_requested.emit)
	end_phase_button.focus_neighbor_right = skip_button.get_path()
	skip_button.focus_neighbor_left = end_phase_button.get_path()
	end_phase_button.grab_focus()
	detail_panel.hide()


func update_state(state: Dictionary) -> void:
	_current_state = state.duplicate(true)
	var revision := int(state.get("revision", 0))
	if revision != _refresh_revision:
		_refresh_revision = revision
		_clear_refresh_selection()
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
	var legal_commands := state.get("legal_commands", []) as Array
	end_phase_button.disabled = not _commands_contain_type(legal_commands, "END_PHASE")
	end_phase_button.text = (
		"請先完成選擇" if not state.get("effect_state", {}).is_empty() else "結束目前階段"
	)
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
		var roll_event := events[index] as Dictionary
		if roll_event.get("type") == "die_rolled":
			event_label.text = "%s擲出 %d（D%d），獲得 %d 購買力" % [
				_card_display_name(str(roll_event.get("source_card_instance_id", ""))),
				int(roll_event.get("die_result", 0)),
				int(roll_event.get("die_sides", 0)),
				int(roll_event.get("amount", 0)),
			]
			return
	for index in range(events.size() - 1, -1, -1):
		var event := events[index] as Dictionary
		if event.get("type") == "boss_revealed":
			event_label.text = "Boss 揭示：%s" % _card_display_name(
				str(event.get("card_instance_id", ""))
			)
			return
		if event.get("type") == "boss_defeated":
			event_label.text = "Boss 討伐成功：%s" % _card_display_name(
				str(event.get("target_card_id", ""))
			)
			return
		if event.get("type") == "enemy_defeated":
			event_label.text = "討伐成功：%s（%d 名參戰者）" % [
				_card_display_name(str(event.get("target_card_id", ""))),
				(event.get("participant_ids", []) as Array).size(),
			]
			return
		if event.get("type") == "choice_progressed":
			if StringName(event.get("op", "")) == &"draft_gain_card":
				event_label.text = "%s 已取得 %s，輪到 %s（剩餘 %d 張）" % [
					_player_display_name(str(event.get("actor_id", ""))),
					_card_display_name(str(event.get("card_instance_id", ""))),
					_player_display_name(str(event.get("required_actor_id", ""))),
					int(event.get("remaining_count", 0)),
				]
			elif StringName(event.get("op", "")) == &"choose_gain_card":
				event_label.text = "已取得：%s（%d/%d）" % [
					_card_display_name(str(event.get("card_instance_id", ""))),
					int(event.get("selected_count", 0)),
					int(event.get("max_selections", 0)),
				]
			else:
				event_label.text = "已移除：%s（%d/%d）" % [
					_card_display_name(str(event.get("card_instance_id", ""))),
					int(event.get("selected_count", 0)),
					int(event.get("max_selections", 0)),
				]
			return
		if event.get("type") == "choice_resolved":
			var operation := StringName(event.get("op", ""))
			if bool(event.get("skipped", false)):
				event_label.text = "已略過%s" % _choice_action_label(operation)
			elif operation == &"choose_remove_card" \
					and (bool(event.get("completed_early", false)) \
					or (event.get("source_zone_keys", []) as Array).size() > 1):
				event_label.text = "已完成移除（%d 張）" % int(
					event.get("selected_count", 0)
				)
			elif operation in [&"choose_gain_card", &"draft_gain_card"]:
				event_label.text = "已從%s取得：%s" % [
					(
						"物資輪抽區"
						if operation == &"draft_gain_card"
						else _localized_choice_source(StringName(event.get("source_zone_key", "")))
					),
					_card_display_name(str(event.get("card_instance_id", ""))),
				]
			else:
				event_label.text = "已從%s移除：%s" % [
					_localized_choice_source(StringName(event.get("source_zone_key", ""))),
					_card_display_name(str(event.get("card_instance_id", ""))),
				]
			return
		if event.get("type") == "market_refreshed":
			event_label.text = "市場刷新完成：已更換 %d 張公開卡" % (
				(event.get("returned_card_ids", []) as Array).size()
			)
			return
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
	var hand_card_ids := hand.get("card_instance_ids", []) as Array
	var cards := state.get("cards", {}) as Dictionary
	var definitions := state.get("definitions", {}) as Dictionary
	var legal_commands := state.get("legal_commands", []) as Array
	var refresh_command := _find_refresh_command(legal_commands)
	var choice_commands := _find_choice_commands(legal_commands)
	var action_buttons: Array[Button] = []
	var effect_state := state.get("effect_state", {}) as Dictionary
	var removed := zones.get(str(zone_ids.get("removed", "")), {}) as Dictionary
	var card_ids := hand_card_ids.duplicate()
	var choice_source_label := _choice_source_summary(effect_state)
	if choice_commands.is_empty():
		hand_title.text = "手牌與合法操作"
		hand_summary.text = "目前手牌：%d 張　移除區：%d 張" % [
			card_ids.size(),
			(removed.get("card_instance_ids", []) as Array).size(),
		]
	else:
		var choice_operation := StringName(effect_state.get("op", ""))
		hand_title.text = (
			str(effect_state.get("choice_title", "多人輪抽"))
			if choice_operation == &"draft_gain_card"
			else "待處理選擇"
		)
		card_ids = _remaining_choice_card_ids(effect_state)
		var selected_count := int(effect_state.get("selected_count", 0))
		var max_selections := int(effect_state.get("max_selections", 1))
		var progress_text := (
			"（已選 %d/%d）" % [selected_count, max_selections]
			if max_selections > 1
			else ""
		)
		var count_text := (
			"剩餘 %d 張" % card_ids.size()
			if StringName(effect_state.get("op", "")) == &"choose_remove_card" \
					and max_selections > 1
			else "%d 張" % card_ids.size()
		)
		if choice_operation == &"draft_gain_card":
			hand_summary.text = "%s｜目前應選：%s｜剩餘 %d 張" % [
				str(effect_state.get("prompt", "請完成選擇")),
				_player_display_name(str(effect_state.get("required_actor_id", ""))),
				card_ids.size(),
			]
		else:
			hand_summary.text = "待選擇：%s%s｜來源：%s（%s）" % [
				str(effect_state.get("prompt", "請完成選擇")),
				progress_text,
				choice_source_label,
				count_text,
			]
	if choice_commands.is_empty():
		for raw_command: Variant in legal_commands:
			if not raw_command is Dictionary:
				continue
			var command := raw_command as Dictionary
			var source_id := str(command.get("card_instance_id", ""))
			if command.get("type") == "EQUIP_ITEM" and not source_id.is_empty() \
					and source_id not in card_ids:
				card_ids.append(source_id)

	for raw_card_id: Variant in card_ids:
		var card_id := str(raw_card_id)
		var card := cards.get(card_id, {}) as Dictionary
		var definition := definitions.get(str(card.get("definition_id", "")), {}) as Dictionary
		var card_label := Label.new()
		card_label.text = (
			_draft_card_text(definition)
			if StringName(effect_state.get("op", "")) == &"draft_gain_card"
			else _hand_card_text(definition)
		)
		if StringName(effect_state.get("op", "")) == &"choose_remove_card":
			card_label.text += "｜來源：%s" % _choice_card_source_label(
				effect_state, card_id
			)
		card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hand_actions.add_child(card_label)
		var choice_command := _find_choice_for_card(choice_commands, card_id)
		if not choice_command.is_empty():
			var card_source_label := _choice_card_source_label(effect_state, card_id)
			var choice_button := Button.new()
			choice_button.text = _choice_button_text(
				StringName(effect_state.get("op", "")),
				card_source_label if not card_source_label.is_empty() else choice_source_label
			)
			choice_button.custom_minimum_size = Vector2(0.0, 36.0)
			choice_button.focus_mode = Control.FOCUS_ALL
			choice_button.pressed.connect(
				resolve_choice_requested.emit.bind(
					str(choice_command.get("choice_id", "")),
					StringName(card_id),
					false
				)
			)
			hand_actions.add_child(choice_button)
			action_buttons.append(choice_button)
		if card_id in (refresh_command.get("discard_card_ids", []) as Array):
			var cost_button := Button.new()
			cost_button.text = (
				"✓ 已選為刷新代價"
				if _refresh_discard_id == StringName(card_id)
				else "選為刷新代價"
			)
			cost_button.custom_minimum_size = Vector2(0.0, 34.0)
			cost_button.pressed.connect(_on_refresh_cost_selected.bind(StringName(card_id)))
			hand_actions.add_child(cost_button)
			action_buttons.append(cost_button)
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

	var skip_choice := _find_skip_choice(choice_commands)
	if not skip_choice.is_empty():
		var skip_choice_button := Button.new()
		var selected_count := int(effect_state.get("selected_count", 0))
		var max_selections := int(effect_state.get("max_selections", 1))
		skip_choice_button.text = (
			"完成移除（已選 %d/%d）" % [selected_count, max_selections]
			if StringName(effect_state.get("op", "")) == &"choose_remove_card" \
					and selected_count > 0
			else "略過%s" % _choice_action_label(StringName(effect_state.get("op", "")))
		)
		skip_choice_button.custom_minimum_size = Vector2(0.0, 36.0)
		skip_choice_button.focus_mode = Control.FOCUS_ALL
		skip_choice_button.pressed.connect(
			resolve_choice_requested.emit.bind(
				str(skip_choice.get("choice_id", "")), &"", true
			)
		)
		hand_actions.add_child(skip_choice_button)
		action_buttons.append(skip_choice_button)

	end_phase_button.focus_neighbor_top = NodePath()
	skip_button.focus_neighbor_top = NodePath()
	for index in action_buttons.size():
		var button := action_buttons[index]
		if not choice_commands.is_empty():
			button.focus_neighbor_top = action_buttons[
				(index - 1 + action_buttons.size()) % action_buttons.size()
			].get_path()
			button.focus_neighbor_bottom = action_buttons[
				(index + 1) % action_buttons.size()
			].get_path()
		else:
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
		if not choice_commands.is_empty():
			action_buttons[0].call_deferred("grab_focus")
		else:
			end_phase_button.focus_neighbor_top = action_buttons.back().get_path()
			skip_button.focus_neighbor_top = action_buttons.back().get_path()


func _hand_card_text(definition: Dictionary) -> String:
	var text := str(definition.get("display_name", "未知卡片"))
	var purchase_power: Variant = definition.get("purchase_power", null)
	var combat: Variant = definition.get("combat", null)
	var cost: Variant = definition.get("cost", null)
	var honor: Variant = definition.get("honor", null)
	if cost != null:
		text += "｜費用 %d" % int(cost)
	if purchase_power != null:
		text += "｜購買力 %d（購買階段自動計算）" % int(purchase_power)
	if combat != null:
		text += "｜戰力 %d" % int(combat)
	if honor != null:
		text += "｜榮譽 %d" % int(honor)
	var profession_labels: Array[String] = []
	for raw_tag: Variant in definition.get("tags", []):
		var label: String = {"support":"輔助","melee":"近戰","mage":"法師","tank":"坦克","ranged":"遠程"}.get(str(raw_tag), "")
		if not label.is_empty():
			profession_labels.append(label)
	if not profession_labels.is_empty():
		text += "｜職業 %s" % "、".join(profession_labels)
	var rules_text := str(definition.get("rules_text", ""))
	if not rules_text.is_empty():
		text += "\n效果：%s" % rules_text
	return text


func _draft_card_text(definition: Dictionary) -> String:
	var type_label: String = {
		"item": "道具",
		"equipment": "裝備",
	}.get(str(definition.get("card_type", "")), str(definition.get("card_type", "卡牌")))
	var text := "%s｜%s" % [str(definition.get("display_name", "未知卡片")), type_label]
	for stat: Array in [
		["cost", "費用"],
		["purchase_power", "購買力"],
		["combat", "戰力"],
		["honor", "榮譽"],
	]:
		var value: Variant = definition.get(str(stat[0]), null)
		if value != null:
			text += "｜%s %d" % [str(stat[1]), int(value)]
	return text


func _localized_choice_source(source_zone_key: StringName) -> String:
	return {
		&"hand": "自己的手牌",
		&"party": "自己的隊伍",
		&"discard_pile": "自己的棄牌堆",
		&"recruit_row": "招募區",
		&"shop_row": "商店",
		&"resource_draft_row": "物資輪抽區",
		&"inspection": "自己的查看區",
		&"equipment": "自己的裝備區",
		&"effect_source": "效果來源",
		&"monster_row": "魔物區",
		&"public_enemy": "魔物區",
	}.get(source_zone_key, "選擇來源區")


func _choice_source_summary(effect_state: Dictionary) -> String:
	var source_zone_keys := effect_state.get("source_zone_keys", []) as Array
	if source_zone_keys.is_empty():
		return _localized_choice_source(StringName(effect_state.get("source_zone_key", "")))
	var labels: Array[String] = []
	for raw_source: Variant in source_zone_keys:
		labels.append(_localized_choice_source(StringName(str(raw_source))))
	return "、".join(labels)


func _choice_card_source_label(effect_state: Dictionary, card_id: String) -> String:
	var source_record := (effect_state.get("eligible_card_sources", {}) as Dictionary).get(
		card_id, {}
	) as Dictionary
	var source_zone_key := StringName(source_record.get("zone_key", ""))
	return "" if source_zone_key.is_empty() else _localized_choice_source(source_zone_key)


func _remaining_choice_card_ids(effect_state: Dictionary) -> Array:
	if StringName(effect_state.get("op", "")) == &"draft_gain_card":
		return (effect_state.get("remaining_card_ids", []) as Array).duplicate()
	var result: Array = []
	var selected_card_ids := effect_state.get("selected_card_ids", []) as Array
	for raw_card_id: Variant in effect_state.get("eligible_card_ids", []):
		if str(raw_card_id) not in selected_card_ids:
			result.append(raw_card_id)
	return result


func _choice_action_label(operation: StringName) -> String:
	if operation == &"pay_post_departure_cost":
		return "棄牌"
	return {
		&"choose_gain_card": "取得", &"draft_gain_card": "取得",
		&"choose_remove_card": "移除",
		&"choose_move_card": "移動", &"choose_refresh_row": "刷新",
		&"choose_target_combat_modifier": "指定", &"confirm_effect": "效果",
		&"inspect_deck_top": "移除",
	}.get(operation, "選擇")


func _choice_button_text(operation: StringName, source_label: String) -> String:
	if operation == &"pay_post_departure_cost":
		return "棄置此冒險者"
	if operation in [&"choose_gain_card", &"draft_gain_card"]:
		return "從%s取得此牌" % source_label
	if operation == &"confirm_effect":
		return "執行效果"
	if operation == &"choose_move_card":
		return "從%s移動此牌" % source_label
	if operation == &"choose_target_combat_modifier":
		return "指定此魔物"
	if operation == &"choose_refresh_row":
		return "選擇刷新此牌"
	if operation == &"order_deck_top":
		return "選為下一張牌庫頂"
	if operation == &"choose_equipment_replacement":
		return "棄置此裝備"
	return "從%s移除此牌" % source_label


func _card_display_name(card_instance_id: String) -> String:
	var card := _cards.get(card_instance_id, {}) as Dictionary
	var definition := _definitions.get(str(card.get("definition_id", "")), {}) as Dictionary
	return str(definition.get("display_name", card_instance_id))


func _player_display_name(player_id: String) -> String:
	var players := _current_state.get("players", {}) as Dictionary
	var player := players.get(player_id, {}) as Dictionary
	return str(player.get("display_name", player_id))


func _rebuild_market(state: Dictionary) -> void:
	for child: Node in market_actions.get_children():
		market_actions.remove_child(child)
		child.queue_free()
	var zones := state.get("zones", {}) as Dictionary
	var legal_commands := state.get("legal_commands", []) as Array
	var refresh_command := _find_refresh_command(legal_commands)
	var refresh_rows := refresh_command.get("rows", {}) as Dictionary
	var market_buttons: Array[Button] = []
	_append_boss_info(zones)
	var attack_target_count := _append_combat_actions(legal_commands, market_buttons)
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
			var row_box := HBoxContainer.new()
			var label := Label.new()
			label.text = _hand_card_text(definition)
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
			if card_id in (refresh_rows.get(row_id, []) as Array):
				var select_button := CheckBox.new()
				select_button.text = "刷新"
				select_button.button_pressed = (
					_refresh_row_id == StringName(row_id)
					and StringName(card_id) in _refresh_selected_ids
				)
				select_button.toggled.connect(
					_on_refresh_card_toggled.bind(StringName(row_id), StringName(card_id))
				)
				row_box.add_child(select_button)
				market_buttons.append(select_button)
			market_actions.add_child(row_box)
		if refresh_rows.has(row_id):
			var selected_count := (
				_refresh_selected_ids.size() if _refresh_row_id == StringName(row_id) else 0
			)
			var confirm_button := Button.new()
			confirm_button.text = "確認刷新（已選 %d 張）" % selected_count
			confirm_button.disabled = _refresh_discard_id.is_empty() or selected_count == 0
			confirm_button.pressed.connect(_on_refresh_confirmed.bind(StringName(row_id)))
			market_actions.add_child(confirm_button)
			market_buttons.append(confirm_button)
	if attack_target_count > 0:
		market_summary.text = "可討伐目標：%d　參戰者採剛好達標的隊伍前綴" % attack_target_count
	else:
		market_summary.text = "公開卡：%d　%s" % [
			total_cards,
			"選 1～3 張並從手牌選 1 張作為刷新代價"
			if not refresh_command.is_empty()
			else "購買只在購買階段開放",
		]

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


func _append_boss_info(zones: Dictionary) -> void:
	var active := zones.get("shared:boss-active", {}) as Dictionary
	var deck := zones.get("shared:boss-deck", {}) as Dictionary
	var card_ids := active.get("card_instance_ids", []) as Array
	var title := Label.new()
	title.text = "Boss｜牌庫剩餘 %d" % (deck.get("card_instance_ids", []) as Array).size()
	title.add_theme_color_override("font_color", Color(1.0, 0.48, 0.42))
	market_actions.add_child(title)
	if card_ids.is_empty():
		var empty_label := Label.new()
		var metadata := active.get("metadata", {}) as Dictionary
		empty_label.text = (
			"已全數擊敗"
			if bool(metadata.get("all_bosses_defeated", false))
			else "等待休息階段揭示下一名 Boss"
		)
		market_actions.add_child(empty_label)
		return
	var card_id := str(card_ids[0])
	var definition := _definition_for_instance(card_id)
	var boss_label := Label.new()
	var attachment_names: Array[String] = []
	var boss_card := _cards.get(card_id, {}) as Dictionary
	for raw_attachment_id: Variant in (boss_card.get("state", {}) as Dictionary).get("attachment_ids", []):
		attachment_names.append(_card_display_name(str(raw_attachment_id)))
	boss_label.text = "%s｜戰力 %d｜購買力 %d｜榮譽 %d\n規則：%s\n獎勵：%s%s" % [
		str(definition.get("display_name", card_id)),
		int(definition.get("combat", 0)),
		int(definition.get("purchase_power", 0)),
		int(definition.get("honor", 0)),
		str(definition.get("rules_text", "")),
		str(definition.get("reward_text", "")),
		(
			"\n附件：%s" % "、".join(attachment_names)
			if not attachment_names.is_empty()
			else ("\n此 Boss 的單卡規則尚未啟用" if not bool(definition.get("framework_ready", true)) else "")
		),
	]
	boss_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	market_actions.add_child(boss_label)


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


func _find_refresh_command(commands: Array) -> Dictionary:
	for raw_command: Variant in commands:
		if raw_command is Dictionary and (raw_command as Dictionary).get("type") == "REFRESH_MARKET":
			return raw_command as Dictionary
	return {}


func _find_choice_commands(commands: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_command: Variant in commands:
		if raw_command is Dictionary \
				and (raw_command as Dictionary).get("type") == "RESOLVE_CHOICE":
			result.append(raw_command as Dictionary)
	return result


func _find_choice_for_card(commands: Array[Dictionary], card_instance_id: String) -> Dictionary:
	for command: Dictionary in commands:
		if not bool(command.get("skip", false)) \
				and str(command.get("card_instance_id", "")) == card_instance_id:
			return command
	return {}


func _find_skip_choice(commands: Array[Dictionary]) -> Dictionary:
	for command: Dictionary in commands:
		if bool(command.get("skip", false)):
			return command
	return {}


func _commands_contain_type(commands: Array, command_type: String) -> bool:
	for raw_command: Variant in commands:
		if raw_command is Dictionary \
				and str((raw_command as Dictionary).get("type", "")) == command_type:
			return true
	return false


func _append_combat_actions(commands: Array, action_buttons: Array[Button]) -> int:
	var attack_commands: Array[Dictionary] = []
	for raw_command: Variant in commands:
		if raw_command is Dictionary and (raw_command as Dictionary).get("type") == "ATTACK_TARGET":
			attack_commands.append(raw_command as Dictionary)
	if attack_commands.is_empty():
		return 0
	var title := Label.new()
	title.text = "討伐目標"
	title.add_theme_color_override("font_color", Color(0.95, 0.78, 0.26))
	market_actions.add_child(title)
	var rendered_targets: Dictionary = {}
	for command: Dictionary in attack_commands:
		var target_id := str(command.get("target_card_id", ""))
		var preview := command.get("preview", {}) as Dictionary
		if not rendered_targets.has(target_id):
			rendered_targets[target_id] = true
			var participant_names: Array[String] = []
			for raw_participant_id: Variant in preview.get("participant_ids", []):
				participant_names.append(_card_display_name(str(raw_participant_id)))
			var preview_label := Label.new()
			preview_label.text = "%s｜需求 %d｜投入 %d\n參戰：%s" % [
				_card_display_name(target_id),
				int(preview.get("requirement", 0)),
				int(preview.get("total_combat", 0)),
				"、".join(participant_names),
			]
			preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			market_actions.add_child(preview_label)
		var claim_reward := bool(command.get("claim_optional_reward", true))
		var use_departures := bool(command.get("use_optional_departures", true))
		var reward_summary := str(preview.get("reward_summary", ""))
		var attack_button := Button.new()
		if bool(preview.get("optional_reward", false)):
			attack_button.text = (
				"討伐並領取 %s" % reward_summary if claim_reward else "討伐並略過獎勵"
			)
		else:
			attack_button.text = "討伐｜%s" % reward_summary
		if bool(preview.get("optional_departure", false)):
			attack_button.text += "｜%s替代離場" % ("採用" if use_departures else "略過")
		attack_button.custom_minimum_size = Vector2(0.0, 36.0)
		attack_button.pressed.connect(
			attack_target_requested.emit.bind(
				StringName(target_id), claim_reward, use_departures
			)
		)
		market_actions.add_child(attack_button)
		action_buttons.append(attack_button)
	return rendered_targets.size()


func _on_refresh_cost_selected(card_instance_id: StringName) -> void:
	_refresh_discard_id = &"" if _refresh_discard_id == card_instance_id else card_instance_id
	_rerender_card_actions()


func _on_refresh_card_toggled(
	pressed: bool,
	row_id: StringName,
	card_instance_id: StringName
) -> void:
	if pressed:
		if _refresh_row_id != row_id:
			_refresh_row_id = row_id
			_refresh_selected_ids.clear()
		if card_instance_id not in _refresh_selected_ids and _refresh_selected_ids.size() < 3:
			_refresh_selected_ids.append(card_instance_id)
	else:
		_refresh_selected_ids.erase(card_instance_id)
		if _refresh_selected_ids.is_empty():
			_refresh_row_id = &""
	_rerender_card_actions()


func _on_refresh_confirmed(row_id: StringName) -> void:
	if _refresh_discard_id.is_empty() or _refresh_row_id != row_id \
			or _refresh_selected_ids.is_empty():
		return
	refresh_market_requested.emit(
		_refresh_discard_id,
		row_id,
		_refresh_selected_ids.duplicate()
	)


func _rerender_card_actions() -> void:
	if _current_state.is_empty():
		return
	var active_player_id := str(_current_state.get("active_player_id", ""))
	_rebuild_hand(_current_state, active_player_id)
	_rebuild_market(_current_state)


func _clear_refresh_selection() -> void:
	_refresh_discard_id = &""
	_refresh_row_id = &""
	_refresh_selected_ids.clear()
