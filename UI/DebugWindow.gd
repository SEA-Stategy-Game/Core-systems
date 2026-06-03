extends CanvasLayer

## -----------------------------------------------------------------------
## Developer Debug Window
## Full dashboard: world telemetry, per-player stockpile + win progress,
## live unit roster, building / resource counts, ID-free ActionGateway
## commands, and a rolling console log.
## Toggle with F1 or Tilde (~).
## -----------------------------------------------------------------------

const ROSTER_LIMIT: int = 60
const CONSOLE_BUFFER_LINES: int = 200

var window: Window

# Inputs
var unit_id_input: SpinBox
var player_id_input: SpinBox
var x_input: SpinBox
var y_input: SpinBox

# Top dashboard labels
var tick_label: Label
var status_label: Label
var stockpile_label: Label
var counts_label: Label
var win_progress_label: Label

# Live tables
var unit_roster: RichTextLabel
var building_roster: RichTextLabel
var resource_roster: RichTextLabel

# Console
var console_log: RichTextLabel

# Telemetry state tracking
var _last_action_type: String = ""

func _ready() -> void:
	if Game.is_headless:
		queue_free()
		return
	_build_ui()

	# Connect to ActionGateway for log lines
	var gw = get_node_or_null("/root/ActionGateway")
	if gw:
		if gw.has_signal("task_completed"):
			gw.task_completed.connect(_on_task_completed)
		if gw.has_signal("task_failed"):
			gw.task_failed.connect(_on_task_failed)
		if gw.has_signal("plan_execution_finished"):
			gw.plan_execution_finished.connect(_on_plan_finished)
		if gw.has_signal("unit_idled"):
			gw.unit_idled.connect(_on_unit_idled)

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

	# --- Top tick / focus line ---
	var tm = get_node_or_null("/root/TickManager")
	var tick = tm.tick_count if tm and "tick_count" in tm else 0
	tick_label.text = "Tick: %d   |   game_over: %s   |   player_count: %d" % [
		tick, str(Game.game_over), Game.player_count
	]

	# --- Focus unit detail ---
	var uid = int(unit_id_input.value)
	var sense = gw.sense()
	var status = sense.get_unit_status(uid)
	if status.is_empty():
		status_label.text = "Focus Unit [%d] NOT_FOUND" % uid
		_last_action_type = ""
	else:
		var is_idle = status.get("is_idle", true)
		var state_str = "IDLE" if is_idle else "BUSY"
		var action_str = "NONE"
		var current_action = status.get("current_action")
		if current_action:
			action_str = current_action.get("type", "UNKNOWN")
			if not is_idle and action_str != _last_action_type:
				_log("[CMD_EXECUTING] Unit %d began executing: %s" % [uid, action_str])
				_last_action_type = action_str
		else:
			_last_action_type = ""
		var hp = status.get("health", "?")
		var max_hp = status.get("max_health", "?")
		var owner = status.get("player_id", "?")
		var pos = status.get("position", {"x": 0, "y": 0})
		status_label.text = "Focus Unit [%d]  P%s  HP %s/%s  pos (%.0f, %.0f)  %s  %s" % [
			uid, str(owner), str(hp), str(max_hp),
			pos.get("x", 0), pos.get("y", 0), state_str, action_str
		]

	_refresh_stockpile()
	_refresh_counts(sense)
	_refresh_win_progress()
	_refresh_unit_roster(sense)
	_refresh_building_roster(sense)
	_refresh_resource_roster(sense)

# -----------------------------------------------------------------
# Dashboard refresh helpers
# -----------------------------------------------------------------

func _refresh_stockpile() -> void:
	var lines: Array[String] = []
	var count = max(1, Game.player_count)
	for p in range(count):
		lines.append("P%d  Wood %2d   Stone %2d" % [
			p, Game.get_player_wood(p), Game.get_player_stone(p)
		])
	stockpile_label.text = "Stockpile\n" + "\n".join(lines)

