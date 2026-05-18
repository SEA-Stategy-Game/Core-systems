extends Node

signal task_completed(unit_id: int, action_data: Dictionary)
signal task_failed(unit_id: int, action_data: Dictionary)
signal path_blocked(unit_id: int, position: Dictionary)
signal plan_execution_finished(plan_id: String)
signal unit_idled(unit_id: int)
signal command_validated(command: Dictionary)

var _sense: SenseAPI = null
var _active_player_id: int = 0
var _chop_return_state: Dictionary = {}
var _tick_manager: TickManager = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tick_manager = get_node_or_null("/root/TickManager") as TickManager
	if _tick_manager != null and not _tick_manager.tick.is_connected(_on_tick):
		_tick_manager.tick.connect(_on_tick)

func set_active_player(player_id: int) -> void:
	_active_player_id = player_id

func sense() -> SenseAPI:
	if _sense == null:
		_sense = SenseAPI.new(get_tree())
	return _sense

func move_unit(unit_id: int, destination: Vector2, requesting_player_id: int = -1, requesting_peer_id: int = -1) -> bool:
	var unit = _find_unit(unit_id)
	if unit == null:
		return false
	if not _validate_ownership(unit, requesting_player_id, requesting_peer_id):
		return false

	var tile_map = get_node_or_null("/root/World/NavigationRegion2D/TileMapLayer")
	if tile_map != null and tile_map.has_method("get_tile_at_world_pos"):
		var tile = tile_map.get_tile_at_world_pos(destination)
		if tile == null or int(tile.terrain) == MapTile.TerrainType.WATER:
			push_warning("[MOVE_DENIED] Destination is not walkable (water/outside map): %s" % str(destination))
			return false

	var action = UnitActionMove.create(destination)
	var cq: CommandQueue = _get_or_create_queue(unit)
	if not cq.enqueue(action):
		return false

	_emit_command("MOVE", unit_id, {
		"destination": {"x": destination.x, "y": destination.y}
	})
	return true

func go_chop_tree_and_return(unit_id: int, tree_id: int, requesting_player_id: int = -1, requesting_peer_id: int = -1) -> bool:
	var unit = _find_unit(unit_id)
	var tree_node = _find_resource(tree_id)
	if unit == null or tree_node == null:
		push_warning("ActionGateway.go_chop_tree_and_return: unit or tree not found.")
		return false
	if not _validate_ownership(unit, requesting_player_id, requesting_peer_id):
		return false
	if tree_node.has_method("is_alive") and not tree_node.is_alive():
		print("[RESOURCE_LOG] Rejected harvest command against destroyed resource ", tree_id, ".")
		return false

	var cq: CommandQueue = _get_or_create_queue(unit)
	if not cq.enqueue(UnitActionMove.create_to_node(tree_node)):
		return false
	if not cq.enqueue(UnitActionHarvest.create(tree_node)):
		return false

	var barracks := _find_closest_barracks(unit.global_position)
	if barracks != null:
		cq.enqueue(UnitActionMove.create_to_node(barracks))

	var uid := _get_uid(unit)
	_chop_return_state[uid] = {
		"state": "CHOPPING",
		"player_id": unit.player_id if "player_id" in unit else 0
	}

	_emit_command("CHOP_AND_RETURN", unit_id, {
		"target_id": tree_id
	})
	return true

func go_chop_tree(unit_id: int, tree_id: int, requesting_player_id: int = -1, requesting_peer_id: int = -1) -> bool:
	return go_chop_tree_and_return(unit_id, tree_id, requesting_player_id, requesting_peer_id)

func go_mine_stone(unit_id: int, stone_id: int, requesting_player_id: int = -1, requesting_peer_id: int = -1) -> bool:
	return go_chop_tree_and_return(unit_id, stone_id, requesting_player_id, requesting_peer_id)

func go_construct(unit_id: int, building_scene: String, build_pos: Vector2, duration: float = 10.0, requesting_player_id: int = -1, requesting_peer_id: int = -1) -> bool:
	var unit = _find_unit(unit_id)
	if unit == null:
		return false
	if not _validate_ownership(unit, requesting_player_id, requesting_peer_id):
		return false

	var cq: CommandQueue = _get_or_create_queue(unit)
	if not cq.enqueue(UnitActionMove.create(build_pos)):
		return false
	if not cq.enqueue(UnitActionConstruct.create(building_scene, build_pos, duration)):
		return false

	_emit_command("CONSTRUCT", unit_id, {
		"building_scene": building_scene,
		"position": {"x": build_pos.x, "y": build_pos.y},
		"duration": duration
	})
	return true

func attack_target(unit_id: int, target_id: int, requesting_player_id: int = -1, requesting_peer_id: int = -1) -> bool:
	var unit = _find_unit(unit_id)
	var target_node = _find_entity(target_id)
	if unit == null or target_node == null:
		return false
	if not _validate_ownership(unit, requesting_player_id, requesting_peer_id):
		return false
	if target_node.has_method("is_alive") and not target_node.is_alive():
		print("[COMBAT_LOG] Rejected ATTACK from unit ", unit_id, " against destroyed target ", target_id, ".")
		return false

	var cq: CommandQueue = _get_or_create_queue(unit)
	cq.enqueue(UnitActionMove.create_to_node(target_node))
	cq.enqueue(UnitActionAttack.create(target_node))
	_emit_command("ATTACK", unit_id, {"target_id": target_id})
	return true

