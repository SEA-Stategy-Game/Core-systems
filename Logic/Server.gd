extends Node

## Authoritative server gateway. Manages the multiplayer peer, serialises world
## state, and distributes it to connected clients via RPC.

@onready var units = get_node("/root/World/Units")     
@onready var objects = get_node("/root/World/NavigationRegion2D/TileMapLayer/Objects")  
@onready var buildings = get_node("/root/World/NavigationRegion2D/TileMapLayer/Houses") 
@onready var map_manager = get_node("/root/World/NavigationRegion2D/TileMapLayer") 

var MAX_PLAYERS: int = 32
var DEFAULT_PORT: int = 12345
var queued_objects: Array[Dictionary] = []

func _ready():
	# Get the port from command line or use default
	var port = _get_port_from_args(DEFAULT_PORT)
	_start_server(port)
	return

## Initialises the ENet server on the received port with a maximum of 32 clients.
## Connects the peer_connected signal to track incoming connections.
func _start_server(port: int): 
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		var error_msg = error_string(error)
		printerr("FATAL ERROR: Could not create server. Err: ", error_string(error))
		get_tree().quit() # Closes the game if server can't be created
		return # Prevents the rest of the function from running

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.") or ip.begins_with("10."):
			print("Server started, hosting on: ", ip)

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
func broadcast_state(tick: int) -> void:
	var peers = multiplayer.get_peers()
	print("Broadcasting to peers: ", peers)
	
	# TODO:
	# Expand the state to also include map-data
	# Create unit paths:
	var state = {
		"current_tick" : tick,
		# Always send all units since the majority are likely to be dynamic 
		"units" : units.get_children().map(func(x): return build_dynamic_unit(x)),
		# For objects, we only send objects that are modified since there are a lot of these and they are likely to be mostly static 
		"modified_objects" : queued_objects
	}
	queued_objects = []
	#print("Dynamic state: ", state)
	var bytes = JSON.stringify(state).to_utf8_buffer()
	var compressed = bytes.compress(FileAccess.COMPRESSION_GZIP)
	rpc("receive_state", compressed)

func build_dynamic_unit(unit):
	return {
		"meta_values" : serialize_core_state_variables(unit),
		"path" : unit.get_navigation_path_segment(8),
		"speed" : unit.speed #.get_local_movement_speed()
	} 

# Signal called from objects when they are modified
# Should maybe add TTL in object to broadcast a few times. This requires idempotency from Interface
func _on_ressource_modified(object):
	queued_objects.append({
		"meta_values" : serialize_core_state_variables(object),
		"destroyed" : object.amount == 0,
		"amount_left" : object.amount
	})

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
		"objects" : objects.get_children().map(func(x): return serialize_object(x)),
		"map"	  : map_manager.game_map.get_all_tiles().map(func(x): return serialize_map_tile(x))
	}

## Serialises the core properties shared by all entities.
func serialize_core_state_variables(entity: Node) -> Dictionary:
	return {
		"entity_id"  : entity.entity_id,
		"max_health" : entity.max_health,
		"player_id"  : entity.player_id,
		"position"   : entity.global_position
	}

## Serialises a map-tile
func serialize_map_tile(tile) -> Dictionary:
	return {
		"x" : tile.x,
		"y" : tile.y,
		"terrain_type" : tile.terrain
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


## Helper function to parse command line arguments
func _get_port_from_args(default_port: int) -> int:
	var args = OS.get_cmdline_args()
	for arg in args:
		if arg.begins_with("--port="):
			var value = arg.split("=")[1]
			if value.is_valid_int():
				return value.to_int()
	return default_port
