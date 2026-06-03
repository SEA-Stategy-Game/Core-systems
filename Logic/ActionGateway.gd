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

## Damage multiplier applied when a player explicitly commands an attack
## (vs. auto-aggro defence).  Keeps the initiative advantage small so
## reactive defence still has a chance.
const PLAYER_INITIATIVE_BONUS: float = 1.25

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

# -----------------------------------------------------------------
#  Entity ID Generation
# -----------------------------------------------------------------
var _next_entity_id: int = 1000 # Start high to avoid collision with scene-placed entities

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

## AttackTarget: attack a specific hostile target.  The ATTACK action chases
## the target on its own (see UnitActionAttack.CHASE_SPEED), so we don't
## prepend a MOVE — that previously stalled when the attacker's body
## collided with the target's body before MOVE could reach arrival_radius.
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

	var attack_action = UnitActionAttack.create_focused(target_node, PLAYER_INITIATIVE_BONUS)
	var cq: CommandQueue = _get_or_create_queue(unit)
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
	var attack_action = UnitActionAttack.create_auto(PLAYER_INITIATIVE_BONUS)

	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(move_action)
	cq.enqueue(attack_action)
	return true

# =================================================================
#  ID-FREE WRAPPERS  (the AI team scrapped target-id tracking, so
#  these resolve the nearest matching entity for them).
# =================================================================

## Chop the nearest tree to the named unit.  Returns true on success.
func go_chop_nearest_tree(unit_id: int, requesting_player_id: int = -1) -> bool:
	var unit = _find_unit(unit_id)
	if unit == null:
		return false
	if not _validate_ownership(unit, requesting_player_id):
		return false
	var tree_node = _find_nearest_resource_of_kind(unit.global_position, "tree")
	if tree_node == null:
		print("[SENSE_QUERY] No trees available for unit ", unit_id)
		return false
	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(UnitActionMove.create_to_node(tree_node))
	cq.enqueue(UnitActionHarvest.create(tree_node))
	return true

## Mine the nearest stone to the named unit.
func go_mine_nearest_stone(unit_id: int, requesting_player_id: int = -1) -> bool:
	var unit = _find_unit(unit_id)
	if unit == null:
		return false
	if not _validate_ownership(unit, requesting_player_id):
		return false
	var stone_node = _find_nearest_resource_of_kind(unit.global_position, "stone")
	if stone_node == null:
		print("[SENSE_QUERY] No stones available for unit ", unit_id)
		return false
	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(UnitActionMove.create_to_node(stone_node))
	cq.enqueue(UnitActionHarvest.create(stone_node))
	return true

## Attack the nearest hostile entity (unit / building) of any other player.
func attack_nearest_enemy(unit_id: int, requesting_player_id: int = -1) -> bool:
	var unit = _find_unit(unit_id)
	if unit == null:
		return false
	if not _validate_ownership(unit, requesting_player_id):
		return false
	var target = _find_nearest_hostile(unit)
	if target == null:
		print("[COMBAT_LOG] No hostiles available for unit ", unit_id)
		return false
	# UnitActionAttack chases on its own; queue MOVE separately and the body
	# collision against the target prevents MOVE from ever arriving.
	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(UnitActionAttack.create_focused(target, PLAYER_INITIATIVE_BONUS))
	return true

# =================================================================
#  REACTIVE BEHAVIOR PLANS  (forward to BehaviorPlanner)
# =================================================================

## Register a list of (when, do, priority) rules on a unit.  Every
## TickManager tick the planner picks the highest-priority matching
## rule and dispatches it.  Pass [] to clear.
func set_behavior_plan(unit_id: int, rules: Array, requesting_player_id: int = -1) -> bool:
	var bp = get_node_or_null("/root/BehaviorPlanner")
	if bp == null:
		push_error("ActionGateway.set_behavior_plan: BehaviorPlanner not loaded.")
		return false
	return bp.set_behavior(unit_id, rules, requesting_player_id)

func clear_behavior_plan(unit_id: int, _requesting_player_id: int = -1) -> bool:
	var bp = get_node_or_null("/root/BehaviorPlanner")
	if bp == null:
		return false
	bp.clear_behavior(unit_id)
	return true

## Trigger an AoE explosion at a world position centred at `center`.
## Hostiles within `radius` take linearly-falling damage.
func explode_at(unit_id: int, center: Vector2, radius: float = 64.0,
		damage: int = 25, requesting_player_id: int = -1) -> bool:
	var unit = _find_unit(unit_id)
	if unit == null:
		return false
	if not _validate_ownership(unit, requesting_player_id):
		return false
	var action = UnitActionExplode.create(center, radius, damage)
	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(action)
	return true

