extends Node

## -----------------------------------------------------------------------
## Global game state autoload.
##
## - Player stockpiles (wood / stone), tracked per player_id.
## - Building costs for the in-game build / spawn pop-up.
## - Win condition thresholds.
## - Helper for opening the unit-spawn pop-up over a Barracks.
## -----------------------------------------------------------------------

@onready var spawn = preload("res://Entities/Interfaces/spawn_unit.tscn")

var is_headless: bool = false
var game_room_id: String = "testgame"

func _init() -> void:
	OS.set_environment("USE_REDIS", "true")
	var env_game_id = OS.get_environment("GAME_ROOM_ID")
	if env_game_id != "":
		game_room_id = env_game_id
	is_headless = DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_args()

# ---------------------------------------------------------------
#  Per-player stockpiles ( pid -> { "wood": int, "stone": int } )
# ---------------------------------------------------------------
var player_resources: Dictionary = {}

# Backwards-compat globals -- the existing UI label reads these.
# They mirror player 0's stockpile.
var Wood: int = 0
var Stone: int = 0

# ---------------------------------------------------------------
#  Build / spawn cost (Barracks unit spawn = 10 wood + 5 stone)
# ---------------------------------------------------------------
const SPAWN_COST_WOOD: int = 10
const SPAWN_COST_STONE: int = 5

# Threshold for the "economy" win condition.
const RESOURCE_WIN_THRESHOLD: int = 50

# ---------------------------------------------------------------
#  Army-wide upgrades (Sword, Bow)
# ---------------------------------------------------------------
const SWORD_COST: Dictionary = {"wood": 15, "stone": 0}
const BOW_COST: Dictionary   = {"wood": 10, "stone": 5}

const SWORD_DAMAGE_PER_LEVEL: int = 5            ## +5 attack damage / level
const BOW_DAMAGE_PER_LEVEL: int = 3              ## +3 attack damage / level
const BOW_VISION_PER_LEVEL: int = 1              ## +1 vision tile / level
const BOW_RANGE_SCALE_PER_LEVEL: float = 0.5     ## +50 % attack range / level

## pid -> { "sword": int_level, "bow": int_level }
var player_upgrades: Dictionary = {}

# Number of players selected on the player-count pop-up. 1 means solo.
var player_count: int = 1

# Set true once a victory pop-up has been shown so the win-checker stops.
var game_over: bool = false

# ---------------------------------------------------------------
#  Stockpile accessors
# ---------------------------------------------------------------

func _ensure(pid: int) -> void:
	if not player_resources.has(pid):
		player_resources[pid] = {"wood": 0, "stone": 0}

func add_resource(pid: int, kind: String, amount: int = 1) -> void:
	_ensure(pid)
	player_resources[pid][kind] = player_resources[pid].get(kind, 0) + amount
	_sync_legacy()

func spend_resources(pid: int, wood_cost: int, stone_cost: int) -> bool:
	_ensure(pid)
	if player_resources[pid]["wood"] < wood_cost:
		return false
	if player_resources[pid]["stone"] < stone_cost:
		return false
	player_resources[pid]["wood"] -= wood_cost
	player_resources[pid]["stone"] -= stone_cost
	_sync_legacy()
	return true

func can_afford_spawn(pid: int) -> bool:
	_ensure(pid)
	return (
		player_resources[pid]["wood"] >= SPAWN_COST_WOOD
		and player_resources[pid]["stone"] >= SPAWN_COST_STONE
	)

func get_player_wood(pid: int) -> int:
	_ensure(pid)
	return player_resources[pid]["wood"]

func get_player_stone(pid: int) -> int:
	_ensure(pid)
	return player_resources[pid]["stone"]

func _sync_legacy() -> void:
	# Keep the old Wood / Stone globals in sync with player 0 for the UI label.
	if player_resources.has(0):
		Wood = player_resources[0]["wood"]
		Stone = player_resources[0]["stone"]

# ---------------------------------------------------------------
#  Upgrade ledger + factory
# ---------------------------------------------------------------

func _ensure_upgrades(pid: int) -> void:
	if not player_upgrades.has(pid):
		player_upgrades[pid] = {"sword": 0, "bow": 0}

func get_upgrade_level(pid: int, kind: String) -> int:
	_ensure_upgrades(pid)
	return int(player_upgrades[pid].get(kind, 0))

