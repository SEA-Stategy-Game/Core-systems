extends CanvasLayer

## -----------------------------------------------------------------------
## Developer Debug Window
## Provides a live GUI to manually override/inject commands to the ActionGateway
## testing ownership logic, combat, and composite commands without AI JSON.
## Toggle with F1 or Tilde (~).
## -----------------------------------------------------------------------

var window: Window

# Inputs
var unit_id_input: SpinBox
var player_id_input: SpinBox
var target_id_input: SpinBox
var x_input: SpinBox
var y_input: SpinBox

# Output
var status_label: Label
var console_log: RichTextLabel

# Telemetry state tracking
var _last_action_type: String = ""
var _last_action_state: int = -1

func _ready() -> void:
	_build_ui()
	
	# Connect to ActionGateway for logging
	var gw = get_node_or_null("/root/ActionGateway")
	if gw:
		# Using pass-throughs because the Gateway might not be fully initialized yet
		gw.task_completed.connect(_on_task_completed)
		gw.task_failed.connect(_on_task_failed)
	
	# Print initial log
	_log("[SYS_READY] Debug Interface Initialised.")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1 or event.keycode == KEY_QUOTELEFT:
			window.visible = not window.visible

func _process(_delta: float) -> void:
	if not window.visible:
		return
	
	var gw = get_node_or_null("/root/ActionGateway")
	if not gw:
		status_label.text = "[ERROR] ActionGateway not found!"
		return
	
	var uid = int(unit_id_input.value)
	var pid = int(player_id_input.value)
	
	var sense = gw.sense()
	var status = sense.get_unit_status(uid)
	
	if status.is_empty():
		status_label.text = "Unit [" + str(uid) + "] Status: NOT_FOUND | Current Action: NONE"
		_last_action_type = ""
		_last_action_state = -1
		return
		
	var is_idle = status.get("is_idle", true)
	var state_str = "IDLE" if is_idle else "BUSY"
	var action_str = "NONE"
	
	var current_action = status.get("current_action")
	if current_action:
		action_str = current_action.get("type", "UNKNOWN")
		var st = current_action.get("state", -1)
		
		# Log state transitions into executing
		if not is_idle and action_str != _last_action_type:
			_log("[CMD_EXECUTING] Unit " + str(uid) + " began executing: " + action_str)
			_last_action_type = action_str
			_last_action_state = st
	else:
		_last_action_type = ""
		_last_action_state = -1
		
	status_label.text = "Unit [" + str(uid) + "] Status: " + state_str + " | Current Action: " + action_str
	
	# Display actual player ownership of the unit
	var real_owner = status.get("player_id", "UNKNOWN")
	status_label.text += " | Owner: P" + str(real_owner)

# -----------------------------------------------------------------
# Button Handlers
# -----------------------------------------------------------------

func _on_btn_move() -> void:
	var gw = get_node("/root/ActionGateway")
	var dest = Vector2(x_input.value, y_input.value)
	var res = gw.move_unit(int(unit_id_input.value), dest, int(player_id_input.value))
	_handle_cmd_result("MOVE", res)

func _on_btn_chop() -> void:
	var gw = get_node("/root/ActionGateway")
	var res = gw.go_chop_tree_and_return(int(unit_id_input.value), int(target_id_input.value), int(player_id_input.value))
	_handle_cmd_result("CHOP_AND_RETURN", res)

func _on_btn_attack() -> void:
	var gw = get_node("/root/ActionGateway")
	var res = gw.attack_target(int(unit_id_input.value), int(target_id_input.value), int(player_id_input.value))
	_handle_cmd_result("ATTACK", res)

func _on_btn_collect() -> void:
	var gw = get_node("/root/ActionGateway")
	# Mapping collect to mine stone for variety, or generic harvest
	var res = gw.go_mine_stone(int(unit_id_input.value), int(target_id_input.value), int(player_id_input.value))
	_handle_cmd_result("COLLECT_STONE", res)

func _handle_cmd_result(cmd_name: String, success: bool) -> void:
	if success:
		_log("[CMD_SENT] " + cmd_name + " command dispatched to queue.")
	else:
		_log("[CMD_DENIED: WRONG_OWNER] " + cmd_name + " failed ownership validation or target invalid.")