## Convenience composite: chop nearest tree, then march back to the unit's
## nearest barracks and idle.  Mirrors `go_chop_tree_and_return` but
## without requiring a tree_id.
func go_chop_nearest_tree_and_return(unit_id: int, requesting_player_id: int = -1) -> bool:
	var unit = _find_unit(unit_id)
	if unit == null:
		return false
	if not _validate_ownership(unit, requesting_player_id):
		return false
	var tree_node = _find_nearest_resource_of_kind(unit.global_position, "tree")
	if tree_node == null:
		return false
	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(UnitActionMove.create_to_node(tree_node))
	cq.enqueue(UnitActionHarvest.create(tree_node))
	var uid = _get_uid(unit)
	_chop_return_state[uid] = {
		"state": "CHOPPING",
		"player_id": unit.player_id if "player_id" in unit else 0
	}
	print("[IDLE_REPORT] Unit ", uid, " starting nearest-tree chop-and-return.")
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
	var behaviors: Array = plan.get("behaviors", [])

	# Register any reactive behavior blocks first so they are armed before
	# the imperative commands kick in.
	# Format:  "behaviors": [ {"unit_id": 1, "rules": [...]}, ... ]
	for b in behaviors:
		var bd: Dictionary = b
		var uid := int(bd.get("unit_id", -1))
		var rules: Array = bd.get("rules", [])
		set_behavior_plan(uid, rules, plan_player_id)

	if commands.is_empty() and behaviors.is_empty():
		push_warning("ActionGateway.execute_plan: empty command list.")
		return false
	if commands.is_empty():
		# Behavior-only plan; nothing to dispatch immediately.
		plan_execution_finished.emit(plan_id)
		return true

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
			"CHOP_NEAREST":
				go_chop_nearest_tree(uid, plan_player_id)
			"MINE_NEAREST":
				go_mine_nearest_stone(uid, plan_player_id)
			"ATTACK_NEAREST":
				attack_nearest_enemy(uid, plan_player_id)
			"CHOP_NEAREST_AND_RETURN":
				go_chop_nearest_tree_and_return(uid, plan_player_id)
			"EXPLODE":
				var t = cmd.get("target", {})
				var radius = float(cmd.get("radius", 64.0))
				var dmg = int(cmd.get("damage", 25))
				explode_at(uid, Vector2(t.get("x", 0), t.get("y", 0)), radius, dmg, plan_player_id)
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

func get_player_units(pid: int) -> Array:
	return sense().get_player_units(pid)

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
			var uid = _get_uid(unit)
			if uid == unit_id:
				return unit
	push_warning("ActionGateway: Unit ", unit_id, " not found.")
	return null

## Find a unit by entity_id filtered to a specific player.
## Falls back to entity_id-only search when player_id < 0 (single-player / test).
func _find_unit_for_player(unit_id: int, player_id: int) -> Node:
	if player_id < 0:
		return _find_unit(unit_id)
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.get("entity_id") == unit_id and unit.get("player_id") == player_id:
			return unit
	push_warning("ActionGateway: Unit %d not found for player %d" % [unit_id, player_id])
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
			var cid = _get_uid(child)
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
		var bid = _get_uid(bld)
		if bid == eid:
			return bld

	# Check resources
	return _find_resource(eid)

