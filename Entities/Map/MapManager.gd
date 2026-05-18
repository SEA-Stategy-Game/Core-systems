extends TileMapLayer

@export var tile_size: int = 32

const TestMapScript = preload("res://Entities/Map/TestMap.gd")
@onready var game_map: TestMap = TestMapScript.new()
@onready var nav_region = get_node_or_null("/root/World/NavigationRegion2D")

func draw_tile(tile) -> void:
    if tile == null:
        return
    set_cell(Vector2i(tile.x, tile.y), 0, tile.get_atlas_coordinates())

func _ready() -> void:
    if game_map.tiles.is_empty():
        game_map.initialize_tiles()

    for y in range(game_map.height):
        for x in range(game_map.width):
            var tile = game_map.get_tile(x, y)
            if tile == null:
                continue
            draw_tile(tile)

    if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
        return

    var resource_spawner = get_node_or_null("/root/ResourceSpawner")
    game_map.populate_tiles(resource_spawner)

    if nav_region != null and nav_region.has_method("rebuild_nav"):
        nav_region.rebuild_nav()

func _index(x: int, y: int) -> int:
    return y * game_map.width + x