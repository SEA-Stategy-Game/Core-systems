extends StaticBody2D

## -----------------------------------------------------------------------
## Barracks -- player home base.  Units return here after composite tasks.
## Implements IDamageable contract for universal combat targeting.
## -----------------------------------------------------------------------

@export var entity_id: int = -1
@export var player_id: int = 0
@export var max_health: int = 500
var current_health: int

var mouseEntered = false
@onready var select = get_node("Selected")
var selected = false

func _ready() -> void:
	current_health = max_health
	add_to_group("buildings")
	add_to_group("barracks")

func _process(delta) -> void:
	select.visible = selected

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("LeftClick"):
		print("click! mouseEntered=", mouseEntered, " allow=", _allow_spawn_ui())
		if mouseEntered == true and _allow_spawn_ui():
			selected = !selected
			if selected == true:
				Game.spawn_unit(global_position)



func _on_mouse_entered() -> void:
	print(mouseEntered)
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

func _allow_spawn_ui() -> bool:
	var session = get_node_or_null("/root/NetSession")
	if session and session.is_scenario_active():
		return false

	return true
