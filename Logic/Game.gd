extends Node

@onready var spawn = preload("res://Entities/Interfaces/spawn_unit.tscn")

var Wood = 0
var Stone = 0

func spawnUnit():
	var current_scene = get_tree().current_scene
	if current_scene:
		var ui = current_scene.get_node_or_null("UI")
		if ui:
			var spawn_interface = spawn.instantiate()
			ui.add_child(spawn_interface)
		else:
			var spawn_interface = spawn.instantiate()
			current_scene.add_child(spawn_interface)
