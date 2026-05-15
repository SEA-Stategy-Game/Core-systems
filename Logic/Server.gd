extends Node

const PORT := 24567
const MAX_CLIENTS := 16

signal client_connected(peer_id: int)
signal client_disconnected(peer_id: int)

var last_full_state: Dictionary = {}
var connected_peers: Array[int] = []

@export var auto_start_server := true

func _ready() -> void:
	if OS.has_feature("dedicated_server"):
		start_server()
		return

	if auto_start_server and "--server" in OS.get_cmdline_args():
		start_server()

func start_server() -> void:
	_start_server()

func _start_server() -> void:
	if multiplayer.multiplayer_peer != null:
		return

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)

	if err != OK:
		push_error("[NET_ERR] Failed to create ENet server. Error: %s" % err)
		return

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	var tick_manager = get_node_or_null("/root/TickManager")
	if tick_manager != null and not tick_manager.authoritative_state_ready.is_connected(_on_authoritative_state_ready):
		tick_manager.authoritative_state_ready.connect(_on_authoritative_state_ready)

	print("[NET_LOG] Dedicated multiplayer server started on port ", PORT)

func connect_to_server(address: String = "127.0.0.1") -> void:
	if multiplayer.multiplayer_peer != null:
		return

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)

	if err != OK:
		push_error("[NET_ERR] Failed to connect to server. Error: %s" % err)
		return

	multiplayer.multiplayer_peer = peer
	print("[NET_LOG] Connecting to multiplayer server at ", address)

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

	print("[NET_SYNC] Applying tick ", state["tick"])
	_sync_units(state.get("units", []))
	_sync_resources(state.get("resources", []))
	_sync_buildings(state.get("buildings", []))

func _sync_units(units: Array) -> void:
	var unit_nodes = get_tree().get_nodes_in_group("units")
	for incoming in units:
		var target = null
		for unit in unit_nodes:
			if unit.get("entity_id") == incoming["entity_id"]:
				target = unit
				break
		if target == null:
			continue
		target.global_position = Vector2(incoming["position"]["x"], incoming["position"]["y"])
		target.current_health = incoming["health"]

func _sync_resources(resources: Array) -> void:
	for incoming in resources:
		for resource in get_tree().get_nodes_in_group("resources"):
			if resource.get("entity_id") == incoming["entity_id"]:
				resource.amount = incoming["amount"]
				resource.global_position = Vector2(incoming["position"]["x"], incoming["position"]["y"])
				break

func _sync_buildings(buildings: Array) -> void:
	for incoming in buildings:
		for building in get_tree().get_nodes_in_group("buildings"):
			if building.get("entity_id") == incoming["entity_id"]:
				building.global_position = Vector2(incoming["position"]["x"], incoming["position"]["y"])
				building.current_health = incoming["health"]
				break
