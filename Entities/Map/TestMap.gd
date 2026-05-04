extends RefCounted
class_name TestMap

static func build_test_map(map: GameMap) -> void:
    map.width = 150
    map.height = 150
    map.initialize_tiles()

    var border := 5
    _fill_water_border(map, border)

    # Interior defaults to plains.
    # Add larger forest regions than hills so the map matches the intended ratios.
    _fill_rect(map, 20, 20, 55, 40, MapTile.TerrainType.FOREST)
    _fill_rect(map, 10, 80, 120, 12, MapTile.TerrainType.FOREST)

    # Hills are intentionally smaller and rarer.
    _fill_rect(map, 95, 30, 14, 12, MapTile.TerrainType.HILLS)
    _fill_rect(map, 60, 110, 8, 6, MapTile.TerrainType.HILLS)

static func _fill_water_border(map: GameMap, border: int) -> void:
    for y in range(map.height):
        for x in range(map.width):
            if x < border or y < border or x >= map.width - border or y >= map.height - border:
                map.set_tile(x, y, MapTile.TerrainType.WATER)

static func _fill_rect(map: GameMap, x0: int, y0: int, w: int, h: int, terrain: int) -> void:
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            map.set_tile(x, y, terrain)