func _refresh_counts(sense) -> void:
	var units = sense.get_all_units() if sense.has_method("get_all_units") else []
	var resources = sense.get_all_resources() if sense.has_method("get_all_resources") else []
	var buildings = sense.get_all_buildings() if sense.has_method("get_all_buildings") else []

	# Per-player unit / building tally
	var per_player: Dictionary = {}
	for u in units:
		var p = int(u.get("player_id", -1))
		if p == -1:
			continue
		per_player[p] = per_player.get(p, {"units": 0, "buildings": 0})
		per_player[p]["units"] += 1
	for b in buildings:
		var p = int(b.get("player_id", -1))
		if p == -1:
			continue
		per_player[p] = per_player.get(p, {"units": 0, "buildings": 0})
		per_player[p]["buildings"] += 1

	var trees = 0
	var stones = 0
	for r in resources:
		var n = String(r.get("name", "")).to_lower()
		if n.contains("tree"):
			trees += 1
		elif n.contains("stone") or n.contains("rock"):
			stones += 1

	var per_player_str: Array[String] = []
	var keys = per_player.keys()
	keys.sort()
	for p in keys:
		per_player_str.append("P%d  units %d  buildings %d" % [
			p, per_player[p]["units"], per_player[p]["buildings"]
		])
	counts_label.text = "World counts\n  Units: %d   Buildings: %d   Trees: %d   Stones: %d\n%s" % [
		units.size(), buildings.size(), trees, stones,
		("  " + "\n  ".join(per_player_str)) if per_player_str.size() > 0 else ""
	]

func _refresh_win_progress() -> void:
	var lines: Array[String] = ["Win progress (50 wood OR 50 stone)"]
	var count = max(1, Game.player_count)
	for p in range(count):
		var w = Game.get_player_wood(p)
		var s = Game.get_player_stone(p)
		var w_bar = _bar(w, Game.RESOURCE_WIN_THRESHOLD)
		var s_bar = _bar(s, Game.RESOURCE_WIN_THRESHOLD)
		lines.append("  P%d  W %s %d/%d   S %s %d/%d" % [
			p, w_bar, w, Game.RESOURCE_WIN_THRESHOLD,
			s_bar, s, Game.RESOURCE_WIN_THRESHOLD
		])
	win_progress_label.text = "\n".join(lines)

func _bar(value: int, max_value: int, width: int = 12) -> String:
	var ratio = clampf(float(value) / float(max(1, max_value)), 0.0, 1.0)
	var filled = int(round(ratio * width))
	return "[" + ("=").repeat(filled) + (".").repeat(width - filled) + "]"

func _refresh_unit_roster(sense) -> void:
	if not sense.has_method("get_all_units"):
		unit_roster.text = "(SenseAPI has no get_all_units)"
		return
	var units = sense.get_all_units()
	var rows: Array[String] = []
	rows.append("[b]id   P    HP        idle   action[/b]")
	var displayed = 0
	for u in units:
		if displayed >= ROSTER_LIMIT:
			break
		var pid = int(u.get("player_id", -1))
		var hp = int(u.get("health", 0))
		var max_hp = int(u.get("max_health", 0))
		var is_idle = bool(u.get("is_idle", true))
		var pending = int(u.get("pending_actions", 0))
		var status = sense.get_unit_status(int(u.get("id", -1)))
		var action_str = "—"
		var cur = status.get("current_action")
		if cur != null and cur is Dictionary:
			action_str = String(cur.get("type", "—"))
		rows.append("%4d  P%d  %3d/%-3d  %-5s  %s  [+%d]" % [
			int(u.get("id", -1)), pid, hp, max_hp,
			"idle" if is_idle else "busy",
			action_str, pending
		])
		displayed += 1
	if units.size() > ROSTER_LIMIT:
		rows.append("... (+%d more)" % (units.size() - ROSTER_LIMIT))
	unit_roster.text = "\n".join(rows)

