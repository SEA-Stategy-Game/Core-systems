extends Node2D
class_name Entity

# Core state variables
@export var entity_id: int
@export var max_health: int = 100
var current_health: int

var is_selected: bool = false

func _ready():
	current_health = max_health
	# Units group is used for the selection logic 
	add_to_group("units")

func set_selected(value: bool):
	is_selected = value
	# Logic to toggle the visibility of the selection box
	if has_node("SelectionBox"):
		get_node("SelectionBox").visible = value

func take_damage(amount: int):
	current_health -= amount
	if current_health <= 0:
		die()

func die():
	print("Entity ", entity_id, " destroyed.")
	queue_free()
