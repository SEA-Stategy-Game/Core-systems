extends Control
class_name MultiplayerLauncher

## =========================================================================
## MultiplayerLauncher.gd
##
## Purpose:
##   Coordinate spawning and managing multiple ShowcaseInstance nodes
##   for local multiplayer testing.
##
## Features:
##   - Preset configurations (2 Local, Server+Client, etc.)
##   - Real-time instance monitoring
##   - Determinism verification via live state checksums
##   - Debug UI for inspection
##
## Usage:
##   1. Set as main scene in project settings, OR
##   2. Call manually: launcher.spawn_instances(config_name)
## =========================================================================

## Configuration Presets
var presets = {
	"2_Local": {
		"name": "2 Local Players",
		"instances": [
			{"player_id": 0, "is_server": true, "enable_networking": false},
			{"player_id": 1, "is_server": true, "enable_networking": false},
		],
		"description": "Two players on same machine, shared world"
	},
	"Server_LocalClient": {
		"name": "Server + Local Client",
		"instances": [
			{"player_id": 0, "is_server": true, "enable_networking": true},
			{"player_id": 1, "is_server": false, "enable_networking": true},
		],
		"description": "Server instance + networked client"
	},
	"Solo": {
		"name": "Solo Player (Determinism Test)",
		"instances": [
			{"player_id": 0, "is_server": true, "enable_networking": false},
		],
		"description": "Single player for baseline testing"
	}
}

## References
var instance_scene: PackedScene
var active_instances: Array[ShowcaseInstance] = []
var current_preset: String = ""

## UI Components
var preset_dropdown: OptionButton
var start_button: Button
var status_label: Label
var instance_list: ItemList
var determinism_panel: PanelContainer
var determinism_label: Label
var close_all_button: Button

## State
var launcher_ready: bool = false
var verify_determinism: bool = true
var last_snapshot_time: int = 0
var state_snapshots: Dictionary = {}  # player_id -> last snapshot

## =========================================================================
## Lifecycle
## =========================================================================

func _ready() -> void:
	"""Build launcher UI and prepare for instance spawning."""
	print("[LAUNCHER] MultiplayerLauncher starting...")
	
	# Load instance scene
	instance_scene = load("res://Showcase/Instance/ShowcaseInstance.tscn")
	if not instance_scene:
		push_error("[LAUNCHER] ShowcaseInstance.tscn not found!")
		return
	
	# Build UI
	_build_launcher_ui()
	
	launcher_ready = true
	print("[LAUNCHER] ✅ Ready to spawn instances")

func _process(delta: float) -> void:
	"""Update UI with instance status and determinism info."""
	if not launcher_ready or active_instances.is_empty():
		return
	
	# Update instance list
	_update_instance_list()
	
	# Periodically check determinism
	if verify_determinism and Time.get_ticks_msec() - last_snapshot_time > 500:
		_verify_determinism()
		last_snapshot_time = Time.get_ticks_msec()

## =========================================================================
## Public API
## =========================================================================

func spawn_instances(preset_name: String) -> void:
	"""
	Spawn instances according to a preset configuration.
	
	Args:
		preset_name: Key from presets dict ("2_Local", "Server_LocalClient", etc.)
	"""
	if not launcher_ready:
		_set_status("ERROR: Launcher not ready!", Color.RED)
		return
	
	if not presets.has(preset_name):
		_set_status("ERROR: Unknown preset '%s'" % preset_name, Color.RED)
		return
	
	print("[LAUNCHER] Spawning preset: %s" % preset_name)
	_set_status("Spawning instances...", Color.YELLOW)
	
	current_preset = preset_name
	var preset = presets[preset_name]
	
	# Clear any existing instances
	for inst in active_instances:
		inst.queue_free()
	active_instances.clear()
	
	# Spawn new instances according to preset
	for config in preset.get("instances", []):
		_spawn_single_instance(config)
	
	# Wait for all instances to initialize
	await _wait_all_ready()
	_set_status("✅ Showcase Ready!", Color.GREEN)

