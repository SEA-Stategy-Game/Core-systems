extends StaticBody2D

## -----------------------------------------------------------------------
## Barracks -- player home base.  Units return here after composite tasks.
## Implements IDamageable contract for universal combat targeting.
## Click to open the spawn-unit pop-up (charges 10 wood + 5 stone).
## -----------------------------------------------------------------------

@export var entity_id: int = -1
@export var player_id: int = 0
@export var max_health: int = 500
@export var vision_range_tiles: int = 8
var current_health: int

## Upgrade system (mirrors Building.gd so AI / debug tooling can drive it).
@export var upgrade_level: int = 0
const MAX_UPGRADE_LEVEL: int = 3
const UPGRADE_WOOD_COST: Array[int]  = [0, 15, 25, 40]
const UPGRADE_STONE_COST: Array[int] = [0, 10, 20, 35]
const HP_BONUS_PER_LEVEL: float = 0.25
const VISION_BONUS_PER_LEVEL: int = 1
const SPAWN_COST_REDUCTION_PER_LEVEL: int = 1   ## -1 wood / -1 stone per level

var mouseEntered = false
@onready var select = get_node("Selected")
var Selected = false

func _ready() -> void:
	current_health = max_health
	add_to_group("buildings")
	add_to_group("barracks")

func _process(delta: float) -> void:
	select.visible = Selected

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("LeftClick"):
		if mouseEntered == true:
			Selected = !Selected
			if Selected == true:
				Game.spawnUnit(global_position, player_id)

func _on_mouse_entered() -> void:
	mouseEntered = true

func _on_mouse_exited():
	mouseEntered = false

# -----------------------------------------------------------------
# IDamageable contract
# -----------------------------------------------------------------

func take_damage(amount: int) -> void:
	current_health -= amount
	print("[COMBAT_LOG] Barracks ", entity_id, " (player ", player_id, ") took ", amount, " damage. HP: ", current_health, "/", max_health)
	if current_health <= 0:
		die()

func get_current_health() -> int:
	return current_health

func is_alive() -> bool:
	return current_health > 0

func get_player_id() -> int:
	return player_id

func die() -> void:
	print("[COMBAT_LOG] Barracks ", entity_id, " (player ", player_id, ") destroyed.")
	queue_free()

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

## Spends resources and bumps `upgrade_level`.  Returns true on success.
func upgrade() -> bool:
	if not can_upgrade():
		print("[BUILDING] Barracks already at max level (", upgrade_level, ").")
		return false
	var cost = get_upgrade_cost()
	if not Game.spend_resources(player_id, int(cost["wood"]), int(cost["stone"])):
		print("[BUILDING] Barracks upgrade denied (need ", cost["wood"], "w + ", cost["stone"], "s).")
		return false
	upgrade_level += 1
	var hp_delta = int(max_health * HP_BONUS_PER_LEVEL)
	max_health += hp_delta
	current_health = min(current_health + hp_delta, max_health)
	vision_range_tiles += VISION_BONUS_PER_LEVEL
	print("[BUILDING] Barracks (player ", player_id, ") upgraded to level ", upgrade_level,
		"  -- max HP ", max_health, ", vision ", vision_range_tiles)
	return true

## Discounted spawn cost based on upgrade level.
func get_effective_spawn_cost() -> Dictionary:
	var w = max(0, Game.SPAWN_COST_WOOD - upgrade_level * SPAWN_COST_REDUCTION_PER_LEVEL)
	var s = max(0, Game.SPAWN_COST_STONE - upgrade_level * SPAWN_COST_REDUCTION_PER_LEVEL)
	return {"wood": w, "stone": s}
