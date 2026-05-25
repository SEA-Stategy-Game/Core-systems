## ActionGateway.gd  (Autoload Singleton)
## -----------------------------------------------------------------------
## THE single entry-point for the AI Planning Team.
##
## The AI team sends a "Big Plan" via execute_plan() or calls high-level
## wrappers like go_chop_tree().  The Gateway translates these into
## IUnitAction objects, enqueues them into each unit's CommandQueue,
## and lets the TickManager drive execution.
##
## Signals are emitted so the AI can react to completion / failure
## without polling.
##
## MULTIPLAYER: Every command validates player_id ownership before
## execution.  Cross-player commands are rejected with [OWNERSHIP_ERR].
## -----------------------------------------------------------------------
extends Node

# -----------------------------------------------------------------
#  Signals -- AI team connects to these for feedback
# -----------------------------------------------------------------
signal task_completed(unit_id: int, action_data: Dictionary)
signal task_failed(unit_id: int, action_data: Dictionary)
signal path_blocked(unit_id: int, position: Dictionary)
signal plan_execution_finished(plan_id: String)
signal unit_idled(unit_id: int)

# -----------------------------------------------------------------
#  Sense API -- lazy-initialised on first access
# -----------------------------------------------------------------
var _sense: SenseAPI = null

func sense() -> SenseAPI:
	if _sense == null:
		_sense = SenseAPI.new(get_tree())
	return _sense

# -----------------------------------------------------------------
#  Chop-and-Return tracking
#  Maps unit_id -> { "state": "CHOPPING" | "RETURNING", "player_id": int }
# -----------------------------------------------------------------
var _chop_return_state: Dictionary = {}

# =================================================================
#  HIGH-LEVEL WRAPPERS  ("Task" layer)
# =================================================================

## GoChopTree: pathfind to the tree, then harvest it.
## Returns true if the commands were successfully enqueued.
func go_chop_tree(unit_id: int, tree_id: int, requesting_player_id: int = -1) -> bool:
	var unit = _find_unit(unit_id)
	var tree_node = _find_resource(tree_id)
	if unit == null or tree_node == null:
		push_warning("ActionGateway.go_chop_tree: unit or tree not found.")
		return false

	if not _validate_ownership(unit, requesting_player_id):
		return false

	var move_action = UnitActionMove.create_to_node(tree_node)
	var harvest_action = UnitActionHarvest.create(tree_node)

	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(move_action)
	cq.enqueue(harvest_action)
	return true

## GoChopTreeAndReturn: composite multi-step command.
## 1. Pathfind to tree  2. Harvest  3. Auto-return to nearest Barracks  4. Idle
## The AI team only sends this ONE call -- internal signals handle the rest.
func go_chop_tree_and_return(unit_id: int, tree_id: int, requesting_player_id: int = -1) -> bool:
	var unit = _find_unit(unit_id)
	var tree_node = _find_resource(tree_id)
	if unit == null or tree_node == null:
		push_warning("ActionGateway.go_chop_tree_and_return: unit or tree not found.")
		return false

	if not _validate_ownership(unit, requesting_player_id):
		return false

	var move_action = UnitActionMove.create_to_node(tree_node)
	var harvest_action = UnitActionHarvest.create(tree_node)

	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(move_action)
	cq.enqueue(harvest_action)

	# Register this unit for the return-to-base phase
	var uid = _get_uid(unit)
	_chop_return_state[uid] = {
		"state": "CHOPPING",
		"player_id": unit.player_id if "player_id" in unit else 0
	}
	print("[IDLE_REPORT] Unit ", uid, " starting chop-and-return sequence.")
	return true

## GoMineStone: pathfind to a stone node, then harvest it.
func go_mine_stone(unit_id: int, stone_id: int, requesting_player_id: int = -1) -> bool:
	var unit = _find_unit(unit_id)
	var stone_node = _find_resource(stone_id)
	if unit == null or stone_node == null:
		push_warning("ActionGateway.go_mine_stone: unit or stone not found.")
		return false

	if not _validate_ownership(unit, requesting_player_id):
		return false

	var move_action = UnitActionMove.create_to_node(stone_node)
	var harvest_action = UnitActionHarvest.create(stone_node)

	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(move_action)
	cq.enqueue(harvest_action)
	return true

