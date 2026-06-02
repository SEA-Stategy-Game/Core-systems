extends GutTest

## -----------------------------------------------------------------------
## Tests for FogOfWar.gd
## -----------------------------------------------------------------------
## The FogOfWar node tracks three states per (player, tile):
##   UNKNOWN  -> never seen
##   EXPLORED -> seen before, not currently visible (this is the persistent
##               memory that distinguishes "fog" from "shroud")
##   VISIBLE  -> currently observed by a unit/building owned by that player
##
## The acceptance criterion from the GitHub issue is:
##   "Add FoW to the game so that the player is only able to see
##    previously explored areas."
## -> i.e. EXPLORED tiles must remain marked as explored even after the
##    vision source moves away. These tests exercise that behaviour.
## -----------------------------------------------------------------------

const FogOfWarScript = preload("res://Entities/Map/FogOfWar.gd")

# Lightweight Node2D stand-in for a unit/building with a player_id and
# optional per-instance vision range. We avoid the real Unit scene to keep
# the tests pure.
class FakeVisionSource extends Node2D:
	var player_id: int = 0
	var current_health: int = 100
	var vision_range_tiles: int = 4

	func get_player_id() -> int:
		return player_id

var fow: FogOfWar

func _make_source(player_id: int, pos: Vector2, radius: int = 4, hp: int = 100) -> FakeVisionSource:
	var src := FakeVisionSource.new()
	src.player_id = player_id
	src.vision_range_tiles = radius
	src.current_health = hp
	src.global_position = pos
	src.add_to_group("units")
	add_child_autofree(src)
	return src

func before_each() -> void:
	fow = FogOfWarScript.new()
	fow.tile_size = 32
	fow.map_width = 64
	fow.map_height = 64
	fow.default_unit_vision_tiles = 4
	fow.default_building_vision_tiles = 6
	# Do not auto-rebuild on tick during tests.
	fow.update_on_tick = false
	add_child_autofree(fow)

func after_each() -> void:
	fow = null

# -----------------------------------------------------------------
# coordinate / helper tests
# -----------------------------------------------------------------
func test_world_to_tile_floors_negative_coordinates() -> void:
	assert_eq(fow.world_to_tile(Vector2(0, 0)), Vector2i(0, 0))
	assert_eq(fow.world_to_tile(Vector2(31, 31)), Vector2i(0, 0))
	assert_eq(fow.world_to_tile(Vector2(32, 32)), Vector2i(1, 1))
	# Negative coordinates must floor toward -infinity, not truncate.
	assert_eq(fow.world_to_tile(Vector2(-1, -1)), Vector2i(-1, -1))
	assert_eq(fow.world_to_tile(Vector2(-32, -32)), Vector2i(-1, -1))

func test_tile_to_world_center_returns_tile_midpoint() -> void:
	assert_eq(fow.tile_to_world_center(Vector2i(0, 0)), Vector2(16, 16))
	assert_eq(fow.tile_to_world_center(Vector2i(2, 3)), Vector2(80, 112))

func test_initial_state_is_unknown_for_unseen_tiles() -> void:
	assert_eq(fow.get_fog_state(0, Vector2i(5, 5)), FogOfWar.FogState.UNKNOWN)
	assert_false(fow.is_tile_visible(0, Vector2i(5, 5)))
	assert_false(fow.is_tile_explored(0, Vector2i(5, 5)))

# -----------------------------------------------------------------
# visibility math
# -----------------------------------------------------------------
func test_rebuild_marks_tiles_inside_circular_radius_visible() -> void:
	# A source at tile (5,5) with radius 2 should make exactly the tiles
	# within Euclidean distance <=2 visible.
	var _src = _make_source(0, Vector2(5.5 * 32, 5.5 * 32), 2)
	fow.rebuild_player(0)

	# Center always visible.
	assert_true(fow.is_tile_visible(0, Vector2i(5, 5)))
	# Cardinal neighbours within 2 tiles
	assert_true(fow.is_tile_visible(0, Vector2i(7, 5)))
	assert_true(fow.is_tile_visible(0, Vector2i(5, 3)))
	# Outside radius
	assert_false(fow.is_tile_visible(0, Vector2i(8, 5)))
	# Diagonal at distance ~2.83 must NOT be visible with radius 2.
	assert_false(fow.is_tile_visible(0, Vector2i(7, 7)))

