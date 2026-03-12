extends Node2D

@onready var unit = preload("res://Entities/Units/character_body_2d.tscn")

func _on_yes_pressed() -> void:
	var current_scene = get_tree().current_scene
	if current_scene:
		var unit_instance = unit.instantiate()
		unit_instance.position = Vector2(200, 200)
		var units_container = current_scene.get_node_or_null("Units")
		if units_container:
			units_container.add_child(unit_instance)
		else:
			current_scene.add_child(unit_instance)
	queue_free()

func _on_no_pressed() -> void:
	queue_free()