## GoConstruct: pathfind to position, then build a structure.
func go_construct(unit_id: int, building_scene: String,
		build_pos: Vector2, duration: float = 10.0, requesting_player_id: int = -1) -> bool:
	var unit = _find_unit(unit_id)
	if unit == null:
		return false

	if not _validate_ownership(unit, requesting_player_id):
		return false

	var move_action = UnitActionMove.create(build_pos)
	var build_action = UnitActionConstruct.create(building_scene, build_pos, duration)

	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(move_action)
	cq.enqueue(build_action)
	return true

## MoveUnit: simple move-to-position.
func move_unit(unit_id: int, destination: Vector2, requesting_player_id: int = -1) -> bool:
	var unit = _find_unit(unit_id)
	if unit == null:
		return false

	if not _validate_ownership(unit, requesting_player_id):
		return false

	var action = UnitActionMove.create(destination)
	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(action)
	return true

## AttackTarget: move to and attack a specific hostile target.
func attack_target(unit_id: int, target_id: int, requesting_player_id: int = -1) -> bool:
	var unit = _find_unit(unit_id)
	if unit == null:
		return false

	if not _validate_ownership(unit, requesting_player_id):
		return false

	var target_node = _find_entity(target_id)
	if target_node == null:
		push_warning("ActionGateway.attack_target: target ", target_id, " not found.")
		return false

	# Verify target is hostile
	if target_node.has_method("get_player_id"):
		var unit_pid = unit.player_id if "player_id" in unit else 0
		if target_node.get_player_id() == unit_pid:
			push_warning("[OWNERSHIP_ERR] Cannot attack friendly entity ", target_id)
			return false

	var move_action = UnitActionMove.create_to_node(target_node)
	var attack_action = UnitActionAttack.create_focused(target_node)

	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(move_action)
	cq.enqueue(attack_action)
	return true

## AttackMove: move to position, auto-attack hostiles encountered.
func attack_move(unit_id: int, destination: Vector2, requesting_player_id: int = -1) -> bool:
	var unit = _find_unit(unit_id)
	if unit == null:
		return false

	if not _validate_ownership(unit, requesting_player_id):
		return false

	var move_action = UnitActionMove.create(destination)
	var attack_action = UnitActionAttack.create_auto()

	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(move_action)
	cq.enqueue(attack_action)
	return true

# =================================================================
#  PLAN EXECUTION  (the "Push/Pull" solution)
# =================================================================

## Execute a plan dictionary.  The plan format:
## {
##   "plan_id": "abc-123",
##   "player_id": 0,
##   "commands": [
##     {"unit_id": 1, "action": "MOVE",      "target": {"x": 100, "y": 200}},
##     {"unit_id": 1, "action": "HARVEST",    "target_id": 42},
##     {"unit_id": 2, "action": "CONSTRUCT",  "scene": "res://...", "position": {"x":..., "y":...}, "duration": 10},
##     {"unit_id": 1, "action": "CHOP_AND_RETURN", "target_id": 42},
##     {"unit_id": 3, "action": "ATTACK",     "target_id": 99}
##   ]
## }
func execute_plan(plan: Dictionary) -> bool:
	var plan_id: String = plan.get("plan_id", "unknown")
	var plan_player_id: int = int(plan.get("player_id", -1))
	var commands: Array = plan.get("commands", [])

	if commands.is_empty():
		push_warning("ActionGateway.execute_plan: empty command list.")
		return false

	for cmd in commands:
		var uid: int = int(cmd.get("unit_id", -1))
		var action_str: String = cmd.get("action", "")

		match action_str:
			"MOVE":
				var t = cmd.get("target", {})
				move_unit(uid, Vector2(t.get("x", 0), t.get("y", 0)), plan_player_id)
			"HARVEST":
				var tid: int = int(cmd.get("target_id", -1))
				go_chop_tree(uid, tid, plan_player_id)
			"CHOP_AND_RETURN":
				var tid: int = int(cmd.get("target_id", -1))
				go_chop_tree_and_return(uid, tid, plan_player_id)
			"CONSTRUCT":
				var pos = cmd.get("position", {})
				go_construct(
					uid,
					cmd.get("scene", ""),
					Vector2(pos.get("x", 0), pos.get("y", 0)),
					cmd.get("duration", 10.0),
					plan_player_id
				)
			"ATTACK":
				var tid: int = int(cmd.get("target_id", -1))
				attack_target(uid, tid, plan_player_id)
			"ATTACK_MOVE":
				var t = cmd.get("target", {})
				attack_move(uid, Vector2(t.get("x", 0), t.get("y", 0)), plan_player_id)
			_:
				push_warning("ActionGateway: Unknown action '", action_str, "' in plan.")

	plan_execution_finished.emit(plan_id)
	return true

