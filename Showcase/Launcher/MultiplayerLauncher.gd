extends Node
class_name MultiplayerLauncher

const DEFAULT_ADDRESS := "127.0.0.1"
const DEFAULT_PORT := 24567

var _world: Node = null
var _scenario: ShowcaseScenario = null
var _gateway: Node = null

var _ui_layer: CanvasLayer
var _panel: PanelContainer
var _address_edit: LineEdit
var _port_spin: SpinBox
var _player_spin: SpinBox
var _unit_spin: SpinBox
var _target_spin: SpinBox
var _mode_label: Label
var _peer_label: Label
var _tick_label: Label
var _hash_label: Label
var _sync_label: Label
var _scenario_label: Label
var _log: RichTextLabel
var _host_button: Button
var _join_button: Button
var _disconnect_button: Button
var _demo_button: Button
var _refresh_button: Button

func _ready() -> void:
	_build_ui()
	_bind_from_tree()
	_refresh_defaults()
	_apply_command_line_defaults()
	_log_line("[SHOWCASE] Local multiplayer launcher ready.")

func bind_world(world: Node) -> void:
	_world = world
	_gateway = _world.get_node_or_null("ClientGateway") if _world != null else null
	_scenario = _world.get_node_or_null("ScenarioController") if _world != null else null
	if _scenario != null and _scenario.has_signal("scenario_state_changed"):
		if not _scenario.scenario_state_changed.is_connected(_on_scenario_state_changed):
			_scenario.scenario_state_changed.connect(_on_scenario_state_changed)
	_refresh_defaults()
	_update_status()

func _process(_delta: float) -> void:
	if _world == null:
		_bind_from_tree()
	_update_status()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F6:
			_host_pressed()
		KEY_F7:
			_join_pressed()
		KEY_F8:
			_demo_pressed()
		KEY_F9:
			_disconnect_pressed()

func _bind_from_tree() -> void:
	if _world == null:
		_world = get_tree().root.get_node_or_null("World")
	if _world != null:
		_gateway = _world.get_node_or_null("ClientGateway")
		_scenario = _world.get_node_or_null("ScenarioController")
		if _scenario != null and _scenario.has_signal("scenario_state_changed"):
			if not _scenario.scenario_state_changed.is_connected(_on_scenario_state_changed):
				_scenario.scenario_state_changed.connect(_on_scenario_state_changed)

func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 200
	add_child(_ui_layer)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = 16
	_panel.offset_top = 16
	_panel.offset_right = 550
	_panel.offset_bottom = 740
	_ui_layer.add_child(_panel)

	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 14)
	outer.add_theme_constant_override("margin_top", 14)
	outer.add_theme_constant_override("margin_right", 14)
	outer.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(outer)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(vbox)

	var title := Label.new()
	title.text = "Local Multiplayer Showcase"
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Host in one instance, join from another, and watch the deterministic state hash stay aligned."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)

	grid.add_child(_label("Address"))
	_address_edit = LineEdit.new()
	_address_edit.text = DEFAULT_ADDRESS
	grid.add_child(_address_edit)

	grid.add_child(_label("Port"))
	_port_spin = _spin(DEFAULT_PORT, 1, 65535, 1)
	grid.add_child(_port_spin)

	grid.add_child(_label("Player ID"))
	_player_spin = _spin(0, 0, 8, 1)
	grid.add_child(_player_spin)

	grid.add_child(_label("Unit ID"))
	_unit_spin = _spin(1000, 0, 10000, 1)
	grid.add_child(_unit_spin)

	grid.add_child(_label("Target Resource ID"))
	_target_spin = _spin(2000, 0, 10000, 1)
	grid.add_child(_target_spin)

	vbox.add_child(HSeparator.new())

	var button_row := GridContainer.new()
	button_row.columns = 2
	button_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(button_row)

	_host_button = _button("Host Local", _host_pressed)
	button_row.add_child(_host_button)
	_join_button = _button("Join Local", _join_pressed)
	button_row.add_child(_join_button)
	_disconnect_button = _button("Disconnect", _disconnect_pressed)
	button_row.add_child(_disconnect_button)
	_demo_button = _button("Run Sync Demo", _demo_pressed)
	button_row.add_child(_demo_button)
	_refresh_button = _button("Refresh IDs", _refresh_pressed)
	button_row.add_child(_refresh_button)
	button_row.add_child(_button("Apply Player ID", _apply_player_pressed))

	vbox.add_child(HSeparator.new())

	_mode_label = _label("Mode: offline")
	_peer_label = _label("Peer: n/a")
	_tick_label = _label("Tick: n/a")
	_hash_label = _label("Hash: n/a")
	_sync_label = _label("Sync: n/a")
	_scenario_label = _label("Scenario: idle")

	vbox.add_child(_mode_label)
	vbox.add_child(_peer_label)
	vbox.add_child(_tick_label)
	vbox.add_child(_hash_label)
	vbox.add_child(_sync_label)
	vbox.add_child(_scenario_label)

	vbox.add_child(HSeparator.new())

	var log_title := Label.new()
	log_title.text = "Console"
	vbox.add_child(log_title)

	_log = RichTextLabel.new()
	_log.fit_content = true
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(0, 220)
	vbox.add_child(_log)

