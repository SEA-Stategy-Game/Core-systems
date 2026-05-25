class_name TestMap extends GameMap

func initialize_tiles() -> void:
	width = 32
	height = 32
	super.initialize_tiles()
	
	# Interior defaults to plains.
	_fill_rect(0, 0, width/2, height/2, MapTile.TerrainType.FOREST)
	_fill_rect(width/2, 0, width/2, height/2, MapTile.TerrainType.HILLS)
	_fill_rect(0, height/2, width/2, height/2, MapTile.TerrainType.WATER)
	_fill_rect(width/2, height/2, width/2, height/2, MapTile.TerrainType.PLAINS)
	
	var border := 5
	_fill_water_border(border)

func _fill_water_border(border: int) -> void:
	for y in range(height):
		for x in range(width):
			if x < border or y < border or x >= width - border or y >= height - border:
				set_tile(x, y, MapTile.TerrainType.WATER)

func _fill_rect(x0: int, y0: int, w: int, h: int, terrain: int) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			set_tile(x, y, terrain)