## Pull-based variant: Core calls the AI module's get_plan() and executes.
## Override `_ai_get_plan` or connect it to the AI singleton.
func pull_and_execute() -> void:
	var plan: Dictionary = _ai_get_plan()
	if not plan.is_empty():
		execute_plan(plan)

## Stub -- replace with a call to the AI team's singleton / HTTP endpoint.
func _ai_get_plan() -> Dictionary:
	# Example: return AI_Planner.get_plan()
	return {}

# =================================================================
#  STATE REPORTING  (Sense API convenience pass-throughs)
# =================================================================

func get_all_units() -> Array:
	return sense().get_all_units()

func get_idle_units(pid: int) -> Array:
	return sense().get_idle_units(pid)

func get_busy_units(pid: int) -> Array:
	return sense().get_busy_units(pid)

func get_resources_near(origin: Vector2, radius: float) -> Array:
	return sense().get_resources_near(origin, radius)

func get_buildings_near(origin: Vector2, radius: float) -> Array:
	return sense().get_buildings_near(origin, radius)

func get_stockpile() -> Dictionary:
	return sense().get_resources_stockpile()

# =================================================================
#  PERSISTENCE
# =================================================================

func save_task_state() -> bool:
	return TaskSerializer.save_state(get_tree())

func load_task_state() -> Dictionary:
	return TaskSerializer.load_state()

func restore_task_state() -> void:
	var state = load_task_state()
	TaskSerializer.restore_queues(get_tree(), state)

# =================================================================
#  INTERNAL HELPERS
# =================================================================

## Validate that the requesting player owns the unit.
## If requesting_player_id is -1 (not specified), ownership check is skipped
## for backwards compatibility with single-player / test scenarios.
func _validate_ownership(unit: Node, requesting_player_id: int) -> bool:
	if requesting_player_id < 0:
		return true  # No ownership check requested

	var unit_owner_id: int = unit.player_id if "player_id" in unit else 0
	if unit_owner_id != requesting_player_id:
		var uid = _get_uid(unit)
		print("[OWNERSHIP_ERR] Player ", requesting_player_id,
			" attempted to command unit ", uid,
			" owned by player ", unit_owner_id, ". Request rejected.")
		return false
	return true

func _find_unit(unit_id: int) -> CharacterBody2D:
	for unit in get_tree().get_nodes_in_group("units"):
		if unit is CharacterBody2D:
			var uid = unit.entity_id if "entity_id" in unit else unit.get_instance_id()
			if uid == unit_id:
				return unit
	push_warning("ActionGateway: Unit ", unit_id, " not found.")
	return null

func _find_resource(resource_id: int) -> Node2D:
	# Search in Objects and direct World children
	var search_roots: Array = []
	var objects = get_tree().get_root().get_node_or_null("World/Objects")
	if objects:
		search_roots.append(objects)
	var world = get_tree().get_root().get_node_or_null("World")
	if world:
		search_roots.append(world)

	for root in search_roots:
		for child in root.get_children():
			var cid = child.entity_id if "entity_id" in child else child.get_instance_id()
			if cid == resource_id:
				return child
	return null

