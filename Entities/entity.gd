extends Node2D
class_name Entity

## -----------------------------------------------------------------------
## Base class for every game entity (Units, Buildings, Resources).
## Implements the IDamageable contract so combat logic works universally.
## -----------------------------------------------------------------------

# Core state variables
@export var entity_id: int = -1
@export var max_health: int = 100
@export var player_id: int = 0        ## Owner player (-1 = neutral / environment)

var current_health: int
var is_selected: bool = false

# -----------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------

func _ready():
	current_health = max_health
	# Units group is used for the selection logic
	add_to_group("units")

func set_selected(value: bool):
	is_selected = value
	# Logic to toggle the visibility of the selection box
	if has_node("SelectionBox"):
		get_node("SelectionBox").visible = value

# -----------------------------------------------------------------
# IDamageable contract
# -----------------------------------------------------------------

func take_damage(amount: int) -> void:
	current_health -= amount
	print("[COMBAT_LOG] Entity ", entity_id, " (player ", player_id, ") took ", amount, " damage. HP: ", current_health, "/", max_health)
	if current_health <= 0:
		die()

func get_current_health() -> int:
	return current_health

func is_alive() -> bool:
	return current_health > 0

func get_player_id() -> int:
	return player_id

func die():
	print("[COMBAT_LOG] Entity ", entity_id, " (player ", player_id, ") destroyed.")
	queue_free()
