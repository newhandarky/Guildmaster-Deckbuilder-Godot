class_name CpuCommandCodec
extends RefCounted


static func payload(legal_command: Dictionary) -> Dictionary:
	var command := legal_command.duplicate(true)
	for metadata_key in ["actor_id", "expected_revision", "preview", "effective_cost"]:
		command.erase(metadata_key)
	return command


static func key(legal_command: Dictionary) -> String:
	return CanonicalJson.stringify(payload(legal_command))
