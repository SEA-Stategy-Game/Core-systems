extends Node

## Authoritative server gateway. Manages the multiplayer peer, serialises world
## state, and distributes it to connected clients via RPC.
##
## NOTE: registered as an autoload, so this node enters the tree BEFORE the
## main World scene. We therefore cannot use @onready here; the World nodes
## have to be resolved lazily on first broadcast.

var units: Node = null
var objects: Node = null
var buildings: Node = null
var map_manager: Node = null

var MAX_PLAYERS: int = 32
var DEFAULT_PORT: int = 12345
var server_port: int = 12345
var queued_objects: Array[Dictionary] = []
var _crash_signal_sent := false
var _shutdown_reason := "Graceful shutdown"

## Returns true if the World scene is loaded and we have a Units container.
func _resolve_world_refs() -> bool:
	if units != null and is_instance_valid(units):
		return true
	units = get_node_or_null("/root/World/Units")
	objects = get_node_or_null("/root/World/NavigationRegion2D/TileMapLayer/Objects")
	buildings = get_node_or_null("/root/World/NavigationRegion2D/TileMapLayer/Houses")
	map_manager = get_node_or_null("/root/World/NavigationRegion2D/TileMapLayer")
	return units != null

func _ready():
	# Disable automatic quitting. We will handle it manually in _notification
	# to ensure we can send a final status update to the backend.
	get_tree().set_auto_accept_quit(false)
	print("[INFO] Manual shutdown handler enabled (auto_accept_quit = false).")

	var env_max_players = OS.get_environment("MAX_PLAYERS")
	if env_max_players != "" and env_max_players.is_valid_int():
		MAX_PLAYERS = env_max_players.to_int()
		
	# Get the port from command line or use default
	server_port = _get_port_from_args(DEFAULT_PORT)
	_start_server(server_port)
	return

## Initialises the ENet server on the received port with a maximum of 32 clients.
## Connects the peer_connected signal to track incoming connections.
func _start_server(port: int): 
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	print("Creating server on port:", port)

	if error != OK:
		var error_msg = error_string(error)
		printerr("FATAL ERROR: Could not create server. Err: ", error_string(error))
		_shutdown_reason = "Server creation failed: %s" % error_msg
		get_tree().quit() # Closes the game, _exit_tree will send the final status
		return # Prevents the rest of the function from running

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.") or ip.begins_with("10."):
			print("Server started, hosting on: ", ip)

## Called when a new client connects. Logs the peer ID.
func _on_peer_connected(id: int):
	print("Client connected: ", id)
	
@rpc("any_peer", "call_remote", "reliable")
func on_player_registered(player_uuid: String) -> void:
	var peer_id = multiplayer.get_remote_sender_id()

	# Reject new players if the game room is already full.
	if PlayerManager.is_new_player(player_uuid) and PlayerManager.player_uuid_to_local_id.size() >= MAX_PLAYERS:
		print("[INFO] Player connection rejected: room is full. UUID=", player_uuid, " Peer=", peer_id)
		rpc_id(peer_id, "connection_rejected", "Game room is full.")
		return

	var new_player = PlayerManager.is_new_player(player_uuid)
	var local_id = PlayerManager.get_or_create_local_id(player_uuid)
	
	PlayerManager.connected_players[peer_id] = {
		"peer_id": peer_id,
		"local_id": local_id,
		"player_uuid": player_uuid,
		"connected_at": Time.get_unix_time_from_system()
	}
	print("Player registered: UUID=", player_uuid, " LocalID=", local_id, " Peer=", peer_id)

	if new_player:
		var gateway = get_node_or_null("/root/ActionGateway")
		if gateway:
			gateway.spawn_initial_unit(local_id)
			
		# After the first player joins, emits a signal that marks the room as running
		if PlayerManager.player_uuid_to_local_id.size() == 1:
			GlobalSignals.game_room_running.emit()
	
	
	rpc_id(peer_id, "receive_player_registration", local_id, Game.game_room_id)
	GameRoomManager.join_player_to_room(Game.game_room_id, player_uuid)


## Called when a client disconnects
func _on_peer_disconnected(id: int):
	if PlayerManager.connected_players.has(id):
		var p_id = PlayerManager.connected_players[id]['player_uuid']
		print("Player ", p_id, " (Peer ", id, ") disconnected.")
		PlayerManager.connected_players.erase(id) # Remove from manager
	else:
		print("Unregistered peer ", id, " disconnected.")

#

# -----------------------------------------------------------------------
# AI Planning Group -- server-side RPC entry points
# -----------------------------------------------------------------------
# These run on the server only.  An AI peer (the planning group's process)
# connects to port 12345 and calls rpc_id(1, "<name>", ...).  Each method
# forwards into the local ActionGateway autoload, which validates ownership
# and enqueues IUnitAction objects on the relevant CommandQueue.

