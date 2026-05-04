extends Node
class_name GameMap

@export var width: int = 64
@export var height: int = 64
@export var tile_size: int = 32

var tiles: Array = []

func _ready() -> void:
    if tiles.is_empty():
        initialize_tiles()

func initialize_tiles() -> void:
    tiles.resize(width * height)
    for y in range(height):
        for x in range(width):
            tiles[_index(x, y)] = MapTile.new(x, y, MapTile.TerrainType.PLAINS)

func _index(x: int, y: int) -> int:
    return y * width + x

func in_bounds(x: int, y: int) -> bool:
    return x >= 0 and y >= 0 and x < width and y < height

func set_tile(x: int, y: int, terrain: int) -> void:
    if tiles.size() != width * height:
        initialize_tiles()
    if not in_bounds(x, y):
        return
    tiles[_index(x, y)].terrain = terrain

func get_tile(x: int, y: int):
    if not in_bounds(x, y):
        return null
    return tiles[_index(x, y)]

func _get_tile(x: int, y: int):
    return get_tile(x, y)
