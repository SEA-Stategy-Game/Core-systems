extends RefCounted
class_name IStateSerializer

func save_state(_state: Dictionary, _tree: SceneTree) -> bool:
	push_error("IStateSerializer.save_state() is abstract.")
	return false

func load_state() -> Dictionary:
	push_error("IStateSerializer.load_state() is abstract.")
	return {}