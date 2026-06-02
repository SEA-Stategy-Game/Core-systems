extends CanvasLayer

## -----------------------------------------------------------------------
## PlayerSelectPopup
## Asks the user how many players to start the match with (1-4).
## On confirmation it spawns the requested number of starting units
## (one per player, distinct spawn positions, each with a unique player_id)
## and arms the WinConditionChecker.
## -----------------------------------------------------------------------

signal players_chosen(count: int)

@onready var unit_scene = preload("res://Entities/Units/unit.tscn")

const SPAWN_RING_RADIUS: float = 180.0
const STARTING_WOOD: int = 0
const STARTING_STONE: int = 0
static var next_starting_id: int = 1

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	# Dim background
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Centred panel
	var panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(360, 200)
	add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	vbox.add_child(margin)

	var inner = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	margin.add_child(inner)

	var title = Label.new()
	title.text = "How many players?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	inner.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Solo: win by stockpiling 50 wood or 50 stone.\n2-4 players: also win by eliminating rivals."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD
	inner.add_child(subtitle)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	inner.add_child(hbox)

	for i in range(1, 5):
		var b = Button.new()
		b.text = str(i)
		b.custom_minimum_size = Vector2(48, 48)
		var n = i  # capture
		b.pressed.connect(func(): _on_count_pressed(n))
		hbox.add_child(b)

func _on_count_pressed(count: int) -> void:
	count = clampi(count, 1, 4)
	Game.player_count = count
	Game.game_over = false

	_spawn_starting_units(count)

	players_chosen.emit(count)
	print("[GAME_START] ", count, " player(s) chosen. Starting units spawned.")
	queue_free()

func _spawn_starting_units(count: int) -> void:
	var world = get_tree().get_root().get_node_or_null("World")
	var units_node = get_tree().get_root().get_node_or_null("World/Units")
	if world == null or units_node == null:
		push_error("PlayerSelectPopup: World/Units container not found.")
		return

	# Pick a centre from the existing Camera2D position (the camera looks at the play area).
	var centre: Vector2 = Vector2(573, 323)
	var cam = world.get_node_or_null("Camera2D")
	if cam:
		centre = cam.position

	for pid in range(count):
		Game._ensure(pid)
		# Seed starting stockpile so players can act immediately.
		Game.player_resources[pid]["wood"] = STARTING_WOOD
		Game.player_resources[pid]["stone"] = STARTING_STONE

		var angle = TAU * float(pid) / float(count)
		var pos = centre + Vector2(cos(angle), sin(angle)) * SPAWN_RING_RADIUS

		var u = unit_scene.instantiate()
		u.entity_id = next_starting_id
		next_starting_id += 1
		u.player_id = pid
		u.position = pos
		units_node.add_child(u)
		print("[GAME_START] Spawned starter unit ", u.entity_id, " for player ", pid, " at ", pos)

	Game._sync_legacy()

	if world.has_method("get_units"):
		world.get_units()
