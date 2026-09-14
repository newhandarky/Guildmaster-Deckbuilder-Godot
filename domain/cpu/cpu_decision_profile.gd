class_name CpuDecisionProfile
extends RefCounted


static func balanced() -> Dictionary:
	return {
		"attack_boss": 180,
		"attack_monster": 85,
		"boss_unlock": 170,
		"boss_gap_reduction": 22,
		"party_power": 13,
		"equipment_power": 15,
		"future_combat": 10,
		"honor": 3,
		"purchase_efficiency": 5,
	}
