class_name MapGenerator extends GameMap

@export var water_border: int = 5
@export var plains_threshold: float = 0.50
@export var forest_threshold: float = 0.70
@export var hills_threshold: float = 0.90
var rng = RandomNumberGenerator.new()

func initialize_tiles():
	generate();

func _init(seed: int = -1) -> void:
	if seed < 0:
		rng.randomize()
	else:
		rng.seed = seed
	ResourceSpawner.set_rng(rng)
	super()

func generate() -> void:
	super.initialize_tiles()

	var noise = FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.06

	for y in range(height):
		for x in range(width):
			if _is_border(x, y, width, height, water_border):
				set_tile(x, y, MapTile.TerrainType.WATER)
				continue
			var n = (noise.get_noise_2d(x, y) + 1.0) * 0.7
			set_tile(x, y, _classify(n))

func _is_border(x: int, y: int, w: int, h: int, b: int) -> bool:
	return x < b or y < b or x >= (w - b) or y >= (h - b)

func _classify(n: float) -> int:
	if n > hills_threshold:
		return MapTile.TerrainType.HILLS
	if n > forest_threshold:
		return MapTile.TerrainType.FOREST
	if n > plains_threshold:
		return MapTile.TerrainType.PLAINS
	return MapTile.TerrainType.WATER