func _refresh_building_roster(sense) -> void:
	if not sense.has_method("get_all_buildings"):
		building_roster.text = "(no SenseAPI.get_all_buildings)"
		return
	var buildings = sense.get_all_buildings()
	if buildings.is_empty():
		building_roster.text = "[i]no buildings[/i]"
		return
	var rows: Array[String] = ["[b]id   P    HP       name[/b]"]
	for b in buildings:
		rows.append("%4d  P%d  %4d     %s" % [
			int(b.get("id", -1)),
			int(b.get("player_id", -1)),
			int(b.get("health", -1)),
			String(b.get("name", ""))
		])
	building_roster.text = "\n".join(rows)

func _refresh_resource_roster(sense) -> void:
	if not sense.has_method("get_all_resources"):
		resource_roster.text = "(no SenseAPI.get_all_resources)"
		return
	var resources = sense.get_all_resources()
	if resources.is_empty():
		resource_roster.text = "[i]no resources[/i]"
		return
	var trees: Array = []
	var stones: Array = []
	for r in resources:
		var nm = String(r.get("name", "")).to_lower()
		if nm.contains("tree"):
			trees.append(r)
		elif nm.contains("stone") or nm.contains("rock"):
			stones.append(r)
	resource_roster.text = "Trees: %d    Stones: %d" % [trees.size(), stones.size()]

# -----------------------------------------------------------------
# Button handlers  (ID-free)
# -----------------------------------------------------------------

func _on_btn_move() -> void:
	var gw = get_node("/root/ActionGateway")
	var dest = Vector2(x_input.value, y_input.value)
	var res = gw.move_unit(int(unit_id_input.value), dest, int(player_id_input.value))
	_handle_cmd_result("MOVE", res)

func _on_btn_chop_nearest() -> void:
	var gw = get_node("/root/ActionGateway")
	var res = gw.go_chop_nearest_tree(int(unit_id_input.value), int(player_id_input.value))
	_handle_cmd_result("CHOP_NEAREST", res)

func _on_btn_chop_nearest_return() -> void:
	var gw = get_node("/root/ActionGateway")
	var res = gw.go_chop_nearest_tree_and_return(int(unit_id_input.value), int(player_id_input.value))
	_handle_cmd_result("CHOP_NEAREST_AND_RETURN", res)

func _on_btn_mine_nearest() -> void:
	var gw = get_node("/root/ActionGateway")
	var res = gw.go_mine_nearest_stone(int(unit_id_input.value), int(player_id_input.value))
	_handle_cmd_result("MINE_NEAREST", res)

func _on_btn_attack_nearest() -> void:
	var gw = get_node("/root/ActionGateway")
	var res = gw.attack_nearest_enemy(int(unit_id_input.value), int(player_id_input.value))
	_handle_cmd_result("ATTACK_NEAREST", res)

func _on_btn_attack_move() -> void:
	var gw = get_node("/root/ActionGateway")
	var dest = Vector2(x_input.value, y_input.value)
	var res = gw.attack_move(int(unit_id_input.value), dest, int(player_id_input.value))
	_handle_cmd_result("ATTACK_MOVE", res)

func _on_btn_construct_barracks() -> void:
	var gw = get_node("/root/ActionGateway")
	var dest = Vector2(x_input.value, y_input.value)
	var res = gw.go_construct(
		int(unit_id_input.value),
		"res://Houses/Barracks.tscn",
		dest, 10.0,
		int(player_id_input.value)
	)
	_handle_cmd_result("CONSTRUCT(Barracks)", res)

func _on_btn_grant_resources() -> void:
	var pid = int(player_id_input.value)
	Game.add_resource(pid, "wood", 10)
	Game.add_resource(pid, "stone", 5)
	_log("[CHEAT] +10 wood / +5 stone granted to player %d" % pid)

func _on_btn_force_win_check() -> void:
	var wcc = get_node_or_null("/root/WinConditionChecker")
	if wcc == null:
		_log("[ERROR] WinConditionChecker not loaded.")
		return
	var fired = wcc.check_now()
	_log("[WIN_CHECK] check_now() returned %s" % str(fired))