## Push a JSON-style "Big Plan" produced by the AI planner.
## Expected dict shape: see ActionGateway.execute_plan().
@rpc("any_peer", "call_remote", "reliable")
func ai_execute_plan(plan: Dictionary) -> void:
	var gw = get_node_or_null("/root/ActionGateway")
	if gw == null:
		push_error("Server.ai_execute_plan: ActionGateway not loaded.")
		return
	gw.execute_plan(plan)

## Move-to-position.  pid = requesting player.
@rpc("any_peer", "call_remote", "reliable")
func ai_move_unit(unit_id: int, x: float, y: float, pid: int) -> void:
	var gw = get_node_or_null("/root/ActionGateway")
	if gw == null: return
	gw.move_unit(unit_id, Vector2(x, y), pid)

## Attack-move: walk to a destination, auto-engage hostiles encountered.
@rpc("any_peer", "call_remote", "reliable")
func ai_attack_move(unit_id: int, x: float, y: float, pid: int) -> void:
	var gw = get_node_or_null("/root/ActionGateway")
	if gw == null: return
	gw.attack_move(unit_id, Vector2(x, y), pid)

## Chop a specific tree by entity_id.
@rpc("any_peer", "call_remote", "reliable")
func ai_chop_tree(unit_id: int, tree_id: int, pid: int) -> void:
	var gw = get_node_or_null("/root/ActionGateway")
	if gw == null: return
	gw.go_chop_tree(unit_id, tree_id, pid)

## ID-free: chop whichever tree is closest to the unit.
@rpc("any_peer", "call_remote", "reliable")
func ai_chop_nearest_tree(unit_id: int, pid: int) -> void:
	var gw = get_node_or_null("/root/ActionGateway")
	if gw == null: return
	gw.go_chop_nearest_tree(unit_id, pid)

## Mine a specific stone by entity_id.
@rpc("any_peer", "call_remote", "reliable")
func ai_mine_stone(unit_id: int, stone_id: int, pid: int) -> void:
	var gw = get_node_or_null("/root/ActionGateway")
	if gw == null: return
	gw.go_mine_stone(unit_id, stone_id, pid)

## ID-free: mine the closest stone to the unit.
@rpc("any_peer", "call_remote", "reliable")
func ai_mine_nearest_stone(unit_id: int, pid: int) -> void:
	var gw = get_node_or_null("/root/ActionGateway")
	if gw == null: return
	gw.go_mine_nearest_stone(unit_id, pid)

## Attack a specific target by entity_id.
@rpc("any_peer", "call_remote", "reliable")
func ai_attack_target(unit_id: int, target_id: int, pid: int) -> void:
	var gw = get_node_or_null("/root/ActionGateway")
	if gw == null: return
	gw.attack_target(unit_id, target_id, pid)

## ID-free: attack whatever hostile is nearest.
@rpc("any_peer", "call_remote", "reliable")
func ai_attack_nearest(unit_id: int, pid: int) -> void:
	var gw = get_node_or_null("/root/ActionGateway")
	if gw == null: return
	gw.attack_nearest_enemy(unit_id, pid)

## Construct a building.  scene_path e.g. "res://Houses/Barracks.tscn".
@rpc("any_peer", "call_remote", "reliable")
func ai_construct(unit_id: int, scene_path: String, x: float, y: float,
		duration: float, pid: int) -> void:
	var gw = get_node_or_null("/root/ActionGateway")
	if gw == null: return
	gw.go_construct(unit_id, scene_path, Vector2(x, y), duration, pid)

## Composite: chop nearest tree then return to base and idle.
@rpc("any_peer", "call_remote", "reliable")
func ai_chop_nearest_and_return(unit_id: int, pid: int) -> void:
	var gw = get_node_or_null("/root/ActionGateway")
	if gw == null: return
	gw.go_chop_nearest_tree_and_return(unit_id, pid)

## AoE explosion at a world position.  Linear-falloff damage.
@rpc("any_peer", "call_remote", "reliable")
func ai_explode_at(unit_id: int, x: float, y: float,
		radius: float, damage: int, pid: int) -> void:
	var gw = get_node_or_null("/root/ActionGateway")
	if gw == null: return
	gw.explode_at(unit_id, Vector2(x, y), radius, damage, pid)

## Register a reactive behavior plan (predicate -> action) on a unit.
## `rules` is Array[Dictionary]: { "when": String, "do": String,
##                                 "priority": int, "args": Dictionary }
## Pass an empty array to clear.
@rpc("any_peer", "call_remote", "reliable")
func ai_set_behavior(unit_id: int, rules: Array, pid: int) -> void:
	var gw = get_node_or_null("/root/ActionGateway")
	if gw == null: return
	gw.set_behavior_plan(unit_id, rules, pid)