## Spend the cost and bump the level by 1.  Returns the new level on
## success, -1 on failure (no resources / unknown kind).
func purchase_upgrade(pid: int, kind: String) -> int:
	var cost: Dictionary
	match kind:
		"sword": cost = SWORD_COST
		"bow":   cost = BOW_COST
		_:
			push_warning("Game.purchase_upgrade: unknown kind '%s'" % kind)
			return -1
	if not spend_resources(pid, int(cost["wood"]), int(cost["stone"])):
		return -1
	_ensure_upgrades(pid)
	player_upgrades[pid][kind] = int(player_upgrades[pid].get(kind, 0)) + 1
	var new_level: int = int(player_upgrades[pid][kind])
	print("[UPGRADE] Player ", pid, " purchased ", kind, " level ", new_level)
	# Apply to every existing unit of that player and to the spawn defaults.
	apply_player_upgrades_to_all_units(pid)
	return new_level

## Builds an Equipment object representing one *level* of the upgrade.
func make_upgrade_equipment(kind: String, level: int) -> Equipment:
	if level <= 0:
		return null
	match kind:
		"sword":
			return Equipment.create("Sword L%d" % level, {
				"attack_damage_bonus": SWORD_DAMAGE_PER_LEVEL * level,
			})
		"bow":
			return Equipment.create("Bow L%d" % level, {
				"attack_damage_bonus": BOW_DAMAGE_PER_LEVEL * level,
				"vision_bonus_tiles":  BOW_VISION_PER_LEVEL * level,
				"attack_range_scale":  1.0 + BOW_RANGE_SCALE_PER_LEVEL * level,
			})
		_:
			return null

## Equip the appropriate-level Sword/Bow on a single unit, removing any
## previously-attached "Sword L*" / "Bow L*" first so we don't stack
## stale levels on top of new ones.
func apply_player_upgrades_to_unit(pid: int, unit: Node) -> void:
	if unit == null:
		return
	_ensure_upgrades(pid)
	if "equipped" in unit:
		var stale: Array = []
		for e in unit.equipped:
			if not is_instance_valid(e):
				continue
			if e.equipment_name.begins_with("Sword L") or e.equipment_name.begins_with("Bow L"):
				stale.append(e)
		for e in stale:
			unit.unequip(e)
	for kind in ["sword", "bow"]:
		var lvl = int(player_upgrades[pid].get(kind, 0))
		if lvl <= 0:
			continue
		var eq = make_upgrade_equipment(kind, lvl)
		if eq != null and unit.has_method("equip"):
			unit.equip(eq)

## Re-equip Sword/Bow on every unit owned by `pid`.
func apply_player_upgrades_to_all_units(pid: int) -> void:
	var tree = get_tree()
	if tree == null:
		return
	for u in tree.get_nodes_in_group("units"):
		if "player_id" in u and int(u.player_id) == pid:
			apply_player_upgrades_to_unit(pid, u)

# ---------------------------------------------------------------
#  Unit-spawn pop-up helper (called from Barracks click)
# ---------------------------------------------------------------

func spawnUnit(position, owning_player_id: int = 0):
	if is_headless:
		# In headless mode, bypass the UI popup and spawn directly if affordable.
		if can_afford_spawn(owning_player_id):
			spend_resources(owning_player_id, SPAWN_COST_WOOD, SPAWN_COST_STONE)
			var unit_scene = load("res://Entities/Units/unit.tscn")
			var unit = unit_scene.instantiate()
			var units_node = get_tree().get_root().get_node_or_null("World/Units")
			if not units_node:
				units_node = Node2D.new()
				units_node.name = "Units"
				get_tree().get_root().get_node("World").add_child(units_node)
			var new_id = ActionGateway.get_next_entity_id()
			unit.set("entity_id", new_id)
			unit.set("player_id", owning_player_id)
			unit.position = position + Vector2(randf_range(-10, 10), randf_range(10, 20))
			units_node.add_child(unit)
			apply_player_upgrades_to_unit(owning_player_id, unit)
			print("[BUILD_OK] Spawned unit ", new_id, " for player ", owning_player_id, " at ", unit.position)
			GlobalSignals.unit_created.emit(unit)
		else:
			print("[BUILD_DENIED] Player ", owning_player_id, " cannot afford a unit spawn.")
		return
	
	var path = get_tree().get_root().get_node_or_null("World/UI")
	if path == null:
		return
	var hasSpawn = false
	for i in path.get_child_count():
		if "spawnUnit" in path.get_child(i).name:
			hasSpawn = true
	if hasSpawn == false:
		var spawnUnit = spawn.instantiate()
		spawnUnit.housePos = position
		spawnUnit.owner_player_id = owning_player_id
		path.add_child(spawnUnit)
