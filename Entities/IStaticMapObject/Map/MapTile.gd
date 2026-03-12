extends RefCounted
class_name MapTile


enum TerrainType {
	DIRT,
	WATER,
	MOUNTAIN
}

var x: int
var y: int
var terrain: TerrainType = TerrainType.DIRT
var map_object: Variant = null
var is_occupied: bool = false

func _init(tile_x: int = 0, tile_y: int = 0, tile_terrain: TerrainType = TerrainType.GRASS, tile_object: Variant = null) -> void:
	x = tile_x
	y = tile_y
	terrain = tile_terrain
	set_map_object(tile_object)

func get_grid_position() -> Vector2i:
	return Vector2i(x, y)

func get_world_position(tile_size: int = 32) -> Vector2:
	return Vector2(x * tile_size, y * tile_size)

func set_map_object(new_object: Variant) -> void:
	map_object = new_object
	is_occupied = map_object != null

func clear_map_object() -> void:
	map_object = null
	is_occupied = false

func has_map_object() -> bool:
	return map_object != null

func is_walkable() -> bool:
	if is_occupied:
		return false

	match terrain:
		TerrainType.WATER, TerrainType.MOUNTAIN:
			return false
		_:
			return true

func take_damage(dmg: int) -> void:
	# Route damage to a static object on the tile, such as a tree, stone,
	# or later a building, if that object supports take_damage().
	if map_object == null:
		return

	if map_object.has_method("take_damage"):
		map_object.take_damage(dmg)

	# If the object was destroyed elsewhere, free the tile afterward.
	if not is_instance_valid(map_object):
		clear_map_object()

func can_place_object() -> bool:
	return (not is_occupied) and is_walkable()

func place_object(new_object: Variant) -> bool:
	if not can_place_object():
		return false

	set_map_object(new_object)
	return true