func execute_plan(plan: Dictionary) -> bool:
	var commands: Array = plan.get("commands", [])
	if commands.is_empty():
		return false

	var ok := true
	for cmd in commands:
		var uid: int = int(cmd.get("unit_id", -1))
		match String(cmd.get("action", "")):
			"MOVE":
				ok = move_unit(uid, Vector2(float(cmd.get("target", {}).get("x", 0.0)), float(cmd.get("target", {}).get("y", 0.0))), int(plan.get("player_id", -1))) and ok
			"HARVEST":
				ok = go_chop_tree(uid, int(cmd.get("target_id", -1)), int(plan.get("player_id", -1))) and ok
			"CHOP_AND_RETURN":
				ok = go_chop_tree_and_return(uid, int(cmd.get("target_id", -1)), int(plan.get("player_id", -1))) and ok
			"CONSTRUCT":
				ok = go_construct(uid, String(cmd.get("scene", "")), Vector2(float(cmd.get("position", {}).get("x", 0.0)), float(cmd.get("position", {}).get("y", 0.0))), float(cmd.get("duration", 10.0)), int(plan.get("player_id", -1))) and ok
			"ATTACK":
				ok = attack_target(uid, int(cmd.get("target_id", -1)), int(plan.get("player_id", -1))) and ok
			_:
				push_warning("ActionGateway.execute_plan: Unknown action '%s'" % String(cmd.get("action", "")))
	return ok

func _on_tick(_tick: int) -> void:
	if _tick_manager == null:
		return
	# Command queues are advanced only from the authoritative server tick.
	for unit in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit):
			continue
		if not (unit is CharacterBody2D):
			continue
		if "command_queue" not in unit or unit.command_queue == null:
			continue
		if unit.has_method("get_closest_hostile") and unit.command_queue.is_idle():
			var hostile = unit.get_closest_hostile()
			if hostile != null:
				unit.command_queue.enqueue(UnitActionAttack.create_focused(hostile))
				print("[COMBAT_LOG] Auto-engaging hostile for unit ", _get_uid(unit), ".")

		unit.command_queue.process_tick(unit, _tick_manager.tick_interval)

func _get_or_create_queue(unit: Node) -> CommandQueue:
	if "command_queue" in unit and unit.command_queue != null:
		_connect_queue_signals(unit.command_queue)
		return unit.command_queue

	var cq := CommandQueue.new()
	cq.setup(unit, _get_uid(unit))
	unit.command_queue = cq

	_connect_queue_signals(cq)
	return cq

func _connect_queue_signals(cq: CommandQueue) -> void:
	if not cq.action_completed.is_connected(_on_action_completed):
		cq.action_completed.connect(_on_action_completed)
	if not cq.action_failed.is_connected(_on_action_failed):
		cq.action_failed.connect(_on_action_failed)
	if not cq.queue_empty.is_connected(_on_queue_empty):
		cq.queue_empty.connect(_on_queue_empty)

func _on_action_completed(unit_id: int, action_data: Dictionary) -> void:
	task_completed.emit(unit_id, action_data)
	if action_data.get("type", "") == "HARVEST":
		var state = _chop_return_state.get(unit_id, {})
		if not state.is_empty():
			state["state"] = "RETURNING"
			_chop_return_state[unit_id] = state

func _on_action_failed(unit_id: int, action_data: Dictionary) -> void:
	task_failed.emit(unit_id, action_data)

func _on_queue_empty(unit_id: int) -> void:
	unit_idled.emit(unit_id)
	if _chop_return_state.has(unit_id):
		_chop_return_state.erase(unit_id)

func _validate_ownership(unit: Node, requesting_player_id: int, requesting_peer_id: int = -1) -> bool:
	var owner := int(unit.get("player_id")) if unit.get("player_id") != null else 0
	if requesting_player_id >= 0 and requesting_player_id != owner:
		push_warning("[OWNERSHIP_ERR] Unit %d belongs to player %d, rejected request from player %d" % [_get_uid(unit), owner, requesting_player_id])
		return false
	var owner_peer := int(unit.get("owner_peer_id")) if unit.get("owner_peer_id") != null else -1
	if requesting_peer_id >= 0 and owner_peer >= 0 and requesting_peer_id != owner_peer:
		push_warning("[OWNERSHIP_ERR] Unit %d belongs to peer %d, rejected request from peer %d" % [_get_uid(unit), owner_peer, requesting_peer_id])
		return false
	return true

func _find_unit(unit_id: int) -> Node:
	for unit in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(unit) and _get_uid(unit) == unit_id:
			return unit
	return null

func _find_resource(resource_id: int) -> Node:
	for resource in get_tree().get_nodes_in_group("resources"):
		if is_instance_valid(resource) and _get_uid(resource) == resource_id:
			return resource
	return null

func _find_entity(entity_id: int) -> Node:
	var node = _find_unit(entity_id)
	if node != null:
		return node
	node = _find_resource(entity_id)
	if node != null:
		return node
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and _get_uid(building) == entity_id:
			return building
	return null

func _find_closest_barracks(origin: Vector2) -> Node:
	var closest: Node = null
	var best := INF
	for b in get_tree().get_nodes_in_group("barracks"):
		if not is_instance_valid(b):
			continue
		var d := origin.distance_to(b.global_position)
		if d < best:
			best = d
			closest = b
	return closest

func _emit_command(action_type: String, unit_id: int, payload: Dictionary) -> void:
	command_validated.emit({
		"player_id": _active_player_id,
		"action_type": action_type,
		"unit_id": unit_id,
		"payload": payload
	})

func _get_uid(node: Node) -> int:
	if node == null:
		return -1
	if "entity_id" in node and node.entity_id != null:
		return int(node.entity_id)
	return int(node.get_instance_id())
