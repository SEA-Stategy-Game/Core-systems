extends Node
class_name ShowcaseNetworkBridge

signal connected
signal disconnected
signal command_synced(command: Dictionary, tick: int)
signal state_snapshot_received(snapshot: Dictionary)

@export var latency_ms: int = 0
@export var enable_state_snapshots: bool = true
@export var snapshot_interval_ticks: int = 10

var action_gateway: ActionGateway
var tick_manager: TickManager
var player_id: int = -1
var is_server: bool = false
var is_connected: bool = false
var pending_commands: Array = []
var command_history: Array = []

func initialize_server(p_player_id: int) -> void:
	print("[NET_BRIDGE] Server: Initializing on player %d..." % p_player_id)
	player_id = p_player_id
	is_server = true
	is_connected = true
	action_gateway = ActionGateway
	tick_manager = TickManager

	if action_gateway != null and not action_gateway.command_validated.is_connected(_on_command_validated):
		action_gateway.command_validated.connect(_on_command_validated)
	if tick_manager != null and not tick_manager.tick.is_connected(_on_tick):
		tick_manager.tick.connect(_on_tick)

	print("[NET_BRIDGE] Server: Ready to receive commands")

func initialize_client(p_player_id: int, _server_address: String = "127.0.0.1") -> void:
	print("[NET_BRIDGE] Client %d: Initializing..." % p_player_id)
	player_id = p_player_id
	is_server = false
	is_connected = true
	action_gateway = ActionGateway
	tick_manager = TickManager

	if action_gateway != null and not action_gateway.command_validated.is_connected(_on_command_validated):
		action_gateway.command_validated.connect(_on_command_validated)
	if tick_manager != null and not tick_manager.tick.is_connected(_on_tick):
		tick_manager.tick.connect(_on_tick)

	connected.emit()
	print("[NET_BRIDGE] Client %d: Connected" % p_player_id)

func _on_command_validated(command: Dictionary) -> void:
	if not is_connected:
		return

	var networked_cmd := command.duplicate(true)
	networked_cmd["source_player"] = command.get("player_id", -1)
	networked_cmd["network_tick"] = tick_manager.current_tick if tick_manager != null else 0
	networked_cmd["client_timestamp"] = Time.get_ticks_msec()
	pending_commands.append(networked_cmd)

func _on_tick(tick: int) -> void:
	if pending_commands.is_empty():
		if enable_state_snapshots and is_server and tick % snapshot_interval_ticks == 0:
			var snapshot := request_state_snapshot()
			state_snapshot_received.emit(snapshot)
		return

	var batch := {
		"tick": tick,
		"player_id": player_id,
		"commands": pending_commands.duplicate(true),
		"timestamp": Time.get_ticks_msec()
	}

	pending_commands.clear()
	command_history.append(batch)
	if command_history.size() > 1000:
		command_history.pop_front()

	if is_server:
		_rpc_receive_command_batch(batch)
	else:
		var server_instance := _find_server_instance()
		if server_instance != null and server_instance.networking != null:
			server_instance.networking._rpc_receive_command_batch(batch)

func _rpc_receive_command_batch(batch: Dictionary) -> void:
	if not is_server:
		return

	for cmd in batch.get("commands", []):
		command_synced.emit(cmd, batch.get("tick", -1))

	if enable_state_snapshots and batch.get("tick", -1) % snapshot_interval_ticks == 0:
		var snapshot := request_state_snapshot()
		state_snapshot_received.emit(snapshot)

func request_state_snapshot() -> Dictionary:
	var sense := action_gateway.sense() if action_gateway != null else null
	var units := sense.get_all_units() if sense != null else []
	var resources := sense.get_all_resources() if sense != null else []
	var buildings := sense.get_all_buildings() if sense != null else []

	var snapshot := {
		"tick": tick_manager.current_tick if tick_manager != null else -1,
		"player_id": player_id,
		"unit_count": units.size(),
		"resource_count": resources.size(),
		"building_count": buildings.size(),
		"resources": {
			"wood": Game.Wood,
			"stone": Game.Stone
		},
		"units": _serialize_units(units),
		"resources_state": _serialize_resources(resources),
		"buildings_state": _serialize_buildings(buildings)
	}
	snapshot["state_hash"] = _hash_snapshot(snapshot)
	return snapshot

func _serialize_units(units: Array) -> Array:
	var serialized: Array = []
	for unit in units:
		serialized.append({
			"id": unit.get("id", -1),
			"position": unit.get("position", {"x": 0, "y": 0}),
			"player_id": unit.get("player_id", -1),
			"health": unit.get("health", 0),
			"is_idle": unit.get("is_idle", true)
		})
	return serialized

func _serialize_resources(resources: Array) -> Array:
	var serialized: Array = []
	for res in resources:
		serialized.append({
			"id": res.get("id", -1),
			"type": res.get("type", "UNKNOWN"),
			"amount": res.get("amount", 0),
			"position": res.get("position", {"x": 0, "y": 0})
		})
	return serialized

func _serialize_buildings(buildings: Array) -> Array:
	var serialized: Array = []
	for bld in buildings:
		serialized.append({
			"id": bld.get("id", -1),
			"player_id": bld.get("player_id", -1),
			"health": bld.get("health", 0),
			"position": bld.get("position", {"x": 0, "y": 0})
		})
	return serialized

func _hash_snapshot(snapshot: Dictionary) -> int:
	var parts: Array[String] = []
	parts.append(str(snapshot.get("tick", -1)))
	parts.append(str(snapshot.get("unit_count", 0)))
	parts.append(str(snapshot.get("resource_count", 0)))
	parts.append(str(snapshot.get("building_count", 0)))
	parts.append(str(snapshot.get("resources", {})))

	for unit in snapshot.get("units", []):
		var pos = unit.get("position", {"x": 0, "y": 0})
		parts.append("%s:%s:%s:%s" % [
			unit.get("id", -1),
			int(pos.get("x", 0)),
			int(pos.get("y", 0)),
			unit.get("health", 0)
		])

	for res in snapshot.get("resources_state", []):
		parts.append("%s:%s:%s" % [
			res.get("id", -1),
			res.get("type", "UNKNOWN"),
			res.get("amount", 0)
		])

	return hash("|".join(parts))

func get_command_history() -> Array:
	return command_history.duplicate(true)

func get_debug_info() -> Dictionary:
	return {
		"player_id": player_id,
		"is_server": is_server,
		"is_connected": is_connected,
		"pending_commands": pending_commands.size(),
		"command_history_size": command_history.size(),
		"latency_ms": latency_ms
	}

func _find_server_instance() -> ShowcaseInstance:
	for child in get_tree().root.get_children():
		if child is ShowcaseInstance and child.is_server:
			return child
	return null
