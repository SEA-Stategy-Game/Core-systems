class_name TestMap extends GameMap

func initialize_tiles() -> void:
	width = 32 
	height = 32
	super.initialize_tiles()
	
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