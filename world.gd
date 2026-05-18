extends Node2D


var units = []

func _ready():
	get_units()
	if has_node("Camera2D"):
		$Camera2D.area_selected.connect(_on_area_selected)
	#if Engine.has_singleton("MapManager"):
	#	var mm = Engine.get_singleton("MapManager")
	#	if mm:
	#		mm.map_node = game_map
	#		mm.tile_size = game_map.tile_size

func get_units():
	units = []
	for node in get_tree().get_nodes_in_group("units"):
		if node is Unit:
			units.append(node)

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
		if u.has_method("set_selected") and u.has_method("can_accept_local_input") and u.can_accept_local_input():
			u.set_selected(true)

# adds units in area draw to a list and returns them
func get_units_in_area(area):
	var u = []
	for unit in units:
		if unit.has_method("can_accept_local_input") and not unit.can_accept_local_input():
			continue
		if unit.global_position.x > area[0].x and unit.global_position.x < area[1].x:
			if unit.global_position.y > area[0].y and unit.global_position.y < area[1].y:
				u.append(unit)
				
	return u
