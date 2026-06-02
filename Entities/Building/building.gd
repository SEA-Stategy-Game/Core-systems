extends Entity

class_name Building

## -----------------------------------------------------------------------
## Base class for all buildings.  Inherits IDamageable from Entity.
## The player_id is inherited from Entity and identifies the owner.
##
## Buildings support a per-instance UPGRADE LEVEL (0..MAX_UPGRADE_LEVEL).
## Each upgrade costs wood + stone from the owner's stockpile and applies
## a bonus to max_health, vision range, and (for spawners) spawn rate.
## -----------------------------------------------------------------------

## Building-specific state
@export var building_name: String = "Building"

## Upgrade system
@export var upgrade_level: int = 0
const MAX_UPGRADE_LEVEL: int = 3

## Cost per upgrade level (index 1..3 used; index 0 unused).
const UPGRADE_WOOD_COST: Array[int]  = [0, 15, 25, 40]
const UPGRADE_STONE_COST: Array[int] = [0, 10, 20, 35]

## Bonuses applied per level.
const HP_BONUS_PER_LEVEL: float = 0.25       ## +25% max HP per level
const VISION_BONUS_PER_LEVEL: int = 1        ## +1 vision tile per level

@export var vision_range_tiles: int = 8      ## Read by FogOfWar

func _ready() -> void:
	super()
	add_to_group("buildings")
	# Buildings should not be in the "units" group -- remove if Entity added it
	if is_in_group("units"):
		remove_from_group("units")

# -----------------------------------------------------------------
# Upgrade API
# -----------------------------------------------------------------

func can_upgrade() -> bool:
	return upgrade_level < MAX_UPGRADE_LEVEL

func get_upgrade_cost() -> Dictionary:
	if not can_upgrade():
		return {"wood": -1, "stone": -1}
	var next = upgrade_level + 1
	return {"wood": UPGRADE_WOOD_COST[next], "stone": UPGRADE_STONE_COST[next]}

## Attempt to upgrade this building one level.  Spends the resources from
## the owning player's stockpile.  Returns true on success.
func upgrade() -> bool:
	if not can_upgrade():
		print("[BUILDING] '", building_name, "' already at max level.")
		return false
	var cost = get_upgrade_cost()
	if not Game.spend_resources(player_id, int(cost["wood"]), int(cost["stone"])):
		print("[BUILDING] '", building_name, "' upgrade denied -- insufficient resources (need ",
			cost["wood"], "w + ", cost["stone"], "s).")
		return false
	upgrade_level += 1
	_apply_upgrade_bonuses()
	print("[BUILDING] '", building_name, "' (player ", player_id, ") upgraded to level ", upgrade_level,
		" -- new max HP ", max_health, ", vision ", vision_range_tiles)
	return true

## Recomputes derived stats based on `upgrade_level` and applies the delta
## to current_health so a heal accompanies each level.
func _apply_upgrade_bonuses() -> void:
	# Recompute max_health from the original base (max_health from .tscn export)
	# by applying the cumulative bonus.
	var base_max = max_health
	var multiplier = 1.0 + HP_BONUS_PER_LEVEL  # this level's +25%
	var new_max = int(base_max * multiplier)
	var hp_delta = new_max - base_max
	max_health = new_max
	current_health = min(current_health + hp_delta, max_health)

	vision_range_tiles += VISION_BONUS_PER_LEVEL