func test_visible_tile_is_also_marked_explored() -> void:
	_make_source(0, Vector2(5.5 * 32, 5.5 * 32), 2)
	fow.rebuild_player(0)
	assert_true(fow.is_tile_explored(0, Vector2i(5, 5)))
	assert_eq(fow.get_fog_state(0, Vector2i(5, 5)), FogOfWar.FogState.VISIBLE)

# -----------------------------------------------------------------
# The core requirement: EXPLORED tiles must persist
# -----------------------------------------------------------------
func test_explored_persists_after_source_moves_away() -> void:
	var src := _make_source(0, Vector2(5.5 * 32, 5.5 * 32), 2)
	fow.rebuild_player(0)
	assert_true(fow.is_tile_visible(0, Vector2i(5, 5)))

	# Move source very far so the original tile is no longer visible.
	src.global_position = Vector2(40.5 * 32, 40.5 * 32)
	fow.rebuild_player(0)

	# The old tile should NOT be visible any more,
	# but must remain EXPLORED.
	assert_false(fow.is_tile_visible(0, Vector2i(5, 5)))
	assert_true(fow.is_tile_explored(0, Vector2i(5, 5)))
	assert_eq(fow.get_fog_state(0, Vector2i(5, 5)), FogOfWar.FogState.EXPLORED)

func test_explored_persists_after_source_dies() -> void:
	var src := _make_source(0, Vector2(2.5 * 32, 2.5 * 32), 2)
	fow.rebuild_player(0)
	assert_true(fow.is_tile_visible(0, Vector2i(2, 2)))

	src.current_health = 0  # treated as dead
	fow.rebuild_player(0)

	assert_false(fow.is_tile_visible(0, Vector2i(2, 2)))
	assert_true(fow.is_tile_explored(0, Vector2i(2, 2)))

# -----------------------------------------------------------------
# multi-player isolation -- each player has independent fog state
# -----------------------------------------------------------------
func test_visibility_is_isolated_per_player() -> void:
	_make_source(0, Vector2(2.5 * 32, 2.5 * 32), 2)
	_make_source(1, Vector2(40.5 * 32, 40.5 * 32), 2)
	fow.rebuild_all_players()

	# Player 0 sees their own area but not player 1's.
	assert_true(fow.is_tile_visible(0, Vector2i(2, 2)))
	assert_false(fow.is_tile_visible(0, Vector2i(40, 40)))

	# Player 1 sees their own area but not player 0's.
	assert_true(fow.is_tile_visible(1, Vector2i(40, 40)))
	assert_false(fow.is_tile_visible(1, Vector2i(2, 2)))

func test_explored_is_isolated_per_player() -> void:
	var src0 := _make_source(0, Vector2(2.5 * 32, 2.5 * 32), 2)
	fow.rebuild_player(0)

	# Player 1 has never been near tile (2,2).
	assert_false(fow.is_tile_explored(1, Vector2i(2, 2)))
	# But player 0 has it explored.
	assert_true(fow.is_tile_explored(0, Vector2i(2, 2)))
	src0.queue_free()  # avoid leaking into other tests

# -----------------------------------------------------------------
# helper: can_player_sense_node
# -----------------------------------------------------------------
func test_can_player_sense_node_returns_true_for_node_in_sight() -> void:
	_make_source(0, Vector2(5.5 * 32, 5.5 * 32), 4)
	# A "target" node placed inside the vision circle.
	var target := Node2D.new()
	target.global_position = Vector2(5.5 * 32, 5.5 * 32)
	add_child_autofree(target)
	fow.rebuild_player(0)
	assert_true(fow.can_player_sense_node(0, target))

func test_can_player_sense_node_returns_false_for_node_out_of_sight() -> void:
	_make_source(0, Vector2(5.5 * 32, 5.5 * 32), 2)
	var target := Node2D.new()
	target.global_position = Vector2(30.5 * 32, 30.5 * 32)
	add_child_autofree(target)
	fow.rebuild_player(0)
	assert_false(fow.can_player_sense_node(0, target))

# -----------------------------------------------------------------
# is_world_position_* helpers
# -----------------------------------------------------------------
func test_is_world_position_visible_matches_tile_lookup() -> void:
	_make_source(0, Vector2(5.5 * 32, 5.5 * 32), 2)
	fow.rebuild_player(0)
	assert_true(fow.is_world_position_visible(0, Vector2(5.5 * 32, 5.5 * 32)))
	assert_false(fow.is_world_position_visible(0, Vector2(40 * 32, 40 * 32)))

