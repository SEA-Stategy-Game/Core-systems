extends RefCounted
class_name MapGenerator

@export var water_border: int = 5
@export var forest_threshold: float = 0.70
@export var hills_threshold: float = 0.90

func generate(map: GameMap, seed: int = -1) -> void:
    var rng = RandomNumberGenerator.new()
    if seed < 0:
        rng.randomize()
    else:
        rng.seed = seed

    var noise = FastNoiseLite.new()
    noise.seed = rng.randi()
    noise.frequency = 0.06

    for y in range(map.height):
        for x in range(map.width):
            if _is_border(x, y, map.width, map.height, water_border):
                map.set_tile(x, y, MapTile.TerrainType.WATER)
                continue

            var n = (noise.get_noise_2d(x, y) + 1.0) * 0.5
            map.set_tile(x, y, _classify(n))

func _is_border(x: int, y: int, w: int, h: int, b: int) -> bool:
    return x < b or y < b or x >= (w - b) or y >= (h - b)

func _classify(n: float) -> int:
    if n > hills_threshold:
        return MapTile.TerrainType.HILLS
    if n > forest_threshold:
        return MapTile.TerrainType.FOREST
    return MapTile.TerrainType.PLAINS