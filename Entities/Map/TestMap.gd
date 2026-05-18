extends RefCounted
class_name TestMap

var tiles: Array[MapTile] = []
var width: int = 32
var height: int = 32

func _init() -> void:
    initialize_tiles()

func _index(x: int, y: int) -> int:
    return y * width + x

func in_bounds(x: int, y: int) -> bool:
    return x >= 0 and y >= 0 and x < width and y < height

func set_tile(x: int, y: int, terrain: int) -> void:
    if not in_bounds(x, y):
        return
    var tile: MapTile = get_tile(x, y)
    if tile == null:
        tile = MapTile.new(x, y, MapTile.TerrainType.PLAINS, null)
        tiles[_index(x, y)] = tile
    tile.terrain = terrain

func get_tile(x: int, y: int) -> MapTile:
    if not in_bounds(x, y):
        return null
    return tiles[_index(x, y)]

func get_all_tiles() -> Array[MapTile]:
    return tiles

func populate_tiles(spawner: Node = null, tile_size: int = 32) -> void:
    if spawner == null or not spawner.has_method("spawn_resource"):
        return

    for y in range(height):
        for x in range(width):
            var tile: MapTile = get_tile(x, y)
            if tile == null:
                continue

            var spawned = spawner.spawn_resource(tile.terrain)
            tile.set_map_object(spawned)

            if spawned != null:
                spawned.global_position = tile.get_world_position(tile_size) + Vector2(tile_size / 2.0, tile_size / 2.0)

func initialize_tiles() -> void:
    tiles.resize(width * height)
    for y in range(height):
        for x in range(width):
            tiles[_index(x, y)] = MapTile.new(x, y, MapTile.TerrainType.PLAINS, null)

    var noise = FastNoiseLite.new()
    noise.seed = 42
    noise.frequency = 0.07
    noise.noise_type = FastNoiseLite.TYPE_PERLIN

    for y in range(height):
        for x in range(width):
            var grad_v = float(x + y) / float(width + height) * 2.0 - 1.0
            var val = (noise.get_noise_2d(x, y) * 0.3) + (grad_v * 0.7)
            var is_land = val > -0.4
            var terrain = MapTile.TerrainType.WATER

            if is_land:
                var t_v = noise.get_noise_2d(x, y)
                if t_v > 0.3:
                    terrain = MapTile.TerrainType.HILLS
                elif t_v > 0.05:
                    terrain = MapTile.TerrainType.FOREST
                elif t_v < -0.6:
                    terrain = MapTile.TerrainType.WATER
                else:
                    terrain = MapTile.TerrainType.PLAINS

            set_tile(x, y, terrain)

    _fill_water_border(3)

func _fill_water_border(border: int) -> void:
    for y in range(height):
        for x in range(width):
            if x < border or y < border or x >= width - border or y >= height - border:
                set_tile(x, y, MapTile.TerrainType.WATER)