func test_is_world_position_explored_persists_for_old_locations() -> void:
	var src := _make_source(0, Vector2(5.5 * 32, 5.5 * 32), 2)
	fow.rebuild_player(0)
	src.global_position = Vector2(40.5 * 32, 40.5 * 32)
	fow.rebuild_player(0)
	assert_true(fow.is_world_position_explored(0, Vector2(5.5 * 32, 5.5 * 32)))
	assert_false(fow.is_world_position_visible(0, Vector2(5.5 * 32, 5.5 * 32)))

# -----------------------------------------------------------------
# signal emission
# -----------------------------------------------------------------
func test_player_fog_rebuilt_signal_fires_on_rebuild() -> void:
	watch_signals(fow)
	_make_source(0, Vector2(0, 0), 1)
	fow.rebuild_player(0)
	assert_signal_emitted_with_parameters(fow, "player_fog_rebuilt", [0])

func test_tile_visibility_changed_emits_unknown_to_visible() -> void:
	watch_signals(fow)
	_make_source(0, Vector2(5.5 * 32, 5.5 * 32), 1)
	fow.rebuild_player(0)
	# At least one tile should have transitioned UNKNOWN -> VISIBLE.
	# We don't pin to a specific tile because radius math hits several
	# tiles, but the signal must have fired.
	assert_true(get_signal_emit_count(fow, "tile_visibility_changed") > 0)

func test_tile_visibility_changed_emits_visible_to_explored() -> void:
	# First reveal then move source away. Expect VISIBLE -> EXPLORED transitions.
	var src := _make_source(0, Vector2(5.5 * 32, 5.5 * 32), 1)
	fow.rebuild_player(0)
	watch_signals(fow)
	src.global_position = Vector2(40.5 * 32, 40.5 * 32)
	fow.rebuild_player(0)
	# Inspect the emit log for any VISIBLE -> EXPLORED transition.
	var found_v_to_e := false
	var emit_count: int = get_signal_emit_count(fow, "tile_visibility_changed")
	for i in range(emit_count):
		var params: Array = get_signal_parameters(fow, "tile_visibility_changed", i)
		var old_state: int = int(params[2])
		var new_state: int = int(params[3])
		if old_state == FogOfWar.FogState.VISIBLE and new_state == FogOfWar.FogState.EXPLORED:
			found_v_to_e = true
			break
	assert_true(found_v_to_e, "expected at least one VISIBLE->EXPLORED transition")

# -----------------------------------------------------------------
# clear functions
# -----------------------------------------------------------------
func test_clear_player_wipes_visible_and_explored() -> void:
	_make_source(0, Vector2(2.5 * 32, 2.5 * 32), 2)
	fow.rebuild_player(0)
	assert_true(fow.is_tile_explored(0, Vector2i(2, 2)))
	fow.clear_player(0)
	assert_false(fow.is_tile_visible(0, Vector2i(2, 2)))
	assert_false(fow.is_tile_explored(0, Vector2i(2, 2)))

func test_clear_all_wipes_all_players() -> void:
	_make_source(0, Vector2(2.5 * 32, 2.5 * 32), 2)
	_make_source(1, Vector2(10.5 * 32, 10.5 * 32), 2)
	fow.rebuild_all_players()
	fow.clear_all()
	assert_false(fow.is_tile_explored(0, Vector2i(2, 2)))
	assert_false(fow.is_tile_explored(1, Vector2i(10, 10)))

# -----------------------------------------------------------------
# map bounds
# -----------------------------------------------------------------
func test_tiles_outside_map_bounds_are_never_marked_visible() -> void:
	# Place a source right at the corner with a radius that would extend
	# off-map. The off-map tiles must not be reported visible.
	_make_source(0, Vector2(0.5 * 32, 0.5 * 32), 4)
	fow.rebuild_player(0)
	assert_true(fow.is_tile_visible(0, Vector2i(0, 0)))
	assert_false(fow.is_tile_visible(0, Vector2i(-1, 0)))
	assert_false(fow.is_tile_visible(0, Vector2i(0, -1)))
	assert_false(fow.is_tile_visible(0, Vector2i(fow.map_width, 0)))
