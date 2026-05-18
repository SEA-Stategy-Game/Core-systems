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
    if resource_spawner != null and resource_spawner.has_method("set_rng"):
        var rng: RandomNumberGenerator = RandomNumberGenerator.new()
        rng.seed = 42
        resource_spawner.set_rng(rng)
    game_map.populate_tiles(resource_spawner, tile_size)

    if nav_region != null and nav_region.has_method("rebuild_nav"):
        nav_region.rebuild_nav()

func world_to_grid(world_pos: Vector2) -> Vector2i:
    return Vector2i(int(floor(world_pos.x / tile_size)), int(floor(world_pos.y / tile_size)))

func get_tile_at_world_pos(world_pos: Vector2) -> Variant:
    var gpos = world_to_grid(world_pos)
    if game_map != null:
        return game_map.get_tile(gpos.x, gpos.y)
    return null

func _index(x: int, y: int) -> int:
    return y * game_map.width + x

func clear_map_object_at_world_pos(world_pos: Vector2) -> void:
    var grid_pos := world_to_grid(world_pos)
    var tile: MapTile = game_map.get_tile(grid_pos.x, grid_pos.y)
    if tile != null:
        tile.clear_map_object()

func set_map_object_at_world_pos(world_pos: Vector2, map_object: Variant) -> void:
    var grid_pos := world_to_grid(world_pos)
    var tile: MapTile = game_map.get_tile(grid_pos.x, grid_pos.y)
    if tile != null:
        tile.set_map_object(map_object)