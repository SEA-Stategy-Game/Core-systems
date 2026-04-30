extends Node

## Authoritative server gateway. Manages the multiplayer peer, serialises world
## state, and distributes it to connected clients via RPC.

@onready var units = get_node("/root/World/Units")     
@onready var objects = get_node("/root/World/Objects")  
@onready var buildings = get_node("/root/World/Houses") 

## Initialises the ENet server on port 12345 with a maximum of 32 clients.
## Connects the peer_connected signal to track incoming connections.
func _ready():
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(12345, 32)
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.") or ip.begins_with("10."):
			print("Server started, hosting on: ", ip)
	print("My node path: ", get_path())

## Called when a new client connects. Logs the peer ID.
func _on_peer_connected(id: int):
	print("Client connected: ", id)

# -----------------------------------------------------------------------
# Client RPC stubs
# These functions are never executed on the server. They exist solely so
# Godot can compute a matching RPC checksum between client and server.
# -----------------------------------------------------------------------

## Stub: called by the client to request the full static world state.
@rpc("any_peer", "call_remote", "reliable")
func request_static_state() -> void:
	pass

## Stub: receives a dynamic state delta broadcast from the server.
@rpc("any_peer", "call_remote", "unreliable")
func receive_state(state: Dictionary):
	pass

## Stub: receives the compressed static world state from the server.
@rpc("any_peer", "call_remote", "unreliable")
func receive_static_state(state: Dictionary):
	pass

# -----------------------------------------------------------------------
# Server functions
# -----------------------------------------------------------------------

## Broadcasts a dynamic state update to all connected peers.
## [param state] A dictionary containing the current dynamic world state.
func broadcast_state(state: Dictionary) -> void:
	var peers = multiplayer.get_peers()
	print("Broadcasting to peers: ", peers)
	
	# TODO:
	# Expand the state to not only include the current tick but the actual dynamic state too
	
	rpc("receive_state", state)

## Handles a client request for the full static world state.
## Serialises, compresses, and sends the state only to the requesting peer.
## RPC is reliable to ensure the full state arrives intact.
@rpc("any_peer", "call_remote", "reliable")
func on_static_state_requested() -> void:
	print("Static state requested")
	var requesting_peer = multiplayer.get_remote_sender_id()
	var state = build_entire_state()
	var bytes = JSON.stringify(state).to_utf8_buffer()
	var compressed = bytes.compress(FileAccess.COMPRESSION_GZIP)
	print("Pushing compressed static state to peer: ", requesting_peer)
	rpc_id(requesting_peer, "receive_static_state", compressed)

## Builds a dictionary representing the full current world state
func build_entire_state() -> Dictionary:
	return {
		"units"   : units.get_children().map(func(x): return serialize_unit(x)),
		"objects" : objects.get_children().map(func(x): return serialize_object(x))
	}

## Serialises the core properties shared by all entities.
func serialize_core_state_variables(entity: Node) -> Dictionary:
	return {
		"entity_id"  : entity.entity_id,
		"max_health" : entity.max_health,
		"player_id"  : entity.player_id,
		"position"   : entity.position
	}

## Serialises a unit node into a transmittable dictionary
func serialize_unit(unit: Node) -> Dictionary:
	return {
		"meta_values"      : serialize_core_state_variables(unit),
		"attack_damage"    : unit.attack_damage,
		"attack_cooldown"  : unit.attack_cooldown,
		"current_health"   : unit.current_health
	}

## Serialises a world object node into a transmittable dictionary
func serialize_object(object: Node) -> Dictionary:
	return {
		"meta_values"   : serialize_core_state_variables(object),
		"resource_name" : object.resource_name,
		"amount"        : object.amount
	}

## Serialises a building node into a transmittable dictionary.
func serialize_buildings(building: Node) -> Dictionary:
	return {
		"meta_values"   : serialize_core_state_variables(building),
		"resource_name" : building.resource_name,
		"amount"        : building.amount,
		"current_health": building.current_health
	}
