extends Node2D

const TestMap = preload("res://Entities/Map/TestMap.gd")

var units = []
var fog_of_war: FogOfWar = null
var game_map: GameMap

func _ready():
	get_units()
	Game.spawnUnit(position)
	if has_node("Camera2D"):
		$Camera2D.area_selected.connect(_on_area_selected)

	game_map = GameMap.new()
	game_map.width = 150
	game_map.height = 150
	game_map.tile_size = 32
	game_map.initialize_tiles()
	add_child(game_map)

	TestMap.build_test_map(game_map)

	if Engine.has_singleton("MapManager"):
		var mm = Engine.get_singleton("MapManager")
		if mm:
			mm.map_node = game_map
			mm.tile_size = game_map.tile_size

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