func _on_task_completed(unit_id: int, action_data: Dictionary) -> void:
	var t = action_data.get("type", "UNKNOWN")
	_log("[CMD_COMPLETE] Unit " + str(unit_id) + " finished " + t)

func _on_task_failed(unit_id: int, action_data: Dictionary) -> void:
	var t = action_data.get("type", "UNKNOWN")
	_log("[CMD_FAILED] Unit " + str(unit_id) + " failed " + t)

func _log(msg: String) -> void:
	if console_log:
		console_log.text += msg + "\n"
		console_log.scroll_to_line(console_log.get_line_count() - 1)

# -----------------------------------------------------------------
# Dynamic UI Generation (Prevents Tscn corruption/missing node IDs)
# -----------------------------------------------------------------

func _build_ui() -> void:
	window = Window.new()
	window.title = "Developer Tools - ActionGateway Override (Press ~ or F1)"
	window.size = Vector2(480, 520)
	window.position = Vector2(50, 50)
	window.visible = false
	window.close_requested.connect(func(): window.hide())
	add_child(window)
	
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(bg)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	window.add_child(vbox)
	
	# Add Padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(margin)
	
	var inner_vbox = VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(inner_vbox)
	
	# Live Telemetry Status
	status_label = Label.new()
	status_label.text = "Unit [?] Status: IDLE | Current Action: NONE"
	status_label.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0))
	inner_vbox.add_child(status_label)
	
	inner_vbox.add_child(HSeparator.new())
	
	# --- Input Section ---
	var grid = GridContainer.new()
	grid.columns = 2
	inner_vbox.add_child(grid)
	
	# Unit ID
	grid.add_child(_create_label("Target Unit ID:"))
	unit_id_input = _create_spinbox(0, 10000, 10) # arbitrary default UID
	grid.add_child(unit_id_input)
	
	# Player Identity
	grid.add_child(_create_label("Active Player ID:"))
	player_id_input = _create_spinbox(0, 10, 0)
	grid.add_child(player_id_input)
	
	# Target ID
	grid.add_child(_create_label("Target Entity ID:"))
	target_id_input = _create_spinbox(0, 10000, 0)
	grid.add_child(target_id_input)
	
	# Dest X & Y
	grid.add_child(_create_label("Dest X / Y:"))
	var xy_box = HBoxContainer.new()
	x_input = _create_spinbox(-5000, 5000, 200)
	y_input = _create_spinbox(-5000, 5000, 200)
	xy_box.add_child(x_input)
	xy_box.add_child(y_input)
	grid.add_child(xy_box)
	
	inner_vbox.add_child(HSeparator.new())
	
	# --- Buttons ---
	var btn_grid = GridContainer.new()
	btn_grid.columns = 2
	btn_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner_vbox.add_child(btn_grid)
	
	btn_grid.add_child(_create_btn("MOVE", _on_btn_move))
	btn_grid.add_child(_create_btn("CHOP & RETURN", _on_btn_chop))
	btn_grid.add_child(_create_btn("ATTACK", _on_btn_attack))
	btn_grid.add_child(_create_btn("COLLECT", _on_btn_collect))
	
	inner_vbox.add_child(HSeparator.new())
	
	# --- Console Log ---
	var console_lbl = Label.new()
	console_lbl.text = "Console Output:"
	inner_vbox.add_child(console_lbl)
	
	console_log = RichTextLabel.new()
	console_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	console_log.scroll_following = true
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08)
	console_log.add_theme_stylebox_override("normal", sb)
	inner_vbox.add_child(console_log)

func _create_label(t: String) -> Label:
	var l = Label.new()
	l.text = t
	return l

func _create_spinbox(min_val: float, max_val: float, default_val: float) -> SpinBox:
	var sb = SpinBox.new()
	sb.min_value = min_val
	sb.max_value = max_val
	sb.value = default_val
	sb.allow_greater = true
	sb.allow_lesser = true
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return sb

func _create_btn(t: String, callable: Callable) -> Button:
	var b = Button.new()
	b.text = t
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(callable)
	return b
