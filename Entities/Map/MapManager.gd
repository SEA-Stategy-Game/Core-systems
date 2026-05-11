extends TileMapLayer

@export var tile_size: int = 32

# Change this instance to change the type of map that is generated
# E.g. GameMap, TestMap, or MapGenerator 
var game_map: GameMap = MapGenerator.new()
@onready var nav_region = $"/root/World/NavigationRegion2D"

func draw_tile(tile):
	set_cell(Vector2i(tile.x, tile.y), 0, tile.get_atlas_coordinates())

func _ready() -> void:
	if game_map.tiles.is_empty():
		game_map.initialize_tiles()
	for y in range(game_map.height):
		for x in range(game_map.width):
			draw_tile(game_map.tiles[_index(x, y)])
	nav_region.rebuild_nav()
	
func _index(x: int, y: int) -> int:
	return y * game_map.width + x

# Drawer for testing
func _input(event):
	return
	if event is InputEventMouseButton and event.pressed:
		var map_pos = local_to_map(
			to_local(get_global_mouse_position())
		)
		set_cell(map_pos, 0, Vector2i(0, 0))

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / tile_size)), int(floor(world_pos.y / tile_size)))

func get_tile_at_world_pos(world_pos: Vector2) -> Variant:
	var map_pos = local_to_map(to_local(world_pos))
	return game_map.get_tile(map_pos.x, map_pos.y)
