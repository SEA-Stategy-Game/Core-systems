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
#  Unit-spawn pop-up helper (called from Barracks click)
# ---------------------------------------------------------------

func spawnUnit(position, owning_player_id: int = 0):
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