func _bind_from_scenario() -> void:
	if _scenario == null:
		return
	if _unit_spin != null and _scenario.has_method("get_first_unit_id_for_player"):
		var uid := int(_scenario.get_first_unit_id_for_player(int(_player_spin.value)))
		if uid >= 0:
			_unit_spin.value = uid
	if _target_spin != null and _scenario.has_method("get_first_resource_id"):
		var rid := int(_scenario.get_first_resource_id())
		if rid >= 0:
			_target_spin.value = rid

func _refresh_defaults() -> void:
	_bind_from_scenario()

	if _scenario != null and _scenario.has_method("get_unit_ids_for_player"):
		var host_ids: Array[int] = _scenario.get_unit_ids_for_player(0)
		if not host_ids.is_empty():
			_unit_spin.value = host_ids[0]
		var client_ids: Array[int] = _scenario.get_unit_ids_for_player(1)
		if not client_ids.is_empty():
			_target_spin.value = _scenario.get_first_resource_id()

func _apply_command_line_defaults() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--showcase-port="):
			_port_spin.value = int(arg.get_slice("=", 1))
		elif arg.begins_with("--showcase-address="):
			_address_edit.text = arg.get_slice("=", 1)
		elif arg.begins_with("--showcase-player="):
			_player_spin.value = int(arg.get_slice("=", 1))
		elif arg.begins_with("--showcase-unit="):
			_unit_spin.value = int(arg.get_slice("=", 1))
		elif arg.begins_with("--showcase-target="):
			_target_spin.value = int(arg.get_slice("=", 1))
		elif arg == "--showcase-host":
			call_deferred("_host_pressed")
		elif arg.begins_with("--showcase-join="):
			_address_edit.text = arg.get_slice("=", 1)
			call_deferred("_join_pressed")

func _host_pressed() -> void:
	_configure_gateway()
	var gateway := _gateway_node()
	if gateway == null:
		_log_line("[NET_ERR] Gateway not available.")
		return
	gateway.start_server(int(_port_spin.value))
	_log_line("[NET_LOG] Host requested on port %d." % int(_port_spin.value))

func _join_pressed() -> void:
	_configure_gateway()
	var gateway := _gateway_node()
	if gateway == null:
		_log_line("[NET_ERR] Gateway not available.")
		return
	gateway.connect_to_server(_address_edit.text, int(_port_spin.value))
	_log_line("[NET_LOG] Join requested for %s:%d." % [_address_edit.text, int(_port_spin.value)])

func _disconnect_pressed() -> void:
	var gateway := _gateway_node()
	if gateway != null and gateway.has_method("disconnect_network"):
		gateway.disconnect_network()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	_log_line("[NET_LOG] Local peer disconnected.")
	_update_status()

