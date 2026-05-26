extends Node

@onready var stone_scene = preload("res://Entities/Resource/stone.tscn")
@onready var tree_scene = preload("res://Entities/Resource/tree.tscn")
@onready var objects = get_tree().get_root().get_node("World/NavigationRegion2D/TileMapLayer/Objects")

var rng = RandomNumberGenerator.new();

# Simple spawntable that the MapTile can use to check if it should spawn a resource
# The Spawn_chance must be a percentage, but the other parameters are transformed into percentages
# Based on the other value, so e.g. "Stone" : 3 and "Tree" : 1 will give a 75% chance that the spawned resource is a stone and 25% that it is a tree 
var spawn_table = {
	MapTile.TerrainType.PLAINS : {
		"spawn_chance" : 0.1,
		"resource_table" : {
			"stone" : 2, 
			"tree" : 5
		}
	},
	MapTile.TerrainType.FOREST : {
		"spawn_chance" : 0.3,
		"resource_table" : {
			"stone" : 1, 
			"tree" : 5
		}
	},
	MapTile.TerrainType.HILLS : {
		"spawn_chance" : 0.2,
		"resource_table" : {
			"stone" : 5, 
			"tree" : 1
		}
	},
	MapTile.TerrainType.WATER : {
		"spawn_chance" : 0
	}
}

func _ready() -> void:
	# Funky (and inneficient, but happens only once) way of creating a chooser for selecting which type of resource to spawn 
	for type in spawn_table.values():
		var choice_array : Array[String] = []
		if "resource_table" in type:
			for resource in type["resource_table"]:
				for i in type["resource_table"][resource]:
					choice_array.append(resource)
			type["choice_array"] = choice_array

func set_rng(_rng : RandomNumberGenerator):
	rng = _rng

func sum(accum, number):
	return accum + number

func spawn_resource(type: MapTile.TerrainType) -> MapResource:
	var table_type = spawn_table[type]
	# First check if the field is selected for spawning a resource
	if rng.randf() <= table_type["spawn_chance"]:
		# Then check which kind of resource is picked
		var picked_num = rng.randi_range(0, table_type["choice_array"].size()-1) 
		match table_type["choice_array"][picked_num]:
			"tree":
				var tree = tree_scene.instantiate()
				objects.add_child(tree)
				return tree
			"stone":
				var stone = stone_scene.instantiate()
				objects.add_child(stone)
				return stone
	return null