@rpc("any_peer", "call_remote", "reliable")
func ai_clear_behavior(unit_id: int, pid: int) -> void:
	var gw = get_node_or_null("/root/ActionGateway")
	if gw == null: return
	gw.clear_behavior_plan(unit_id, pid)

# -----------------------------------------------------------------------
# Server functions
# -----------------------------------------------------------------------

## Broadcasts a dynamic state update to all connected peers.
## [param state] A dictionary containing the current dynamic world state.
func broadcast_state(tick: int) -> void:
	if multiplayer.multiplayer_peer == null:
		return  # No server running yet (e.g. solo play).
	var peers = multiplayer.get_peers()
	if peers.is_empty():
		return
	if not _resolve_world_refs():
		return  # World not loaded yet.

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
	if not _resolve_world_refs():
		return
	print("Static state requested")
	var requesting_peer = multiplayer.get_remote_sender_id()
	var state = build_entire_state()
	var bytes = JSON.stringify(state).to_utf8_buffer()
	var compressed = bytes.compress(FileAccess.COMPRESSION_GZIP)
	print("Pushing compressed static state to peer: ", requesting_peer)
	rpc_id(requesting_peer, "receive_static_state", compressed)

## Builds a dictionary representing the full current world state
func build_entire_state() -> Dictionary:
	if not _resolve_world_refs():
		return {}
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
	var args = OS.get_cmdline_user_args()
	for i in range(args.size()):
		var arg = args[i]
		# Handle --port=12345
		if arg.begins_with("--port="):
			var value = arg.split("=")[1]
			if value.is_valid_int():
				return value.to_int()
		# Handle --port 12345
		elif arg == "--port":
			if i + 1 < args.size() and args[i + 1].is_valid_int():
				return args[i + 1].to_int()
	return default_port
	
# -----------------------------------------------------------------------
# Process Lifecycle Hooks
# -----------------------------------------------------------------------

func _notification(what: int) -> void:
	match what:
		# 1012 is MainLoop.NOTIFICATION_OS_SIGNAL. This handles Ctrl+C in a terminal.
		# We handle it identically to the window close request.
		1012, NOTIFICATION_WM_CLOSE_REQUEST:
			# If a quit is already requested, do nothing to prevent loops.
			if get_tree().is_quit_requested():
				return

			if what == 1012:
				_shutdown_reason = "Process interrupted by OS signal"
				print("[INFO] Received OS signal. Initiating graceful shutdown.")
			else: # NOTIFICATION_WM_CLOSE_REQUEST
				_shutdown_reason = "Window close request"
				print("[INFO] Window close request received. Initiating graceful shutdown.")
			
			# Calling quit() will trigger _exit_tree(), which is the designated
			# place for final actions before the application terminates.
			get_tree().quit()

		NOTIFICATION_CRASH:
			if _crash_signal_sent: return
			print("[FATAL] Engine crash detected. Emitting crash signal.")
			# This is a best-effort attempt as the process is unstable and _exit_tree
			# is not guaranteed to be called. We emit directly.
			GlobalSignals.game_room_crashed.emit("Engine crash")
			_crash_signal_sent = true

func _exit_tree() -> void:
	if _crash_signal_sent:
		# A hard crash signal was already sent directly from _notification.
		# We do nothing more to avoid sending conflicting shutdown reasons.
		return

	# This is the authoritative point for all controlled shutdowns (server fail,
	# Ctrl+C, window close). The blocking HTTP call in the connected signal
	# handler will complete before the application finally terminates.
	print("[INFO] Server shutting down. Reason: ", _shutdown_reason)
	GlobalSignals.game_room_crashed.emit(_shutdown_reason)

# -----------------------------------------------------------------------
# Client RPC stubs
# These functions are never executed on the server. They exist solely so
# Godot can compute a matching RPC checksum between client and server.
# -----------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable")
func receive_state(data: PackedByteArray):
	pass

## Stub: called by the client to request the full static world state.
@rpc("authority", "call_remote", "reliable")
func request_static_state() -> void:
	pass

## Stub: receives the compressed static world state from the server.
@rpc("authority", "call_remote", "unreliable")
func receive_static_state(data: PackedByteArray):
	pass

@rpc("authority", "call_remote", "reliable")
func receive_player_registration(player_local_id: int, game_room_id: String) -> void:
	pass
	
@rpc("authority", "call_remote", "reliable")
func register_player(player_uuid: String) -> void:
	pass
