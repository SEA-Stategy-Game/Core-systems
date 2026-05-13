extends GutTest

## -----------------------------------------------------------------------
## Unit tests for Game.gd (autoload)
## -----------------------------------------------------------------------
## Per-player stockpiles, spending, spawn affordability and the
## army-wide upgrade ledger.  The Game autoload is shared state, so every
## test resets it before and after.
## -----------------------------------------------------------------------

func before_each() -> void:
	_reset_game_state()

func after_each() -> void:
	_reset_game_state()

func _reset_game_state() -> void:
	Game.player_resources.clear()
	Game.player_upgrades.clear()
	Game.Wood = 0
	Game.Stone = 0
	Game.game_over = false

# ------------------
# stockpile basics
# ------------------
func test_new_player_starts_with_empty_stockpile() -> void:
	assert_eq(Game.get_player_wood(0), 0)
	assert_eq(Game.get_player_stone(0), 0)

func test_add_resource_accumulates() -> void:
	Game.add_resource(0, "wood", 2)
	Game.add_resource(0, "wood", 3)

	assert_eq(Game.get_player_wood(0), 5)

func test_stockpiles_are_tracked_per_player() -> void:
	Game.add_resource(0, "wood", 4)
	Game.add_resource(1, "wood", 9)

	assert_eq(Game.get_player_wood(0), 4)
	assert_eq(Game.get_player_wood(1), 9)

func test_legacy_globals_mirror_player_zero_only() -> void:
	Game.add_resource(1, "wood", 9)
	assert_eq(Game.Wood, 0)

	Game.add_resource(0, "wood", 4)
	Game.add_resource(0, "stone", 2)

	assert_eq(Game.Wood, 4)
	assert_eq(Game.Stone, 2)

# ------------------
# spending
# ------------------
func test_spend_resources_deducts_both_kinds() -> void:
	Game.add_resource(0, "wood", 10)
	Game.add_resource(0, "stone", 6)

	var ok := Game.spend_resources(0, 7, 5)

	assert_true(ok)
	assert_eq(Game.get_player_wood(0), 3)
	assert_eq(Game.get_player_stone(0), 1)

func test_spend_resources_fails_on_insufficient_wood_without_deducting() -> void:
	Game.add_resource(0, "wood", 3)
	Game.add_resource(0, "stone", 10)

	var ok := Game.spend_resources(0, 5, 1)

	assert_false(ok)
	assert_eq(Game.get_player_wood(0), 3)
	assert_eq(Game.get_player_stone(0), 10)

func test_spend_resources_fails_on_insufficient_stone_without_deducting() -> void:
	Game.add_resource(0, "wood", 10)

	var ok := Game.spend_resources(0, 1, 1)

	assert_false(ok)
	assert_eq(Game.get_player_wood(0), 10)

# ------------------
# spawn affordability
# ------------------
func test_can_afford_spawn_exactly_at_cost() -> void:
	Game.add_resource(0, "wood", Game.SPAWN_COST_WOOD)
	Game.add_resource(0, "stone", Game.SPAWN_COST_STONE)

	assert_true(Game.can_afford_spawn(0))

func test_cannot_afford_spawn_one_wood_short() -> void:
	Game.add_resource(0, "wood", Game.SPAWN_COST_WOOD - 1)
	Game.add_resource(0, "stone", Game.SPAWN_COST_STONE)

	assert_false(Game.can_afford_spawn(0))

# ------------------
# upgrade ledger
# ------------------
func test_upgrade_level_defaults_to_zero() -> void:
	assert_eq(Game.get_upgrade_level(0, "sword"), 0)
	assert_eq(Game.get_upgrade_level(0, "bow"), 0)

func test_purchase_sword_spends_cost_and_returns_level_one() -> void:
	Game.add_resource(0, "wood", int(Game.SWORD_COST["wood"]))
	Game.add_resource(0, "stone", int(Game.SWORD_COST["stone"]))

	var level := Game.purchase_upgrade(0, "sword")

	assert_eq(level, 1)
	assert_eq(Game.get_upgrade_level(0, "sword"), 1)
	assert_eq(Game.get_player_wood(0), 0)

func test_purchase_upgrade_levels_stack() -> void:
	Game.add_resource(0, "wood", int(Game.SWORD_COST["wood"]) * 2)

	Game.purchase_upgrade(0, "sword")
	var level := Game.purchase_upgrade(0, "sword")

	assert_eq(level, 2)

func test_purchase_upgrade_fails_without_resources() -> void:
	var level := Game.purchase_upgrade(0, "sword")

	assert_eq(level, -1)
	assert_eq(Game.get_upgrade_level(0, "sword"), 0)

func test_purchase_unknown_upgrade_kind_fails() -> void:
	Game.add_resource(0, "wood", 100)
	Game.add_resource(0, "stone", 100)

	assert_eq(Game.purchase_upgrade(0, "shield"), -1)

# ------------------
# upgrade equipment factory
# ------------------
func test_make_sword_equipment_scales_damage_with_level() -> void:
	var eq := autofree(Game.make_upgrade_equipment("sword", 2))

	assert_not_null(eq)
	assert_eq(eq.equipment_name, "Sword L2")
	assert_eq(eq.attack_damage_bonus, Game.SWORD_DAMAGE_PER_LEVEL * 2)

func test_make_bow_equipment_grants_damage_vision_and_range() -> void:
	var eq := autofree(Game.make_upgrade_equipment("bow", 1))

	assert_not_null(eq)
	assert_eq(eq.attack_damage_bonus, Game.BOW_DAMAGE_PER_LEVEL)
	assert_eq(eq.vision_bonus_tiles, Game.BOW_VISION_PER_LEVEL)
	assert_almost_eq(eq.attack_range_scale, 1.0 + Game.BOW_RANGE_SCALE_PER_LEVEL, 0.0001)

func test_make_upgrade_equipment_returns_null_for_level_zero() -> void:
	assert_null(Game.make_upgrade_equipment("sword", 0))
