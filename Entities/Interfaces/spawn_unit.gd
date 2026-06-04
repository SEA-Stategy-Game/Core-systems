extends Node2D

@onready var unit = preload("res://Entities/Units/unit.tscn")
var housePos: Vector2 = Vector2(300, 300)
var owner_player_id: int = 0
static var next_unit_id: int = 100  ## Static so IDs stay unique across pop-ups

@onready var status_label: Label = get_node_or_null("Label")

var sword_btn: Button = null
var bow_btn: Button = null

func _ready() -> void:
	_build_upgrade_buttons()
	_refresh_label()

func _build_upgrade_buttons() -> void:
	# The .tscn ships with Yes / No buttons; we add Sword & Bow next to them.
	sword_btn = Button.new()
	sword_btn.position = Vector2(430.0, 280.0)
	sword_btn.size = Vector2(170.0, 35.0)
	sword_btn.pressed.connect(_on_sword_pressed)
	add_child(sword_btn)

	bow_btn = Button.new()
	bow_btn.position = Vector2(430.0, 320.0)
	bow_btn.size = Vector2(170.0, 35.0)
	bow_btn.pressed.connect(_on_bow_pressed)
	add_child(bow_btn)

	_refresh_button_text()

func _refresh_button_text() -> void:
	if sword_btn:
		var lvl = Game.get_upgrade_level(owner_player_id, "sword")
		sword_btn.text = "Sword L%d  (+%dw)  → L%d" % [
			lvl, int(Game.SWORD_COST["wood"]), lvl + 1
		]
	if bow_btn:
		var lvl = Game.get_upgrade_level(owner_player_id, "bow")
		bow_btn.text = "Bow L%d  (+%dw / %ds)  → L%d" % [
			lvl, int(Game.BOW_COST["wood"]), int(Game.BOW_COST["stone"]), lvl + 1
		]

func _refresh_label() -> void:
	if status_label == null:
		return
	var wood = Game.get_player_wood(owner_player_id)
	var stone = Game.get_player_stone(owner_player_id)
	var sword_lvl = Game.get_upgrade_level(owner_player_id, "sword")
	var bow_lvl = Game.get_upgrade_level(owner_player_id, "bow")
	status_label.text = "Spawn a Unit?  Cost: %d wood, %d stone\n(P%d stockpile: %d wood / %d stone   Sword L%d   Bow L%d)" % [
		Game.SPAWN_COST_WOOD, Game.SPAWN_COST_STONE,
		owner_player_id, wood, stone, sword_lvl, bow_lvl
	]

# -----------------------------------------------------------------
# Upgrade button handlers
# -----------------------------------------------------------------

func _on_sword_pressed() -> void:
	var new_lvl = Game.purchase_upgrade(owner_player_id, "sword")
	if new_lvl < 0:
		if status_label:
			status_label.text = "Sword upgrade denied — need %d wood." % int(Game.SWORD_COST["wood"])
		return
	_refresh_button_text()
	_refresh_label()

func _on_bow_pressed() -> void:
	var new_lvl = Game.purchase_upgrade(owner_player_id, "bow")
	if new_lvl < 0:
		if status_label:
			status_label.text = "Bow upgrade denied — need %d wood + %d stone." % [
				int(Game.BOW_COST["wood"]), int(Game.BOW_COST["stone"])
			]
		return
	_refresh_button_text()
	_refresh_label()

# -----------------------------------------------------------------
# Yes / No -- spawn / close
# -----------------------------------------------------------------

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

	# Snap the jittered spawn onto the navmesh so the unit never lands on water.
	var spawn_pos = housePos + Vector2(randomPosX, randomPosY)
	spawn_pos = ActionGateway.snap_to_navmesh(spawn_pos)
	unit1.position = spawn_pos
	unitPath.add_child(unit1)

	# New units auto-inherit whatever upgrades the owner has purchased.
	Game.apply_player_upgrades_to_unit(owner_player_id, unit1)

	# Notify state mirror / listeners that a unit was created.
	GlobalSignals.unit_created.emit(unit1)

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
