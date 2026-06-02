extends Entity

class_name Equipment

## -----------------------------------------------------------------------
## Equipment
## A stat-modifier object that can be attached to a Unit.  Multiple
## Equipment objects can stack on the same unit (the bonuses are summed).
##
## A unit's effective stats become:
##   attack_damage   = base_attack_damage + Σ attack_damage_bonus
##   attack_cooldown = base_attack_cooldown × Π attack_cooldown_multiplier
##   speed           = base_speed × (1 + Σ speed_bonus)
##   incoming damage = max(1, raw - Σ armor)
##   vision_tiles    = base + Σ vision_bonus_tiles
##
## Usage:
##   var sword = Equipment.create("Iron Sword", {"attack_damage_bonus": 5})
##   unit.equip(sword)
## -----------------------------------------------------------------------

@export var equipment_name: String = "Basic Gear"
@export var attack_damage_bonus: int = 0
@export var attack_cooldown_multiplier: float = 1.0  ## < 1.0 = faster attacks
@export var armor: int = 0                           ## flat damage reduction
@export var speed_bonus: float = 0.0                 ## fractional, applied on top of base
@export var vision_bonus_tiles: int = 0
@export var attack_range_scale: float = 1.0          ## multiplies the unit's Range Area2D shape

var equipped_to: Node = null

func _ready() -> void:
	super()
	add_to_group("equipment")
	# Equipment is data, not a world body.
	if is_in_group("units"):
		remove_from_group("units")

## Apply the bonuses on `unit` and remember the binding.
func apply_to(unit: Node) -> void:
	if unit == null:
		return
	equipped_to = unit
	if "attack_damage" in unit:
		unit.attack_damage += attack_damage_bonus
	if "attack_cooldown" in unit:
		unit.attack_cooldown *= attack_cooldown_multiplier
	if "speed" in unit:
		unit.speed = int(round(unit.speed * (1.0 + speed_bonus)))
	if "vision_range_tiles" in unit:
		unit.vision_range_tiles += vision_bonus_tiles
	if attack_range_scale != 1.0:
		var range_shape = unit.get_node_or_null("Range/CollisionShape2D")
		if range_shape:
			range_shape.scale *= attack_range_scale
	print("[EQUIP] '", equipment_name, "' applied to ",
		unit.entity_id if "entity_id" in unit else unit.get_instance_id(),
		"  (+", attack_damage_bonus, " dmg, x", attack_cooldown_multiplier,
		" cd, +", armor, " armor, +", speed_bonus, " speed, +", vision_bonus_tiles, " vis)")

## Reverse `apply_to`.  Idempotent if the unit is no longer valid.
func remove_from(unit: Node) -> void:
	if unit == null or not is_instance_valid(unit):
		equipped_to = null
		return
	if "attack_damage" in unit:
		unit.attack_damage -= attack_damage_bonus
	if "attack_cooldown" in unit and attack_cooldown_multiplier != 0.0:
		unit.attack_cooldown /= attack_cooldown_multiplier
	if "speed" in unit and (1.0 + speed_bonus) != 0.0:
		unit.speed = int(round(unit.speed / (1.0 + speed_bonus)))
	if "vision_range_tiles" in unit:
		unit.vision_range_tiles -= vision_bonus_tiles
	if attack_range_scale != 1.0 and attack_range_scale != 0.0:
		var range_shape = unit.get_node_or_null("Range/CollisionShape2D")
		if range_shape:
			range_shape.scale /= attack_range_scale
	equipped_to = null
	print("[EQUIP] '", equipment_name, "' removed from ",
		unit.entity_id if "entity_id" in unit else unit.get_instance_id())

# -----------------------------------------------------------------
# Factory
# -----------------------------------------------------------------
## Build an Equipment from a dictionary of stat overrides.
## Example: Equipment.create("Iron Sword", {"attack_damage_bonus": 5, "armor": 2})
static func create(name: String, stats: Dictionary = {}) -> Equipment:
	var eq = Equipment.new()
	eq.equipment_name = name
	eq.attack_damage_bonus = int(stats.get("attack_damage_bonus", 0))
	eq.attack_cooldown_multiplier = float(stats.get("attack_cooldown_multiplier", 1.0))
	eq.armor = int(stats.get("armor", 0))
	eq.speed_bonus = float(stats.get("speed_bonus", 0.0))
	eq.vision_bonus_tiles = int(stats.get("vision_bonus_tiles", 0))
	eq.attack_range_scale = float(stats.get("attack_range_scale", 1.0))
	return eq
