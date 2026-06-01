extends Node

@onready var spawn = preload("res://Entities/Interfaces/spawn_unit.tscn")

var Wood = 0
var Stone = 0
var game_room_id: String = "testgame"

func _init() -> void:
	var env_game_id = OS.get_environment("GAME_ROOM_ID")
	if env_game_id != "":
		game_room_id = env_game_id


func spawnUnit(position):
	var path = get_tree().get_root().get_node("World/UI")
	var hasSpawn = false
	for i in path.get_child_count():
		if "spawnUnit" in path.get_child(i).name:
			hasSpawn = true
	if hasSpawn == false:
		var spawnUnit = spawn.instantiate()
		spawnUnit.housePos = position
		path.add_child(spawnUnit)