func _on_btn_smart_behavior() -> void:
	# Demo: arm the acting unit with the canonical reactive plan
	#   "chop trees, fight if attacked, balance resources".
	var gw = get_node("/root/ActionGateway")
	var uid = int(unit_id_input.value)
	var pid = int(player_id_input.value)
	var rules = [
		{"when": "enemy_within(100)",  "do": "ATTACK_NEAREST",          "priority": 100},
		{"when": "wood > stone",       "do": "MINE_NEAREST",            "priority":  60},
		{"when": "stone > wood",       "do": "CHOP_NEAREST_AND_RETURN", "priority":  60},
		{"when": "idle",               "do": "CHOP_NEAREST_AND_RETURN", "priority":  10},
	]
	var ok = gw.set_behavior_plan(uid, rules, pid)
	_log("[BEHAVIOR] Armed reactive plan on unit %d (player %d): %s" % [uid, pid, str(ok)])

func _on_btn_clear_behavior() -> void:
	var gw = get_node("/root/ActionGateway")
	gw.clear_behavior_plan(int(unit_id_input.value), int(player_id_input.value))
	_log("[BEHAVIOR] Cleared plan on unit %d" % int(unit_id_input.value))

func _on_btn_clear_console() -> void:
	if console_log:
		console_log.text = ""

func _handle_cmd_result(cmd_name: String, success: bool) -> void:
	if success:
		_log("[CMD_SENT] %s dispatched to queue." % cmd_name)
	else:
		_log("[CMD_DENIED] %s — ownership/target invalid." % cmd_name)

# -----------------------------------------------------------------
# Signal relays
# -----------------------------------------------------------------

func _on_task_completed(unit_id: int, action_data: Dictionary) -> void:
	_log("[CMD_COMPLETE] Unit %d finished %s" % [unit_id, String(action_data.get("type", "UNKNOWN"))])

func _on_task_failed(unit_id: int, action_data: Dictionary) -> void:
	_log("[CMD_FAILED] Unit %d failed %s" % [unit_id, String(action_data.get("type", "UNKNOWN"))])

func _on_plan_finished(plan_id: String) -> void:
	_log("[PLAN_DONE] %s dispatched." % plan_id)

func _on_unit_idled(unit_id: int) -> void:
	_log("[UNIT_IDLED] Unit %d became idle." % unit_id)

func _log(msg: String) -> void:
	if not console_log:
		return
	console_log.text += msg + "\n"
	# Trim buffer.
	var line_count = console_log.get_line_count()
	if line_count > CONSOLE_BUFFER_LINES:
		var lines = console_log.text.split("\n")
		console_log.text = "\n".join(lines.slice(lines.size() - CONSOLE_BUFFER_LINES))
	console_log.scroll_to_line(console_log.get_line_count() - 1)

# -----------------------------------------------------------------
# UI generation
# -----------------------------------------------------------------