func stop_all_instances() -> void:
	"""Clean up and remove all active instances."""
	print("[LAUNCHER] Stopping all instances...")
	for inst in active_instances:
		inst.queue_free()
	active_instances.clear()
	_set_status("Instances stopped", Color.WHITE)

func toggle_determinism_checking(enabled: bool) -> void:
	"""Enable/disable real-time determinism verification."""
	verify_determinism = enabled
	print("[LAUNCHER] Determinism checking: %s" % ("ON" if enabled else "OFF"))

## =========================================================================
## Private: Instance Spawning
## =========================================================================

func _spawn_single_instance(config: Dictionary) -> void:
	"""Spawn a single ShowcaseInstance with given config."""
	var instance = instance_scene.instantiate()
	instance.initialize(
		config.get("player_id", -1),
		config.get("is_server", false),
		config.get("enable_networking", false)
	)
	
	# Add to tree
	add_child(instance)
	active_instances.append(instance)
	
	print("[LAUNCHER] Spawned: Player %d (server=%s, net=%s)" % [
		config.get("player_id"),
		config.get("is_server"),
		config.get("enable_networking")
	])

func _wait_all_ready() -> void:
	"""Wait for all instances to complete initialization."""
	print("[LAUNCHER] Waiting for instances to initialize...")
	
	var timeout = 10.0
	
	for inst in active_instances:
		# Wait for instance to initialize with timeout
		var start_time = Time.get_ticks_msec()
		
		while not inst.is_initialized():
			await get_tree().process_frame
			
			if Time.get_ticks_msec() - start_time > timeout * 1000:
				push_error("[LAUNCHER] Instance %d initialization timeout!" % inst.player_id)
				inst.queue_free()
				break
	
	print("[LAUNCHER] All instances ready ✅")

## =========================================================================
## Determinism Verification
## =========================================================================

func _verify_determinism() -> void:
	"""
	Check if all instances have identical game state.
	Useful for verifying deterministic synchronization.
	"""
	if active_instances.is_empty():
		return
	
	# Collect snapshots from all instances
	var snapshots = {}
	for inst in active_instances:
		if not inst.is_initialized():
			continue
		
		if not inst.networking:
			# No networking, can't get snapshots
			continue
		
		var snapshot = inst.networking.request_state_snapshot()
		snapshots[inst.player_id] = snapshot
	
	if snapshots.is_empty():
		return
	
	# Compare all snapshots
	var reference_hash = -1
	var all_in_sync = true
	
	for player_id in snapshots:
		var snap = snapshots[player_id]
		if reference_hash == -1:
			reference_hash = snap.get("state_hash", 0)
		else:
			if snap.get("state_hash", 0) != reference_hash:
				all_in_sync = false
				break
	
	# Update UI
	var sync_text = "✅ IN SYNC" if all_in_sync else "🔴 DESYNC"
	var sync_color = Color.GREEN if all_in_sync else Color.RED
	
	determinism_label.text = "%s | Tick: %d | Units: %d" % [
		sync_text,
		snapshots.get(0, {}).get("tick", 0),
		snapshots.get(0, {}).get("unit_count", 0)
	]
	determinism_label.add_theme_color_override("font_color", sync_color)
	
	state_snapshots = snapshots

## =========================================================================
## UI Building
## =========================================================================

