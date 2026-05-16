extends Node

signal client_connected(peer_id: int)
signal client_disconnected(peer_id: int)
signal authoritative_state_applied(state: Dictionary)

@export var auto_start_server := false
@export var default_port: int = 24567
@export var max_clients: int = 16

var port: int = 24567
var last_full_state: Dictionary = {}
var last_state_signature: String = ""
var connected_peers: Array[int] = []

func _ready() -> void:
	port = default_port

	if OS.has_feature("dedicated_server"):
		start_server()
		return

	if auto_start_server and "--server" in OS.get_cmdline_args():
		start_server()

func set_port(value: int) -> void:
	port = clampi(value, 1, 65535)

func get_port() -> int:
	return port

func start_server(port_override: int = -1) -> void:
	if port_override > 0:
		set_port(port_override)
	_start_server()

func _start_server() -> void:
	if multiplayer.multiplayer_peer != null:
		return

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_clients)
	if err != OK:
		push_error("[NET_ERR] Failed to create ENet server. Error: %s" % err)
		return

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	var tick_manager = get_node_or_null("/root/TickManager")
	if tick_manager != null and not tick_manager.authoritative_state_ready.is_connected(_on_authoritative_state_ready):
		tick_manager.authoritative_state_ready.connect(_on_authoritative_state_ready)

	print("[NET_LOG] Multiplayer server started on port ", port)

func connect_to_server(address: String = "127.0.0.1", port_override: int = -1) -> void:
	if port_override > 0:
		set_port(port_override)

	if multiplayer.multiplayer_peer != null:
		return

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("[NET_ERR] Failed to connect to server. Error: %s" % err)
		return

	multiplayer.multiplayer_peer = peer
	print("[NET_LOG] Connecting to multiplayer server at %s:%d" % [address, port])

func disconnect_network() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	multiplayer.multiplayer_peer = null
	connected_peers.clear()
	last_full_state = {}
	last_state_signature = ""
	print("[NET_LOG] Multiplayer peer disconnected.")

func get_last_state() -> Dictionary:
	return last_full_state.duplicate(true)

func get_last_state_signature() -> String:
	return last_state_signature

func get_last_tick() -> int:
	return int(last_full_state.get("tick", -1))

func get_connection_mode() -> String:
	if multiplayer.multiplayer_peer == null:
		return "offline"
	return "host" if multiplayer.is_server() else "client"

func get_peer_summary() -> Dictionary:
	var peer_id := 0
	var peer := multiplayer.multiplayer_peer
	var peer_active := peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	if peer_active:
		peer_id = multiplayer.get_unique_id()

	return {
		"mode": get_connection_mode(),
		"local_peer_id": peer_id,
		"connected_peers": connected_peers.duplicate(),
		"port": port
	}

func submit_showcase_command(command: Dictionary) -> bool:
	if command.is_empty():
		return false

	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		return _execute_showcase_command(command)

	rpc_id(1, "request_showcase_command", command)
	return true

@rpc("any_peer", "call_remote", "reliable")
func request_showcase_command(command: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_execute_showcase_command(command)

func _execute_showcase_command(command: Dictionary) -> bool:
	var action_type := String(command.get("action", ""))
	var unit_id := int(command.get("unit_id", -1))
	var player_id := int(command.get("player_id", -1))

	var gateway = get_node_or_null("/root/ActionGateway")
	if gateway == null:
		push_error("[NET_ERR] ActionGateway singleton not found.")
		return false

	match action_type:
		"MOVE":
			var pos_dict: Dictionary = command.get("target", {})
			return gateway.move_unit(unit_id, Vector2(float(pos_dict.get("x", 0.0)), float(pos_dict.get("y", 0.0))), player_id)
		"CHOP_AND_RETURN":
			return gateway.go_chop_tree_and_return(unit_id, int(command.get("target_id", -1)), player_id)
		"ATTACK":
			return gateway.attack_target(unit_id, int(command.get("target_id", -1)), player_id)
		"COLLECT":
			return gateway.go_mine_stone(unit_id, int(command.get("target_id", -1)), player_id)
		_:
			push_warning("[NET_ERR] Unknown showcase action: %s" % action_type)
			return false

func _on_peer_connected(id: int) -> void:
	connected_peers.append(id)
	client_connected.emit(id)
	print("[NET_LOG] Peer connected: ", id)
	if not last_full_state.is_empty():
		rpc_id(id, "receive_full_state", last_full_state)

func _on_peer_disconnected(id: int) -> void:
	connected_peers.erase(id)
	client_disconnected.emit(id)
	print("[NET_LOG] Peer disconnected: ", id)

func _on_authoritative_state_ready(state: Dictionary) -> void:
	last_full_state = state.duplicate(true)
	last_state_signature = String(state.get("state_signature", ""))
	authoritative_state_applied.emit(last_full_state)
	if connected_peers.is_empty():
		return
	rpc("receive_tick_state", state)

@rpc("authority", "call_remote", "reliable")
func receive_full_state(state: Dictionary) -> void:
	print("[NET_SYNC] Received full synchronization state.")
	_apply_state(state)

@rpc("authority", "call_remote", "unreliable")
func receive_tick_state(state: Dictionary) -> void:
	_apply_state(state)

func _apply_state(state: Dictionary) -> void:
	if not state.has("tick"):
		push_error("[NET_SYNC_ERR] Incoming state missing tick field.")
		return

	last_full_state = state.duplicate(true)
	last_state_signature = String(state.get("state_signature", ""))
	print("[NET_SYNC] Applying tick ", state["tick"])

	_sync_units(state.get("units", []))
	_sync_resources(state.get("resources", []))
	_sync_buildings(state.get("buildings", []))

	authoritative_state_applied.emit(last_full_state)

func _sync_units(units: Array) -> void:
	var unit_nodes = get_tree().get_nodes_in_group("units")
	for incoming in units:
		var target = null
		for unit in unit_nodes:
			if not is_instance_valid(unit):
				continue
			if unit.get("entity_id") == incoming["entity_id"]:
				target = unit
				break
		if target == null:
			continue
		target.global_position = Vector2(incoming["position"]["x"], incoming["position"]["y"])
		if target.get("current_health") != null:
			target.current_health = int(incoming.get("health", target.current_health))
		if target.get("is_idle") != null:
			target.is_idle = bool(incoming.get("idle", target.is_idle))

func _sync_resources(resources: Array) -> void:
	var incoming_ids := {}
	for incoming in resources:
		var incoming_id := int(incoming.get("entity_id", -1))
		incoming_ids[incoming_id] = true
		for resource in get_tree().get_nodes_in_group("resources"):
			if not is_instance_valid(resource):
				continue
			var resource_entity_id = resource.get("entity_id")
			if resource_entity_id != null and int(resource_entity_id) == incoming_id:
				resource.amount = int(incoming.get("amount", resource.amount))
				resource.global_position = Vector2(incoming["position"]["x"], incoming["position"]["y"])
				break

	for resource in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(resource):
			continue
		var resource_entity_id = resource.get("entity_id")
		var resource_id := int(resource_entity_id) if resource_entity_id != null else -1
		if incoming_ids.has(resource_id):
			continue
		resource.queue_free()

func _sync_buildings(buildings: Array) -> void:
	for incoming in buildings:
		for building in get_tree().get_nodes_in_group("buildings"):
			if not is_instance_valid(building):
				continue
			if building.get("entity_id") == incoming["entity_id"]:
				building.global_position = Vector2(incoming["position"]["x"], incoming["position"]["y"])
				building.current_health = int(incoming.get("health", building.current_health))
				break