## Find the nearest resource ("tree" or "stone") to a position.
func _find_nearest_resource_of_kind(pos: Vector2, kind: String) -> Node2D:
	var closest: Node2D = null
	var closest_dist: float = INF
	for r in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(r):
			continue
		var name_lower: String = ""
		if "resource_name" in r:
			name_lower = String(r.resource_name).to_lower()
		else:
			name_lower = String(r.name).to_lower()
		if kind == "tree" and not (name_lower.contains("tree") or r is TreeResource):
			continue
		if kind == "stone" and not (name_lower.contains("stone") or r is StoneResource):
			continue
		var d = pos.distance_to(r.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = r
	return closest

## Find the nearest hostile (different player_id, not -1) to a unit.
func _find_nearest_hostile(unit: Node2D) -> Node2D:
	var unit_pid: int = unit.player_id if "player_id" in unit else 0
	var closest: Node2D = null
	var closest_dist: float = INF
	var candidates: Array = []
	candidates.append_array(get_tree().get_nodes_in_group("units"))
	candidates.append_array(get_tree().get_nodes_in_group("buildings"))
	candidates.append_array(get_tree().get_nodes_in_group("barracks"))
	for c in candidates:
		if c == unit or not is_instance_valid(c):
			continue
		if not c.has_method("get_player_id"):
			continue
		var c_pid: int = c.get_player_id()
		if c_pid == unit_pid or c_pid == -1:
			continue
		if c.has_method("is_alive") and not c.is_alive():
			continue
		var d = unit.global_position.distance_to(c.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = c
	return closest

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
	if "entity_id" in node and node.entity_id > 0:
		return node.entity_id
	if node.has_meta("entity_id") and node.get_meta("entity_id") > 0:
		return node.get_meta("entity_id")
	# Fallback for nodes that might not have a persistent ID yet
	return node.get_instance_id()
func _get_or_create_queue(unit: CharacterBody2D) -> CommandQueue:
	var cq: CommandQueue
	if "command_queue" in unit and unit.command_queue != null:
		cq = unit.command_queue
	else:
		cq = CommandQueue.new()
		var uid = _get_uid(unit)
		cq.setup(unit, uid)
		if "command_queue" in unit:
			unit.command_queue = cq
		else:
			unit.set_meta("command_queue", cq)

	# Wire signals — guards forhindrer dubletter ved gentagne kald
	if not cq.action_completed.is_connected(_on_action_completed):
		cq.action_completed.connect(_on_action_completed)
	if not cq.action_failed.is_connected(_on_action_failed):
		cq.action_failed.connect(_on_action_failed)
	if not cq.queue_empty.is_connected(_on_queue_empty):
		cq.queue_empty.connect(_on_queue_empty)

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
	# Barracks body is bigger than a unit can push into — use a 25 px arrival
	# radius so MOVE completes once the unit is pressed against it.
	var move_action = UnitActionMove.create_to_node(barracks, 25.0)
	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(move_action)
	print("[IDLE_REPORT] Unit ", unit_id, " returning to barracks at ", barracks.global_position)

func get_next_entity_id() -> int:
	var id = _next_entity_id
	_next_entity_id += 1
	return id

## Returns the closest point ON the world navmesh to `point`.
## Used so spawned units never land on water / off-navigation tiles --
## an off-mesh point gets snapped to the nearest walkable edge.
func snap_to_navmesh(point: Vector2) -> Vector2:
	var nav_region = get_tree().get_root().get_node_or_null("World/NavigationRegion2D")
	if nav_region == null:
		return point
	var nav_map: RID = nav_region.get_navigation_map()
	if not nav_map.is_valid() or not NavigationServer2D.map_is_active(nav_map):
		return point
	var snapped: Vector2 = NavigationServer2D.map_get_closest_point(nav_map, point)
	# Guard against an un-synced map returning the origin.
	if snapped == Vector2.ZERO and point.length() > 1.0:
		return point
	return snapped

# =================================================================
#  SPAWNING UTILITIES
# =================================================================

## Instantiates an initial unit for a new player and adds it to the World.
func spawn_initial_unit(player_id: int, scene_path: String = "res://Entities/Units/unit.tscn") -> Node2D:
	var unit_scene = load(scene_path)
	if not unit_scene:
		push_error("ActionGateway.spawn_initial_unit: Could not load scene " + scene_path)
		return null
		
	var unit = unit_scene.instantiate()
	
	# Assign the correct ownership
	unit.set("player_id", player_id)
	unit.set_meta("player_id", player_id)
		
	# Assign a unique entity_id to prevent dictionary key overwrites in state payloads
	var new_id = get_next_entity_id()
	unit.set("entity_id", new_id)
	unit.set_meta("entity_id", new_id)
		
	# Ensure the unit is discoverable by SenseAPI queries
	unit.add_to_group("units")
	
	# Snap the random spawn onto the navmesh so units never land on water.
	var random_spawn_point = Vector2(randf_range(100.0, 500.0), randf_range(100.0, 500.0))
	random_spawn_point = snap_to_navmesh(random_spawn_point)
	unit.global_position = random_spawn_point

	# Robustly fetch the Units container from the active scene
	var current_scene = get_tree().current_scene
	var units_container = current_scene.get_node_or_null("Units") if current_scene else null
	if units_container:
		units_container.add_child(unit)
		print("[SPAWN] Initial unit ", new_id, " created for Player ", player_id, " at ", random_spawn_point)
		GlobalSignals.unit_created.emit(unit)
	else:
		push_error("ActionGateway.spawn_initial_unit: Could not find 'Units' container in current scene.")
		
	return unit
