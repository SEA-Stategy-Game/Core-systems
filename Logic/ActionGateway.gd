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

# =================================================================
#  HIGH-LEVEL WRAPPERS  ("Task" layer)
# =================================================================

## GoChopTree: pathfind to the tree, then harvest it.
## Returns true if the commands were successfully enqueued.
func go_chop_tree(unit_id: int, tree_id: int) -> bool:
	var unit = _find_unit(unit_id)
	var tree_node = _find_resource(tree_id)
	if unit == null or tree_node == null:
		push_warning("ActionGateway.go_chop_tree: unit or tree not found.")
		return false

	var move_action = UnitActionMove.create_to_node(tree_node)
	var harvest_action = UnitActionHarvest.create(tree_node)

	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(move_action)
	cq.enqueue(harvest_action)
	return true

## GoMineStone: pathfind to a stone node, then harvest it.
func go_mine_stone(unit_id: int, stone_id: int) -> bool:
	var unit = _find_unit(unit_id)
	var stone_node = _find_resource(stone_id)
	if unit == null or stone_node == null:
		push_warning("ActionGateway.go_mine_stone: unit or stone not found.")
		return false

	var move_action = UnitActionMove.create_to_node(stone_node)
	var harvest_action = UnitActionHarvest.create(stone_node)

	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(move_action)
	cq.enqueue(harvest_action)
	return true

## GoConstruct: pathfind to position, then build a structure.
func go_construct(unit_id: int, building_scene: String,
		build_pos: Vector2, duration: float = 10.0) -> bool:
	var unit = _find_unit(unit_id)
	if unit == null:
		return false

	var move_action = UnitActionMove.create(build_pos)
	var build_action = UnitActionConstruct.create(building_scene, build_pos, duration)

	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(move_action)
	cq.enqueue(build_action)
	return true

## MoveUnit: simple move-to-position.
func move_unit(unit_id: int, destination: Vector2) -> bool:
	var unit = _find_unit(unit_id)
	if unit == null:
		return false

	var action = UnitActionMove.create(destination)
	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(action)
	return true

# =================================================================
#  PLAN EXECUTION  (the "Push/Pull" solution)
# =================================================================

## Execute a plan dictionary.  The plan format:
## {
##   "plan_id": "abc-123",
##   "commands": [
##     {"unit_id": 1, "action": "MOVE",      "target": {"x": 100, "y": 200}},
##     {"unit_id": 1, "action": "HARVEST",    "target_id": 42},
##     {"unit_id": 2, "action": "CONSTRUCT",  "scene": "res://...", "position": {"x":..., "y":...}, "duration": 10}
##   ]
## }
func execute_plan(plan: Dictionary) -> bool:
	var plan_id: String = plan.get("plan_id", "unknown")
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
				move_unit(uid, Vector2(t.get("x", 0), t.get("y", 0)))
			"HARVEST":
				var tid: int = int(cmd.get("target_id", -1))
				var unit = _find_unit(uid)
				var res_node = _find_resource(tid)
				if unit and res_node:
					var mv = UnitActionMove.create_to_node(res_node)
					var hv = UnitActionHarvest.create(res_node)
					var cq = _get_or_create_queue(unit)
					cq.enqueue(mv)
					cq.enqueue(hv)
			"CONSTRUCT":
				var pos = cmd.get("position", {})
				go_construct(
					uid,
					cmd.get("scene", ""),
					Vector2(pos.get("x", 0), pos.get("y", 0)),
					cmd.get("duration", 10.0)
				)
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
	var unit = _find_unit(unit_id)
	if unit and "is_idle" in unit and unit.is_idle:
		unit_idled.emit(unit_id)
