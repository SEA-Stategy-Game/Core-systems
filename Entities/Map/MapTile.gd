extends RefCounted
class_name MapTile

enum TerrainType {
	PLAINS,
	FOREST,
	HILLS,
	WATER
}

var x: int
var y: int
var terrain: TerrainType = TerrainType.PLAINS
var map_object: Variant = null
var is_occupied: bool = false

func _init(tile_x: int = 0, tile_y: int = 0, tile_terrain: TerrainType = TerrainType.PLAINS, tile_object: Variant = null) -> void:
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
	return terrain != TerrainType.WATER

func get_movement_multiplier() -> float:
	match terrain:
		TerrainType.PLAINS:
			return 1.10
		TerrainType.FOREST:
			return 0.65
		TerrainType.HILLS:
			return 0.80
		TerrainType.WATER:
			return 0.0
		_:
			return 1.0

# Position of image in atlas
# We are missing a few images in the atlas
func get_atlas_coordinates() -> Vector2i:
	match terrain:
		TerrainType.PLAINS:
			return Vector2i(1, 1)
		TerrainType.FOREST:
			return Vector2i(2, 3)
		TerrainType.HILLS:
			return Vector2i(3, 3)
		TerrainType.WATER:
			return Vector2i(1, 3)
		_:
			return Vector2i(-1, -1)

func take_damage(dmg: int) -> void:
	if map_object == null:
		return

	if map_object.has_method("take_damage"):
		map_object.take_damage(dmg)

	if not is_instance_valid(map_object):
		clear_map_object()

func can_place_object() -> bool:
	return (not is_occupied) and is_walkable()

func place_object(new_object: Variant) -> bool:
	if not can_place_object():
		return false

	set_map_object(new_object)
	return true
