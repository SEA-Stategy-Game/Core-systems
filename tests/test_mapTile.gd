extends GutTest

const DEFAULT_TILE_SIZE := 32

class DamageReceiver extends RefCounted:
	var damage_total: int = 0

	func take_damage(dmg: int) -> void:
		damage_total += dmg

class NoDamageMethod extends RefCounted:
	var marker: bool = true

class SelfDestructingMapObject extends Node:
	var received_damage: int = 0

	func take_damage(dmg: int) -> void:
		received_damage += dmg
		queue_free()

var tile: MapTile

func before_each() -> void:
	tile = MapTile.new()

func after_each() -> void:
	tile = null

# --------------------
# initialization tests
# --------------------
func test_init_sets_default_values() -> void:
	var default_tile := MapTile.new()
	assert_eq(default_tile.x, 0)
	assert_eq(default_tile.y, 0)
	assert_eq(default_tile.terrain, MapTile.TerrainType.DIRT)
	assert_null(default_tile.map_object)
	assert_false(default_tile.is_occupied)

func test_init_sets_custom_values() -> void:
	var obj := DamageReceiver.new()
	var custom_tile := MapTile.new(3, 7, MapTile.TerrainType.WATER, obj)
	assert_eq(custom_tile.x, 3)
	assert_eq(custom_tile.y, 7)
	assert_eq(custom_tile.terrain, MapTile.TerrainType.WATER)
	assert_eq(custom_tile.map_object, obj)
	assert_true(custom_tile.is_occupied)

# ----------------
# position helpers
# ----------------
func test_get_grid_position_returns_expected_vector2i() -> void:
	tile.x = 5
	tile.y = 9
	assert_eq(tile.get_grid_position(), Vector2i(5, 9))

func test_get_world_position_uses_default_tile_size() -> void:
	tile.x = 2
	tile.y = 4
	assert_eq(tile.get_world_position(), Vector2(64, 128))

func test_get_world_position_uses_custom_tile_size() -> void:
	tile.x = 3
	tile.y = 1
	assert_eq(tile.get_world_position(16), Vector2(48, 16))

# --------------------
# map object lifecycle
# --------------------
func test_set_map_object_sets_occupied_true() -> void:
	var obj := DamageReceiver.new()
	tile.set_map_object(obj)
	assert_true(tile.is_occupied)
	assert_true(tile.has_map_object())
	assert_eq(tile.map_object, obj)

func test_clear_map_object_resets_state() -> void:
	tile.set_map_object(DamageReceiver.new())
	tile.clear_map_object()
	assert_false(tile.is_occupied)
	assert_false(tile.has_map_object())
	assert_null(tile.map_object)

# -------------------
# walkability / place
# -------------------
func test_is_walkable_false_when_occupied() -> void:
	tile.terrain = MapTile.TerrainType.DIRT
	tile.set_map_object(DamageReceiver.new())
	assert_false(tile.is_walkable())

func test_is_walkable_false_for_water() -> void:
	tile.terrain = MapTile.TerrainType.WATER
	tile.clear_map_object()
	assert_false(tile.is_walkable())

func test_is_walkable_false_for_mountain() -> void:
	tile.terrain = MapTile.TerrainType.MOUNTAIN
	tile.clear_map_object()
	assert_false(tile.is_walkable())

func test_is_walkable_true_for_unoccupied_dirt() -> void:
	tile.terrain = MapTile.TerrainType.DIRT
	tile.clear_map_object()
	assert_true(tile.is_walkable())

func test_can_place_object_true_when_unoccupied_and_walkable() -> void:
	tile.terrain = MapTile.TerrainType.DIRT
	tile.clear_map_object()
	assert_true(tile.can_place_object())

func test_place_object_succeeds_when_placeable() -> void:
	var obj := DamageReceiver.new()
	var placed := tile.place_object(obj)
	assert_true(placed)
	assert_true(tile.is_occupied)
	assert_eq(tile.map_object, obj)

func test_place_object_fails_when_already_occupied() -> void:
	tile.place_object(DamageReceiver.new())
	var placed := tile.place_object(DamageReceiver.new())
	assert_false(placed)

func test_place_object_fails_on_non_walkable_terrain() -> void:
	tile.terrain = MapTile.TerrainType.WATER
	tile.clear_map_object()
	var placed := tile.place_object(DamageReceiver.new())
	assert_false(placed)
	assert_false(tile.is_occupied)

# -------------------
# damage interaction
# -------------------
func test_take_damage_forwards_to_map_object_with_take_damage_method() -> void:
	var obj := DamageReceiver.new()
	tile.set_map_object(obj)

	tile.take_damage(12)
	assert_eq(obj.damage_total, 12)
	assert_true(tile.has_map_object())

func test_take_damage_does_nothing_when_no_map_object() -> void:
	tile.clear_map_object()
	tile.take_damage(5)
	assert_false(tile.has_map_object())
	assert_false(tile.is_occupied)

func test_take_damage_does_not_call_objects_without_take_damage_method() -> void:
	var obj := NoDamageMethod.new()
	tile.set_map_object(obj)
	tile.take_damage(99)
	assert_true(tile.has_map_object())
	assert_true(tile.is_occupied)
