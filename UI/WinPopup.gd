extends CanvasLayer

## -----------------------------------------------------------------------
## WinPopup -- shown when WinConditionChecker decides a player has won.
## Builds its UI in code so no .tscn editing is required.
## -----------------------------------------------------------------------

@export var winning_player_id: int = 0
@export var reason: String = "combat"  ## "combat" or "economy"

func _ready() -> void:
	get_tree().paused = true
	_build_ui()

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(380, 220)
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title = Label.new()
	title.text = "Player %d wins!" % winning_player_id
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var desc = Label.new()
	if reason == "economy":
		desc.text = "Reached %d of a single resource." % Game.RESOURCE_WIN_THRESHOLD
	else:
		desc.text = "Last player standing."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(hbox)

	var restart = Button.new()
	restart.text = "Restart"
	restart.process_mode = Node.PROCESS_MODE_ALWAYS
	restart.pressed.connect(_on_restart)
	hbox.add_child(restart)

	var quit = Button.new()
	quit.text = "Quit"
	quit.process_mode = Node.PROCESS_MODE_ALWAYS
	quit.pressed.connect(_on_quit)
	hbox.add_child(quit)

func _on_restart() -> void:
	get_tree().paused = false
	Game.game_over = false
	Game.player_resources.clear()
	Game.Wood = 0
	Game.Stone = 0
	get_tree().reload_current_scene()

func _on_quit() -> void:
	get_tree().paused = false
	get_tree().quit()
