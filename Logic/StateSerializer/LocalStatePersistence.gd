extends IStateSerializer

const SAVE_PATH: String = "user://ai_task_state.json"

func save_state(state: Dictionary, _tree: SceneTree) -> bool:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("TaskSerializer: Cannot open ", SAVE_PATH, " for writing.")
		return false

	file.store_string(JSON.stringify(state, "\t"))
	file.close()
	print("[TaskSerializer] State saved locally to ", SAVE_PATH)
	return true

func load_state() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		print("[TaskSerializer] No save file found at ", SAVE_PATH)
		return {}

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("TaskSerializer: Cannot open ", SAVE_PATH, " for reading.")
		return {}

	var text: String = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(text) != OK:
		push_error("TaskSerializer: JSON parse error: ", json.get_error_message())
		return {}

	print("[TaskSerializer] State loaded from ", SAVE_PATH)
	return json.data
