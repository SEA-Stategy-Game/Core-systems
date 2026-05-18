extends RefCounted
class_name GameMap

var tiles: Array = []
var width = 256 #obs
var height = 256 #obs

func _ready() -> void:
	pass
		
func _init() -> void:
	_ensure_tiles_initialized()

func _ensure_tiles_initialized() -> void:
	if tiles.size() != width * height or tiles.has(null):
		initialize_tiles()

func populate_tiles():
	_ensure_tiles_initialized()
	for y in range(height):
		for x in range(width):
			var tile = get_tile(x, y)
			if tile != null:
				tile.try_spawn_resource()

func initialize_tiles() -> void:
	tiles.resize(width * height)
	for y in range(height):
		for x in range(width):
			tiles[_index(x, y)] = MapTile.new(x, y, MapTile.TerrainType.PLAINS, null)

func _index(x: int, y: int) -> int:
	return y * width + x

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height

func set_tile(x: int, y: int, terrain: int) -> void:
	if not in_bounds(x, y):
		return
	if tiles.size() != width * height:
		initialize_tiles()
	var tile := tiles[_index(x, y)]
	if tile == null:
		tile = MapTile.new(x, y, MapTile.TerrainType.PLAINS, null)
		tiles[_index(x, y)] = tile
	tile.terrain = terrain

func get_tile(x: int, y: int):
	if not in_bounds(x, y):
		return null
	if tiles.size() != width * height:
		initialize_tiles()
	return tiles[_index(x, y)]

func get_all_tiles():
	return tiles;

func _get_tile(x: int, y: int):
	return get_tile(x, y)
