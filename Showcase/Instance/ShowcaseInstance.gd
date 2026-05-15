extends PanelContainer
class_name ShowcaseInstance

signal is_ready
signal initialization_failed(error_msg: String)
signal player_context_changed(player_id: int)
signal focus_requested(player_id: int)

var player_id: int = -1
var is_server: bool = false
var enable_networking: bool = false
var instance_label: String = ""
var launcher: Node = null
var networking: ShowcaseNetworkBridge
var _snapshot_cache: Dictionary = {}

var _title_label: Label
var _detail_label: Label
var _snapshot_label: Label
var _focus_button: Button
var _command_button: Button

func initialize(p_id: int, p_is_server: bool, p_enable_networking: bool = false, p_launcher: Node = null) -> void:
	player_id = p_id
	is_server = p_is_server
	enable_networking = p_enable_networking
	launcher = p_launcher
	instance_label = "Server_Host" if is_server else "Player_%d" % player_id

func _ready() -> void:
	_build_ui()
	_setup_network_bridge()
	_refresh()
	is_ready.emit()

func is_initialized() -> bool:
	return true

func is_networked() -> bool:
	return enable_networking

func get_player_id() -> int:
	return player_id

func request_snapshot() -> Dictionary:
	if launcher != null and launcher.has_method("request_player_snapshot"):
		return launcher.request_player_snapshot(player_id)
	return _snapshot_cache.duplicate(true)

func get_state_snapshot() -> Dictionary:
	return request_snapshot()

func get_debug_info() -> Dictionary:
	return {
		"player_id": player_id,
		"is_server": is_server,
		"is_networked": enable_networking,
		"current_tick": TickManager.current_tick if TickManager != null else -1,
		"snapshot_hash": _snapshot_cache.get("state_hash", 0)
	}

func _build_ui() -> void:
	custom_minimum_size = Vector2(360, 160)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	_title_label = Label.new()
	_title_label.text = instance_label if instance_label != "" else "Uninitialized"
	vbox.add_child(_title_label)

	_detail_label = Label.new()
	_detail_label.text = "Waiting for showcase world"
	vbox.add_child(_detail_label)

	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)

	_focus_button = Button.new()
	_focus_button.text = "Focus"
	_focus_button.pressed.connect(func(): focus_requested.emit(player_id))
	hbox.add_child(_focus_button)

	_command_button = Button.new()
	_command_button.text = "Refresh Snapshot"
	_command_button.pressed.connect(_refresh)
	hbox.add_child(_command_button)

	_snapshot_label = Label.new()
	_snapshot_label.text = "Hash: n/a"
	vbox.add_child(_snapshot_label)

func _setup_network_bridge() -> void:
	networking = ShowcaseNetworkBridge.new()
	add_child(networking)

	if enable_networking:
		if is_server:
			networking.initialize_server(player_id)
		else:
			networking.initialize_client(player_id)

func _refresh() -> void:
	if launcher != null and launcher.has_method("request_player_snapshot"):
		_snapshot_cache = launcher.request_player_snapshot(player_id)
	else:
		_snapshot_cache = {}

	_update_labels()

func _update_labels() -> void:
	_title_label.text = "%s" % instance_label
	if _snapshot_cache.is_empty():
		_detail_label.text = "No snapshot available"
		_snapshot_label.text = "Hash: n/a"
		return

	_detail_label.text = "Units: %s | Resources: %s | Buildings: %s" % [
		str(_snapshot_cache.get("unit_count", 0)),
		str(_snapshot_cache.get("resource_count", 0)),
		str(_snapshot_cache.get("building_count", 0))
	]
	_snapshot_label.text = "Hash: %s" % str(_snapshot_cache.get("state_hash", "n/a"))
