extends Node2D

@onready var unit = preload("res://Entities/Units/unit.tscn")
var housePos: Vector2 = Vector2(300, 300)
var owner_player_id: int = 0
static var next_unit_id: int = 100  ## Static so IDs stay unique across pop-ups

@onready var status_label: Label = get_node_or_null("Label")

func _ready() -> void:
	_refresh_label()

func _refresh_label() -> void:
	if status_label == null:
		return
	var wood = Game.get_player_wood(owner_player_id)
	var stone = Game.get_player_stone(owner_player_id)
	status_label.text = "Spawn a Unit?  Cost: %d wood, %d stone\n(P%d stockpile: %d wood / %d stone)" % [
		Game.SPAWN_COST_WOOD, Game.SPAWN_COST_STONE,
		owner_player_id, wood, stone
	]

func _on_yes_pressed() -> void:
	if not Game.can_afford_spawn(owner_player_id):
		if status_label:
			status_label.text = "Not enough resources!  Need %d wood + %d stone." % [
				Game.SPAWN_COST_WOOD, Game.SPAWN_COST_STONE
			]
		print("[BUILD_DENIED] Player ", owner_player_id, " cannot afford a unit spawn.")
		return

	if not Game.spend_resources(owner_player_id, Game.SPAWN_COST_WOOD, Game.SPAWN_COST_STONE):
		return

	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var randomPosX = rng.randi_range(-50, 50)
	var randomPosY = rng.randi_range(-50, 50)

	var unitPath = get_tree().get_root().get_node("World/Units")
	var worldPath = get_tree().get_root().get_node("World")
	var unit1 = unit.instantiate()
	unit1.entity_id = next_unit_id
	unit1.player_id = owner_player_id
	next_unit_id += 1

	unit1.position = housePos + Vector2(randomPosX, randomPosY)
	unitPath.add_child(unit1)
	if worldPath.has_method("get_units"):
		worldPath.get_units()

	print("[BUILD_OK] Spawned unit ", unit1.entity_id, " for player ", owner_player_id,
		"  (-", Game.SPAWN_COST_WOOD, "w / -", Game.SPAWN_COST_STONE, "s)")

	# Close the pop-up after a successful spawn.
	queue_free()

func _on_no_pressed() -> void:
	var housePath = get_tree().get_root().get_node_or_null(
		"World/NavigationRegion2D/TileMapLayer/Houses"
	)
	if housePath:
		for i in housePath.get_child_count():
			if housePath.get_child(i).selected == true:
				housePath.get_child(i).selected = false
	queue_free()
