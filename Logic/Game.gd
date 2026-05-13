extends Node

@onready var spawn = preload("res://Entities/Interfaces/spawn_unit.tscn")

var wood = 0
var stone = 0

func spawn_unit(position):
	var path = get_tree().get_root().get_node("World/UI")
	var has_spawn = false
	for i in path.get_child_count():
		if "spawnUnit" in path.get_child(i).name:
			has_spawn = true
			
	if has_spawn == false:
		var spawn_unit_instance = spawn.instantiate()
		spawn_unit_instance.housePos = position
		path.add_child(spawn_unit_instance)
