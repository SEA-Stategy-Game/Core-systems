extends GutTest

## -----------------------------------------------------------------------
## Unit tests for equipment.gd
## -----------------------------------------------------------------------
## Equipment is a stat-modifier attached to units.  Tests cover the
## factory, symmetric apply/remove, stacking, and the armor rule
## (incoming damage is reduced but at least 1 always lands).
## -----------------------------------------------------------------------

const UNIT_SCENE = preload("res://Entities/Units/character_body_2dtets.tscn")

var unit: Unit

func before_each() -> void:
	unit = UNIT_SCENE.instantiate() as Unit
	add_child_autofree(unit)

func after_each() -> void:
	unit = null

func _make_equipment(stats: Dictionary) -> Equipment:
	return autofree(Equipment.create("Test Gear", stats))

# ----------
# factory
# ----------
func test_create_populates_stats_from_dictionary() -> void:
	var eq := _make_equipment({
		"attack_damage_bonus": 5,
		"armor": 2,
		"attack_cooldown_multiplier": 0.5,
		"speed_bonus": 0.25,
		"vision_bonus_tiles": 3,
	})

	assert_eq(eq.equipment_name, "Test Gear")
	assert_eq(eq.attack_damage_bonus, 5)
	assert_eq(eq.armor, 2)
	assert_almost_eq(eq.attack_cooldown_multiplier, 0.5, 0.0001)
	assert_almost_eq(eq.speed_bonus, 0.25, 0.0001)
	assert_eq(eq.vision_bonus_tiles, 3)

func test_create_defaults_to_neutral_stats() -> void:
	var eq := _make_equipment({})

	assert_eq(eq.attack_damage_bonus, 0)
	assert_eq(eq.armor, 0)
	assert_almost_eq(eq.attack_cooldown_multiplier, 1.0, 0.0001)

# ----------------
# apply / remove
# ----------------
func test_equip_adds_attack_damage_bonus() -> void:
	var base_damage := unit.attack_damage
	var eq := _make_equipment({"attack_damage_bonus": 5})

	unit.equip(eq)

	assert_eq(unit.attack_damage, base_damage + 5)

func test_unequip_restores_base_attack_damage() -> void:
	var base_damage := unit.attack_damage
	var eq := _make_equipment({"attack_damage_bonus": 5})
	unit.equip(eq)

	unit.unequip(eq)

	assert_eq(unit.attack_damage, base_damage)
	assert_eq(unit.equipped.size(), 0)

func test_cooldown_multiplier_applies_and_removes_symmetrically() -> void:
	var base_cooldown := unit.attack_cooldown
	var eq := _make_equipment({"attack_cooldown_multiplier": 0.5})

	unit.equip(eq)
	assert_almost_eq(unit.attack_cooldown, base_cooldown * 0.5, 0.0001)

	unit.unequip(eq)
	assert_almost_eq(unit.attack_cooldown, base_cooldown, 0.0001)

func test_vision_bonus_applies_and_removes() -> void:
	var base_vision := unit.vision_range_tiles
	var eq := _make_equipment({"vision_bonus_tiles": 2})

	unit.equip(eq)
	assert_eq(unit.vision_range_tiles, base_vision + 2)

	unit.unequip(eq)
	assert_eq(unit.vision_range_tiles, base_vision)

func test_bonuses_from_multiple_items_stack() -> void:
	var base_damage := unit.attack_damage
	unit.equip(_make_equipment({"attack_damage_bonus": 5}))
	unit.equip(_make_equipment({"attack_damage_bonus": 3}))

	assert_eq(unit.attack_damage, base_damage + 8)
	assert_eq(unit.equipped.size(), 2)

func test_equip_null_is_rejected() -> void:
	assert_false(unit.equip(null))

func test_unequip_unknown_item_is_rejected() -> void:
	var never_equipped := _make_equipment({})

	assert_false(unit.unequip(never_equipped))

# ----------
# armor rule
# ----------
func test_armor_reduces_incoming_damage() -> void:
	unit.equip(_make_equipment({"armor": 4}))

	unit.take_damage(10)

	assert_eq(unit.current_health, unit.max_health - 6)

func test_at_least_one_damage_always_lands() -> void:
	unit.equip(_make_equipment({"armor": 50}))

	unit.take_damage(10)

	assert_eq(unit.current_health, unit.max_health - 1)

func test_get_total_armor_sums_equipped_items() -> void:
	unit.equip(_make_equipment({"armor": 2}))
	unit.equip(_make_equipment({"armor": 3}))

	assert_eq(unit.get_total_armor(), 5)