## Find any entity by ID across all groups (units, buildings, resources).
func _find_entity(eid: int) -> Node2D:
	# Check units
	var unit = _find_unit(eid)
	if unit:
		return unit

	# Check buildings
	for bld in get_tree().get_nodes_in_group("buildings"):
		var bid = bld.entity_id if "entity_id" in bld else bld.get_instance_id()
		if bid == eid:
			return bld

	# Check resources
	return _find_resource(eid)

## Find the nearest Barracks to the given position for a specific player.
func _find_nearest_barracks(pos: Vector2, pid: int) -> Node2D:
	var closest: Node2D = null
	var closest_dist: float = INF

	for node in get_tree().get_nodes_in_group("barracks"):
		if not is_instance_valid(node):
			continue
		# Match player ownership
		var node_pid: int = node.player_id if "player_id" in node else 0
		if node_pid != pid:
			continue
		var dist = pos.distance_to(node.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = node

	# Fallback: search all buildings if no barracks group
	if closest == null:
		for node in get_tree().get_nodes_in_group("buildings"):
			if not is_instance_valid(node):
				continue
			var node_pid: int = node.player_id if "player_id" in node else 0
			if node_pid != pid:
				continue
			var dist = pos.distance_to(node.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = node

	return closest

func _get_uid(node: Node) -> int:
	return node.entity_id if "entity_id" in node else node.get_instance_id()

func _get_or_create_queue(unit: CharacterBody2D) -> CommandQueue:
	if "command_queue" in unit and unit.command_queue != null:
		return unit.command_queue

	var cq = CommandQueue.new()
	var uid = unit.entity_id if "entity_id" in unit else unit.get_instance_id()
	cq.setup(unit, uid)

	# Wire signals
	cq.action_completed.connect(_on_action_completed)
	cq.action_failed.connect(_on_action_failed)
	if not cq.queue_empty.is_connected(_on_queue_empty):
		cq.queue_empty.connect(_on_queue_empty)

	# Store on the unit
	if "command_queue" in unit:
		unit.command_queue = cq
	else:
		unit.set_meta("command_queue", cq)

	return cq

# -----------------------------------------------------------------
#  Signal relays
# -----------------------------------------------------------------

func _on_action_completed(unit_id: int, action_data: Dictionary) -> void:
	task_completed.emit(unit_id, action_data)

func _on_action_failed(unit_id: int, action_data: Dictionary) -> void:
	task_failed.emit(unit_id, action_data)

func _on_queue_empty(unit_id: int) -> void:
	# Check if this unit is in a chop-and-return sequence
	if unit_id in _chop_return_state:
		var cr_state = _chop_return_state[unit_id]
		if cr_state["state"] == "CHOPPING":
			# Phase 1 complete (move + harvest done) -- now return to base
			_initiate_return_to_base(unit_id, cr_state["player_id"])
			return
		elif cr_state["state"] == "RETURNING":
			# Phase 2 complete -- unit has arrived at base
			_chop_return_state.erase(unit_id)
			var unit = _find_unit(unit_id)
			if unit and "is_idle" in unit:
				unit.is_idle = true
			print("[IDLE_REPORT] Unit ", unit_id, " returned to base. Chop-and-return complete. is_idle = true")
			unit_idled.emit(unit_id)
			return

	# Standard idle handling
	var unit = _find_unit(unit_id)
	if unit and "is_idle" in unit and unit.is_idle:
		unit_idled.emit(unit_id)

## Internal: enqueue the return-to-base movement for a chop-and-return unit.
func _initiate_return_to_base(unit_id: int, pid: int) -> void:
	var unit = _find_unit(unit_id)
	if unit == null:
		_chop_return_state.erase(unit_id)
		return

	var barracks = _find_nearest_barracks(unit.global_position, pid)
	if barracks == null:
		print("[IDLE_REPORT] Unit ", unit_id, " has no barracks to return to. Idling in place.")
		_chop_return_state.erase(unit_id)
		if "is_idle" in unit:
			unit.is_idle = true
		unit_idled.emit(unit_id)
		return

	_chop_return_state[unit_id]["state"] = "RETURNING"
	var move_action = UnitActionMove.create_to_node(barracks)
	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(move_action)
	print("[IDLE_REPORT] Unit ", unit_id, " returning to barracks at ", barracks.global_position)
