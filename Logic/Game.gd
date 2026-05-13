extends Node

@onready var spawn = preload("res://Entities/Interfaces/spawn_unit.tscn")

var wood = 0
var stone = 0

func spawn_unit(position):
	var path = get_tree().get_root().get_node("World/UI")
	var has_spawn = false
	for i in path.get_child_count():
		if "spawnUnit" in path.get_child(i).name:
			hasSpawn = true
	if hasSpawn == false:
		var spawn_unit = spawn.instantiate()
		spawnUnit.housePos = position
		path.add_child(spawnUnit)