func _build_launcher_ui() -> void:
	"""Build the launcher UI."""
	print("[LAUNCHER] Building UI...")
	
	# Main container
	var main_panel = PanelContainer.new()
	main_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(main_panel)
	
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.15, 0.20, 1.0)
	main_panel.add_theme_stylebox_override("panel", bg)
	
	# Main VBox
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 12)
	main_panel.add_child(main_vbox)
	
	# Margin
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(margin)
	
	var inner_vbox = VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(inner_vbox)
	
	# Title
	var title = Label.new()
	title.text = "Sea Strategy - Local Multiplayer Showcase"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color.CYAN)
	inner_vbox.add_child(title)
	
	inner_vbox.add_child(HSeparator.new())
	
	# Preset Selection
	var preset_label = Label.new()
	preset_label.text = "Select Configuration:"
	inner_vbox.add_child(preset_label)
	
	preset_dropdown = OptionButton.new()
	preset_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner_vbox.add_child(preset_dropdown)
	
	# Populate dropdown
	for preset_key in presets.keys():
		preset_dropdown.add_item(presets[preset_key]["name"], 0)
		preset_dropdown.set_item_metadata(preset_dropdown.item_count - 1, preset_key)
	
	# Description label
	var desc_label = Label.new()
	desc_label.text = presets["2_Local"]["description"]
	desc_label.add_theme_color_override("font_color", Color.GRAY)
	inner_vbox.add_child(desc_label)
	
	preset_dropdown.item_selected.connect(func(idx):
		var preset_key = preset_dropdown.get_item_metadata(idx)
		desc_label.text = presets[preset_key]["description"]
	)
	
	# Control buttons
	var button_hbox = HBoxContainer.new()
	button_hbox.add_theme_constant_override("separation", 8)
	inner_vbox.add_child(button_hbox)
	
	start_button = Button.new()
	start_button.text = "START SHOWCASE"
	start_button.custom_minimum_size = Vector2(150, 40)
	start_button.pressed.connect(_on_start_pressed)
	button_hbox.add_child(start_button)
	
	close_all_button = Button.new()
	close_all_button.text = "STOP ALL"
	close_all_button.custom_minimum_size = Vector2(100, 40)
	close_all_button.pressed.connect(stop_all_instances)
	button_hbox.add_child(close_all_button)
	
	# Status
	status_label = Label.new()
	status_label.text = "Ready to launch"
	status_label.add_theme_color_override("font_color", Color.WHITE)
	inner_vbox.add_child(status_label)
	
	inner_vbox.add_child(HSeparator.new())
	
	# Determinism panel
	determinism_panel = PanelContainer.new()
	determinism_panel.custom_minimum_size = Vector2(0, 50)
	var det_bg = StyleBoxFlat.new()
	det_bg.bg_color = Color(0.1, 0.1, 0.12, 1.0)
	determinism_panel.add_theme_stylebox_override("panel", det_bg)
	inner_vbox.add_child(determinism_panel)
	
	determinism_label = Label.new()
	determinism_label.text = "Determinism Checker: (waiting for instances)"
	determinism_label.add_theme_color_override("font_color", Color.YELLOW)
	determinism_panel.add_child(determinism_label)
	
	# Instance list
	var list_label = Label.new()
	list_label.text = "Active Instances:"
	inner_vbox.add_child(list_label)
	
	instance_list = ItemList.new()
	instance_list.custom_minimum_size = Vector2(0, 100)
	inner_vbox.add_child(instance_list)
	
	print("[LAUNCHER] UI built ✅")

func _update_instance_list() -> void:
	"""Update the instance list display."""
	instance_list.clear()
	
	for inst in active_instances:
		if not inst.is_initialized():
			continue
		
		var debug_info = inst.get_debug_info()
		var text = "Player %d | Tick: %d | Units: %d" % [
			inst.player_id,
			debug_info.get("current_tick", -1),
			debug_info.get("player_units", -1)
		]
		
		instance_list.add_item(text)

func _set_status(msg: String, color: Color = Color.WHITE) -> void:
	"""Update status label."""
	status_label.text = msg
	status_label.add_theme_color_override("font_color", color)
	print("[LAUNCHER] Status: %s" % msg)

## =========================================================================
## Callbacks
## =========================================================================

func _on_start_pressed() -> void:
	"""Start button pressed."""
	var preset_idx = preset_dropdown.selected
	if preset_idx < 0:
		_set_status("ERROR: No preset selected", Color.RED)
		return
	
	var preset_key = preset_dropdown.get_item_metadata(preset_idx)
	spawn_instances(preset_key)
