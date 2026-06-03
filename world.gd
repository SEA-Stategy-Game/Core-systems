extends Node2D
const PLAYER_SELECT_SCENE: PackedScene = preload("res://UI/PlayerSelectPopup.tscn")

var units = []
var headless: bool = false

func _init() -> void:
	if is_headless():
		headless = true
		
func _ready():
	get_units()
	if not headless:
		# Show the player-count pop-up; it spawns the starting units once the
	# user picks 1-4.  No automatic Game.spawnUnit() here.
	var popup = PLAYER_SELECT_SCENE.instantiate()
	add_child(popup)

		if has_node("Camera2D"):
			$Camera2D.area_selected.connect(_on_area_selected)
	if has_node("Camera2D"):
		$Camera2D.area_selected.connect(_on_area_selected)
	if Game.is_headless:
		if has_node("UI"):
			$UI.queue_free()
		if has_node("Camera2D"):
			$Camera2D.queue_free()

	get_units()
	if not Game.is_headless:
		# Show the player-count pop-up; it spawns the starting units once the
		# user picks 1-4.  No automatic Game.spawnUnit() here.
		var popup = PLAYER_SELECT_SCENE.instantiate()
		add_child(popup)

		if has_node("Camera2D"):
			$Camera2D.area_selected.connect(_on_area_selected)

	
	var stone = StoneResource.new()
	var new_id = ActionGateway.get_next_entity_id()
	stone.set("entity_id", new_id)
	add_child(stone)
	GlobalSignals.resource_created.emit(stone)

func get_units():
	units = null
	units = get_tree().get_nodes_in_group("units")

func _on_area_selected(camera):
	units = get_tree().get_nodes_in_group("units")
	var start = camera.start
	var end = camera.end
	var area = []
	area.append(Vector2(min(start.x, end.x), min(start.y, end.y)))
	area.append(Vector2(max(start.x, end.x), max(start.y, end.y)))
	var ut = get_units_in_area(area)
	for u in units:
		if u.has_method("set_selected"):
			u.set_selected(false)
	for u in ut:
		if u.has_method("set_selected"):
			u.set_selected(true)

# adds units in area draw to a list and returns them
func get_units_in_area(area):
	var u = []
	for unit in units:
		if unit.global_position.x > area[0].x and unit.global_position.x < area[1].x:
			if unit.global_position.y > area[0].y and unit.global_position.y < area[1].y:
				u.append(unit)

	return u

	
func is_headless() -> bool:
	return  (DisplayServer.get_name() == "headless") or (OS.has_feature("dedicated_server")) or ("--server" in OS.get_cmdline_args())
	