func _build_ui() -> void:
	window = Window.new()
	window.title = "Core Debug Dashboard  (F1 or ~)"
	window.size = Vector2(760, 900)
	window.position = Vector2(40, 40)
	window.visible = false
	window.close_requested.connect(func(): window.hide())
	add_child(window)

	var bg = ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.12, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(bg)

	# Whole window is one big scroll container.
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	window.add_child(scroll)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	var root_v = VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 10)
	root_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(root_v)

	# ---------------- World summary ----------------
	tick_label = _header("Tick: 0", Color(0.5, 0.9, 1.0))
	root_v.add_child(tick_label)

	status_label = Label.new()
	status_label.text = "Focus Unit [?]"
	status_label.add_theme_color_override("font_color", Color(0.6, 0.95, 0.65))
	root_v.add_child(status_label)

	stockpile_label = Label.new()
	stockpile_label.text = "Stockpile"
	stockpile_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	root_v.add_child(stockpile_label)

	counts_label = Label.new()
	counts_label.text = "World counts"
	counts_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.95))
	root_v.add_child(counts_label)

	win_progress_label = Label.new()
	win_progress_label.text = "Win progress"
	var mono = ThemeDB.fallback_font  # default; renders monospace-ish
	win_progress_label.add_theme_color_override("font_color", Color(0.95, 0.6, 0.85))
	root_v.add_child(win_progress_label)

	root_v.add_child(HSeparator.new())

	# ---------------- Unit roster ----------------
	root_v.add_child(_header("Unit roster", Color(0.7, 1.0, 0.7)))
	unit_roster = _make_richtext(180)
	root_v.add_child(unit_roster)

	# ---------------- Building roster ----------------
	root_v.add_child(_header("Buildings", Color(0.95, 0.85, 0.55)))
	building_roster = _make_richtext(90)
	root_v.add_child(building_roster)

	# ---------------- Resource roster ----------------
	root_v.add_child(_header("Resources in world", Color(0.7, 0.95, 0.85)))
	resource_roster = _make_richtext(40)
	root_v.add_child(resource_roster)

	root_v.add_child(HSeparator.new())

	# ---------------- Input row ----------------
	root_v.add_child(_header("Inputs", Color(0.85, 0.85, 0.85)))

	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_v.add_child(grid)

	grid.add_child(_label("Acting Unit ID:"))
	unit_id_input = _spinbox(0, 10000, 1)
	grid.add_child(unit_id_input)

	grid.add_child(_label("Active Player ID:"))
	player_id_input = _spinbox(0, 10, 0)
	grid.add_child(player_id_input)

	grid.add_child(_label("Dest X / Y:"))
	var xy = HBoxContainer.new()
	x_input = _spinbox(-5000, 5000, 400)
	y_input = _spinbox(-5000, 5000, 300)
	xy.add_child(x_input)
	xy.add_child(y_input)
	grid.add_child(xy)

	root_v.add_child(HSeparator.new())

	# ---------------- Commands ----------------
	root_v.add_child(_header("Commands  (auto-target nearest)", Color(0.55, 1.0, 0.65)))
	var btns = GridContainer.new()
	btns.columns = 2
	btns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_v.add_child(btns)

	btns.add_child(_btn("MOVE (to X/Y)", _on_btn_move))
	btns.add_child(_btn("ATTACK-MOVE (to X/Y)", _on_btn_attack_move))
	btns.add_child(_btn("CHOP NEAREST TREE", _on_btn_chop_nearest))
	btns.add_child(_btn("CHOP NEAREST + RETURN", _on_btn_chop_nearest_return))
	btns.add_child(_btn("MINE NEAREST STONE", _on_btn_mine_nearest))
	btns.add_child(_btn("ATTACK NEAREST ENEMY", _on_btn_attack_nearest))
	btns.add_child(_btn("CONSTRUCT BARRACKS (X/Y)", _on_btn_construct_barracks))

	root_v.add_child(HSeparator.new())

	root_v.add_child(_header("Game-state helpers", Color(1.0, 0.65, 0.65)))
	var helpers = GridContainer.new()
	helpers.columns = 3
	helpers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_v.add_child(helpers)
	helpers.add_child(_btn("Grant +10W / +5S", _on_btn_grant_resources))
	helpers.add_child(_btn("Force win-check", _on_btn_force_win_check))
	helpers.add_child(_btn("Clear console", _on_btn_clear_console))
	helpers.add_child(_btn("Arm reactive plan", _on_btn_smart_behavior))
	helpers.add_child(_btn("Clear reactive plan", _on_btn_clear_behavior))

	root_v.add_child(HSeparator.new())

	# ---------------- Console ----------------
	root_v.add_child(_header("Console", Color(0.85, 0.85, 0.85)))
	console_log = _make_richtext(220)
	console_log.scroll_following = true
	root_v.add_child(console_log)

# -----------------------------------------------------------------
# UI primitives
# -----------------------------------------------------------------

func _header(text: String, color: Color) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 15)
	return l

func _label(text: String) -> Label:
	var l = Label.new()
	l.text = text
	return l

func _spinbox(min_val: float, max_val: float, default_val: float) -> SpinBox:
	var sb = SpinBox.new()
	sb.min_value = min_val
	sb.max_value = max_val
	sb.value = default_val
	sb.allow_greater = true
	sb.allow_lesser = true
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return sb

func _btn(text: String, callable: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(callable)
	return b

func _make_richtext(min_height: float) -> RichTextLabel:
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(0, min_height)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	rt.add_theme_stylebox_override("normal", sb)
	return rt