func _demo_pressed() -> void:
	var gateway := _gateway_node()
	if gateway == null:
		_log_line("[CMD_ERR] Gateway not available.")
		return

	var command := {
		"action": "CHOP_AND_RETURN",
		"unit_id": int(_unit_spin.value),
		"target_id": int(_target_spin.value),
		"player_id": int(_player_spin.value)
	}

	var ok := false
	if gateway.has_method("submit_showcase_command"):
		ok = bool(gateway.submit_showcase_command(command))
	elif _scenario != null and _scenario.has_method("run_demo"):
		ok = bool(_scenario.run_demo(int(_unit_spin.value), int(_player_spin.value), int(_target_spin.value)))

	if ok:
		_log_line("[CMD_SENT] %s" % str(command))
	else:
		_log_line("[CMD_DENIED] Demo command was rejected.")
	_update_status()

func _refresh_pressed() -> void:
	_refresh_defaults()
	_log_line("[SHOWCASE] Refreshed unit and target IDs from world state.")

func _apply_player_pressed() -> void:
	var gateway = get_node_or_null("/root/ActionGateway")
	if gateway != null and gateway.has_method("set_active_player"):
		gateway.set_active_player(int(_player_spin.value))
	_log_line("[SHOWCASE] Active player set to %d." % int(_player_spin.value))

func _configure_gateway() -> void:
	var gateway := _gateway_node()
	if gateway != null and gateway.has_method("set_port"):
		gateway.set_port(int(_port_spin.value))
	var action_gateway = get_node_or_null("/root/ActionGateway")
	if action_gateway != null and action_gateway.has_method("set_active_player"):
		action_gateway.set_active_player(int(_player_spin.value))

func _gateway_node() -> Node:
	if _gateway != null:
		return _gateway
	if _world != null:
		_gateway = _world.get_node_or_null("ClientGateway")
	return _gateway

func _update_status() -> void:
	var gateway := _gateway_node()
	var server_tick := -1
	var signature := ""
	var mode := "offline"
	var peer_summary := {}

	if gateway != null and gateway.has_method("get_peer_summary"):
		peer_summary = gateway.get_peer_summary()
		mode = String(peer_summary.get("mode", "offline"))
		server_tick = int(gateway.get_last_tick()) if gateway.has_method("get_last_tick") else -1
		signature = String(gateway.get_last_state_signature()) if gateway.has_method("get_last_state_signature") else ""

	var tick_manager = get_node_or_null("/root/TickManager")
	var local_tick = int(tick_manager.get_tick_count()) if tick_manager != null and tick_manager.has_method("get_tick_count") else -1
	var scenario_report := _scenario.get_status_report() if _scenario != null and _scenario.has_method("get_status_report") else {}

	_mode_label.text = "Mode: %s" % mode
	_peer_label.text = "Peer: %s" % str(peer_summary)
	_tick_label.text = "Tick: local=%d authoritative=%d" % [local_tick, server_tick]
	_hash_label.text = "Hash: %s" % (signature if not signature.is_empty() else "n/a")
	_sync_label.text = "Sync: %s" % ("OK" if bool(scenario_report.get("in_sync", false)) else "DESYNC")
	_scenario_label.text = "Scenario: %s" % str(scenario_report.get("demo_phase", "idle"))

func _on_scenario_state_changed(state: Dictionary) -> void:
	_log_line("[SENSE] %s" % str(state))
	_update_status()

func _label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	return lbl

func _spin(default_value: float, min_value: float, max_value: float, step: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = min_value
	sb.max_value = max_value
	sb.step = step
	sb.value = default_value
	sb.allow_greater = true
	sb.allow_lesser = true
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return sb

func _button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(callback)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return btn

func _log_line(text: String) -> void:
	if _log == null:
		return
	_log.append_text(text + "\n")
	_log.scroll_to_line(_log.get_line_count() - 1)
