class_name PlayerView
extends RefCounted


static func project(state: GameStateData, viewer_id: StringName) -> Dictionary:
	var view := state.to_dictionary()
	view.erase("seed")
	view.erase("rng_state")
	var zones := view.get("zones", {}) as Dictionary
	var cards := view.get("cards", {}) as Dictionary
	for zone_id: Variant in zones:
		var zone := zones[zone_id] as Dictionary
		var visibility := StringName(zone.get("visibility", ""))
		var owner_id := StringName((zone.get("metadata", {}) as Dictionary).get("owner_id", ""))
		if visibility == &"public" or (visibility == &"owner_only" and owner_id == viewer_id):
			continue
		var ids := zone.get("card_instance_ids", []) as Array
		zone["card_count"] = ids.size()
		for raw_id: Variant in ids:
			cards.erase(str(raw_id))
		zone["card_instance_ids"] = []
	var choice := view.get("effect_state", {}) as Dictionary
	if not choice.is_empty() and StringName(choice.get("required_actor_id", "")) != viewer_id:
		if StringName(choice.get("op", "")) in [&"select_bonds", &"complete_bonds"]:
			view["effect_state"] = {
				"type": "pending_choice", "op": "private_bond_choice",
				"required_actor_id": str(choice.get("required_actor_id", "")),
			}
	return view
