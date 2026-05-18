extends Node

signal client_connected(peer_id: int)
signal client_disconnected(peer_id: int)
signal authoritative_state_applied(state: Dictionary)

const UNIT_SCENE := preload("res://Entities/Units/unit.tscn")
const DEFAULT_UNIT_SPAWN_POSITIONS := [
    Vector2(433, 499),
    Vector2(520, 499),
    Vector2(433, 580),
    Vector2(520, 580),
    Vector2(346, 499),
    Vector2(607, 499)
]

@export var auto_start_server := false
@export var default_port: int = 24567
@export var max_clients: int = 16
@export var full_state_sync_interval_ticks: int = 20
@export var debug_log_unit_positions: bool = true
@export var debug_log_unit_positions_once: bool = false

var port: int = 24567
var last_full_state: Dictionary = {}
var last_state_signature: String = ""
var connected_peers: Array[int] = []
var _player_slots_by_peer: Dictionary = {}
var _unit_ids_by_peer: Dictionary = {}
var _next_dynamic_entity_id: int = 10000

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
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

    _initialize_authoritative_world()
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
    _player_slots_by_peer.clear()
    _unit_ids_by_peer.clear()
    print("[NET_LOG] Multiplayer peer disconnected.")

func get_last_state() -> Dictionary:
    return last_full_state.duplicate(true)

func get_last_state_signature() -> String:
    return last_state_signature

func get_last_tick() -> int:
    return int(last_full_state.get("tick", -1))

func get_connection_mode() -> String:
    var peer := multiplayer.multiplayer_peer
    if peer == null:
        return "offline"
    var status := peer.get_connection_status()
    if status == MultiplayerPeer.CONNECTION_CONNECTING:
        return "connecting"
    if status != MultiplayerPeer.CONNECTION_CONNECTED:
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
        "player_slots": _player_slots_by_peer.duplicate(true),
        "owned_units": _unit_ids_by_peer.duplicate(true),
        "port": port
    }

func submit_showcase_command(command: Dictionary) -> bool:
    return submit_player_command(command)

func submit_player_command(command: Dictionary) -> bool:
    if command.is_empty():
        return false

    if multiplayer.multiplayer_peer == null or multiplayer.is_server():
        var local_peer_id := -1
        if multiplayer.multiplayer_peer != null:
            local_peer_id = multiplayer.get_unique_id()
        return _execute_player_command(command, local_peer_id)

    rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, "request_player_command", command)
    return true

@rpc("any_peer", "call_remote", "reliable")
func request_showcase_command(command: Dictionary) -> void:
    request_player_command(command)

@rpc("any_peer", "call_remote", "reliable")
func request_player_command(command: Dictionary) -> void:
    if not multiplayer.is_server():
        return
    var sender_peer_id := multiplayer.get_remote_sender_id()
    if sender_peer_id <= 0:
        sender_peer_id = multiplayer.get_unique_id()
    _execute_player_command(command, sender_peer_id)

func _execute_player_command(command: Dictionary, source_peer_id: int = -1) -> bool:
    var action_type := String(command.get("action", ""))
    var unit_id := int(command.get("unit_id", -1))
    var authorized_command := _authorize_player_command(command, source_peer_id)
    if authorized_command.is_empty():
        return false
    var player_id := int(authorized_command.get("player_id", -1))

    var gateway = get_node_or_null("/root/ActionGateway")
    if gateway == null:
        push_error("[NET_ERR] ActionGateway singleton not found.")
        return false

    match action_type:
        "MOVE":
            var pos_dict: Dictionary = authorized_command.get("target", {})
            return gateway.move_unit(unit_id, Vector2(float(pos_dict.get("x", 0.0)), float(pos_dict.get("y", 0.0))), player_id, source_peer_id)
        "CHOP_AND_RETURN":
            return gateway.go_chop_tree_and_return(unit_id, int(authorized_command.get("target_id", -1)), player_id, source_peer_id)
        "ATTACK":
            return gateway.attack_target(unit_id, int(authorized_command.get("target_id", -1)), player_id, source_peer_id)
        "COLLECT":
            return gateway.go_mine_stone(unit_id, int(authorized_command.get("target_id", -1)), player_id, source_peer_id)
        _:
            push_warning("[NET_ERR] Unknown player action: %s" % action_type)
            return false

func _authorize_player_command(command: Dictionary, source_peer_id: int) -> Dictionary:
    var authorized := command.duplicate(true)
    if multiplayer.multiplayer_peer == null:
        return authorized

    if source_peer_id < 0:
        push_warning("[OWNERSHIP_ERR] Rejected command without an authenticated peer: %s" % str(command))
        return {}
    if not _player_slots_by_peer.has(source_peer_id):
        push_warning("[OWNERSHIP_ERR] Rejected command from unregistered peer %d: %s" % [source_peer_id, str(command)])
        return {}

    var requested_unit_id := int(command.get("unit_id", -1))
    var owned_unit_id := int(_unit_ids_by_peer.get(source_peer_id, -1))

    # Allow empty/missing unit_id by mapping to the peer's owned unit.
    if requested_unit_id < 0:
        if owned_unit_id < 0:
            push_warning("[OWNERSHIP_ERR] Peer %d has no assigned unit; rejecting command: %s" % [source_peer_id, str(command)])
            return {}
        authorized["unit_id"] = owned_unit_id
    else:
        if requested_unit_id != owned_unit_id:
            push_warning("[OWNERSHIP_ERR] Peer %d attempted to control unit %d, but owns unit %d." % [source_peer_id, requested_unit_id, owned_unit_id])
            return {}

    authorized["player_id"] = int(_player_slots_by_peer[source_peer_id])
    print("[OWNERSHIP_LOG] Accepted command from peer ", source_peer_id, " for owned unit ", owned_unit_id, ".")
    return authorized

func _initialize_authoritative_world() -> void:
    if not multiplayer.is_server():
        return

    _player_slots_by_peer.clear()
    _unit_ids_by_peer.clear()
    connected_peers.clear()
    _next_dynamic_entity_id = 10000
    _clear_authoritative_player_units()

    var host_peer_id := multiplayer.get_unique_id()
    _track_peer(host_peer_id)
    _register_peer(host_peer_id)
    _spawn_unit_for_peer(host_peer_id)
    _refresh_last_full_state()

func _track_peer(peer_id: int) -> void:
    if not connected_peers.has(peer_id):
        connected_peers.append(peer_id)

func _register_peer(peer_id: int) -> int:
    if _player_slots_by_peer.has(peer_id):
        return int(_player_slots_by_peer[peer_id])

    var player_slot := _allocate_player_slot()
    _player_slots_by_peer[peer_id] = player_slot
    print("[OWNERSHIP_LOG] Peer ", peer_id, " assigned to player slot ", player_slot, ".")
    return player_slot

func _allocate_player_slot() -> int:
    var used_slots := _player_slots_by_peer.values()
    var candidate := 0
    while used_slots.has(candidate):
        candidate += 1
    return candidate

func _spawn_unit_for_peer(peer_id: int) -> Node:
    var existing_unit_id := int(_unit_ids_by_peer.get(peer_id, -1))
    if existing_unit_id >= 0:
        var existing_unit := _find_unit_node_by_entity_id(existing_unit_id)
        if existing_unit != null:
            return existing_unit
        print("[SPAWN_LOG] Peer ", peer_id, " already has assigned unit ", existing_unit_id, "; not spawning a duplicate.")
        return null

    var unit_parent := _get_units_root()
    if unit_parent == null:
        push_error("[SPAWN_ERR] World/Units node not found; unable to spawn peer unit.")
        return null

    var unit = UNIT_SCENE.instantiate()
    var player_slot := int(_player_slots_by_peer.get(peer_id, _register_peer(peer_id)))
    unit.entity_id = _allocate_dynamic_entity_id()
    unit.player_id = player_slot
    unit.owner_peer_id = peer_id
    unit.global_position = _get_spawn_position(player_slot)
    unit.name = "PlayerUnit_%d" % unit.entity_id
    unit_parent.add_child(unit)

    if unit.has_method("assign_network_owner"):
        unit.assign_network_owner(peer_id, player_slot)
    else:
        unit.owner_peer_id = peer_id
        unit.player_id = player_slot
        unit.set_multiplayer_authority(peer_id, false)

    _unit_ids_by_peer[peer_id] = int(unit.entity_id)
    print("[SPAWN_LOG] Spawned unit ", unit.entity_id, " for peer ", peer_id, " at ", unit.global_position, ".")
    return unit

func _clear_authoritative_player_units() -> void:
    for unit in get_tree().get_nodes_in_group("units"):
        if not is_instance_valid(unit) or not (unit is CharacterBody2D):
            continue
        if unit.get("owner_peer_id") == null:
            continue
        print("[SPAWN_LOG] Removing pre-existing player unit ", unit.get("entity_id"), " before authoritative spawn.")
        unit.queue_free()

func _cleanup_peer_unit(peer_id: int) -> void:
    var unit_id := int(_unit_ids_by_peer.get(peer_id, -1))
    var unit = _find_unit_node_by_entity_id(unit_id)
    if unit != null:
        print("[DESTROY_LOG] Cleaning up unit ", unit_id, " for disconnected peer ", peer_id, ".")
        unit.queue_free()
    else:
        print("[DESTROY_LOG] Disconnect cleanup found no live unit for peer ", peer_id, " (last unit ", unit_id, ").")
    _unit_ids_by_peer.erase(peer_id)

func _on_peer_connected(id: int) -> void:
    _track_peer(id)
    _register_peer(id)
    _spawn_unit_for_peer(id)
    _refresh_last_full_state()
    _broadcast_full_state()
    client_connected.emit(id)
    print("[NET_LOG] Peer connected: ", id)

func _on_peer_disconnected(id: int) -> void:
    connected_peers.erase(id)
    client_disconnected.emit(id)
    _cleanup_peer_unit(id)
    _player_slots_by_peer.erase(id)
    _refresh_last_full_state()
    _broadcast_full_state()
    print("[NET_LOG] Peer disconnected: ", id)

func _on_authoritative_state_ready(state: Dictionary) -> void:
    last_full_state = state.duplicate(true)
    last_state_signature = String(state.get("state_signature", ""))
    authoritative_state_applied.emit(last_full_state)
    if debug_log_unit_positions or debug_log_unit_positions_once:
        _debug_log_unit_positions()
        if debug_log_unit_positions_once:
            debug_log_unit_positions_once = false
    if connected_peers.is_empty():
        return
    var tick := int(state.get("tick", 0))
    if full_state_sync_interval_ticks > 0 and tick % full_state_sync_interval_ticks == 0:
        rpc("receive_full_state", state)
        return
    rpc("receive_tick_state", _build_tick_state(state))

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

    _merge_last_full_state(state)
    last_state_signature = String(last_full_state.get("state_signature", state.get("state_signature", "")))
    print("[NET_SYNC] Applying tick ", state["tick"])
    _sync_units(state.get("units", []))
    _sync_resources(state.get("resources", []))
    _sync_buildings(state.get("buildings", []))
    authoritative_state_applied.emit(last_full_state)

func _refresh_last_full_state() -> void:
    var tick_manager = get_node_or_null("/root/TickManager")
    if tick_manager == null or not tick_manager.has_method("build_authoritative_snapshot"):
        return
    last_full_state = tick_manager.build_authoritative_snapshot()
    last_state_signature = String(last_full_state.get("state_signature", ""))

func _broadcast_full_state() -> void:
    if connected_peers.is_empty() or last_full_state.is_empty():
        return
    rpc("receive_full_state", last_full_state)

func _merge_last_full_state(state: Dictionary) -> void:
    if last_full_state.is_empty() or _is_full_state_payload(state):
        last_full_state = state.duplicate(true)
        return
    last_full_state["tick"] = int(state.get("tick", last_full_state.get("tick", -1)))
    last_full_state["timestamp"] = state.get("timestamp", last_full_state.get("timestamp", 0))
    last_full_state["state_signature"] = String(state.get("state_signature", last_full_state.get("state_signature", "")))
    last_full_state["scenario"] = state.get("scenario", last_full_state.get("scenario", {}))
    last_full_state["units"] = state.get("units", [])
    last_full_state["resources"] = state.get("resources", [])
    last_full_state["buildings"] = state.get("buildings", [])

func _is_full_state_payload(state: Dictionary) -> bool:
    if String(state.get("payload_type", "")) == "tick":
        return false
    var units: Array = state.get("units", [])
    if not units.is_empty() and units[0] is Dictionary and units[0].has("player_id"):
        return true
    var resources: Array = state.get("resources", [])
    if not resources.is_empty() and resources[0] is Dictionary and resources[0].has("resource_name"):
        return true
    return false

func _build_tick_state(state: Dictionary) -> Dictionary:
    var tick_state := {
        "payload_type": "tick",
        "tick": int(state.get("tick", 0)),
        "timestamp": int(state.get("timestamp", 0)),
        "state_signature": String(state.get("state_signature", "")),
        "scenario": state.get("scenario", {}),
        "units": [],
        "resources": [],
        "buildings": []
    }

    for unit in state.get("units", []):
        var unit_snapshot: Dictionary = unit
        var position: Dictionary = unit_snapshot.get("position", {"x": 0.0, "y": 0.0})
        tick_state["units"].append({
            "entity_id": int(unit_snapshot.get("entity_id", -1)),
            "player_id": int(unit_snapshot.get("player_id", 0)),
            "owner_peer_id": int(unit_snapshot.get("owner_peer_id", -1)),
            "position": {
                "x": float(position.get("x", 0.0)),
                "y": float(position.get("y", 0.0))
            },
            "health": int(unit_snapshot.get("health", -1)),
            "idle": bool(unit_snapshot.get("idle", false)),
            "destroyed": bool(unit_snapshot.get("destroyed", false))
        })

    for resource in state.get("resources", []):
        var resource_snapshot: Dictionary = resource
        var resource_position: Dictionary = resource_snapshot.get("position", {"x": 0.0, "y": 0.0})
        tick_state["resources"].append({
            "entity_id": int(resource_snapshot.get("entity_id", -1)),
            "resource_name": String(resource_snapshot.get("resource_name", "")),
            "position": {
                "x": float(resource_position.get("x", 0.0)),
                "y": float(resource_position.get("y", 0.0))
            },
            "amount": int(resource_snapshot.get("amount", -1)),
            "health": int(resource_snapshot.get("health", -1)),
            "destroyed": bool(resource_snapshot.get("destroyed", false))
        })

    for building in state.get("buildings", []):
        var building_snapshot: Dictionary = building
        var building_position: Dictionary = building_snapshot.get("position", {"x": 0.0, "y": 0.0})
        tick_state["buildings"].append({
            "entity_id": int(building_snapshot.get("entity_id", -1)),
            "position": {
                "x": float(building_position.get("x", 0.0)),
                "y": float(building_position.get("y", 0.0))
            },
            "health": int(building_snapshot.get("health", -1))
        })

    return tick_state

func _sync_units(units: Array) -> void:
    var incoming_ids := {}
    var known_units := {}
    for unit in get_tree().get_nodes_in_group("units"):
        if not is_instance_valid(unit) or not (unit is CharacterBody2D):
            continue
        var unit_entity_id = unit.get("entity_id")
        if unit_entity_id != null:
            known_units[int(unit_entity_id)] = unit

    for incoming in units:
        var incoming_snapshot: Dictionary = incoming
        var incoming_id := int(incoming_snapshot.get("entity_id", -1))
        if bool(incoming_snapshot.get("destroyed", false)):
            var destroyed_unit = known_units.get(incoming_id, null)
            if destroyed_unit != null:
                print("[DESTROY_LOG] Removing replicated destroyed unit ", incoming_id, ".")
                destroyed_unit.queue_free()
            continue

        incoming_ids[incoming_id] = true
        var target = known_units.get(incoming_id, null)
        if target == null and _can_spawn_unit_from_snapshot(incoming_snapshot):
            target = _spawn_replicated_unit(incoming_snapshot)
            if target != null:
                known_units[incoming_id] = target
        if target == null:
            continue

        if target.has_method("sync_from_snapshot"):
            target.sync_from_snapshot(incoming_snapshot)
        else:
            target.entity_id = incoming_id
            target.player_id = int(incoming_snapshot.get("player_id", target.player_id))
            target.owner_peer_id = int(incoming_snapshot.get("owner_peer_id", target.owner_peer_id))
            if incoming_snapshot.has("position"):
                target.global_position = Vector2(
                    float(incoming_snapshot["position"].get("x", 0.0)),
                    float(incoming_snapshot["position"].get("y", 0.0))
                )
            target.current_health = int(incoming_snapshot.get("health", target.current_health))

        if target.get("is_idle") != null:
            target.is_idle = bool(incoming_snapshot.get("idle", target.is_idle))

    for unit in get_tree().get_nodes_in_group("units"):
        if not is_instance_valid(unit) or not (unit is CharacterBody2D):
            continue
        var unit_entity_id = unit.get("entity_id")
        var unit_id := int(unit_entity_id) if unit_entity_id != null else -1
        if incoming_ids.has(unit_id):
            continue
        print("[DESTROY_LOG] Removing replicated unit ", unit_id, " because it no longer exists in authoritative state.")
        unit.queue_free()

func _can_spawn_unit_from_snapshot(snapshot: Dictionary) -> bool:
    return snapshot.has("entity_id") and snapshot.has("player_id") and snapshot.has("owner_peer_id")

func _spawn_replicated_unit(snapshot: Dictionary) -> Node:
    var unit_parent := _get_units_root()
    if unit_parent == null:
        return null

    var unit = UNIT_SCENE.instantiate()
    var entity_id := int(snapshot.get("entity_id", -1))
    unit.name = "ReplicatedUnit_%d" % entity_id
    unit.entity_id = entity_id
    unit.player_id = int(snapshot.get("player_id", 0))
    unit.owner_peer_id = int(snapshot.get("owner_peer_id", -1))
    if snapshot.has("position"):
        unit.global_position = Vector2(float(snapshot["position"].get("x", 0.0)), float(snapshot["position"].get("y", 0.0)))

    unit_parent.add_child(unit)

    if unit.has_method("sync_from_snapshot"):
        unit.sync_from_snapshot(snapshot)
    else:
        unit.entity_id = entity_id
        unit.player_id = int(snapshot.get("player_id", 0))
        unit.owner_peer_id = int(snapshot.get("owner_peer_id", -1))
        unit.current_health = int(snapshot.get("health", unit.max_health))
        if snapshot.has("position"):
            unit.global_position = Vector2(float(snapshot["position"].get("x", 0.0)), float(snapshot["position"].get("y", 0.0)))

    print("[SPAWN_LOG] Created replicated remote unit ", unit.entity_id, " owned by peer ", unit.owner_peer_id, ".")
    return unit

func _sync_resources(resources: Array) -> void:
    var incoming_ids := {}
    for incoming in resources:
        var incoming_snapshot: Dictionary = incoming
        var incoming_id := int(incoming_snapshot.get("entity_id", -1))
        if bool(incoming_snapshot.get("destroyed", false)):
            for destroyed_resource in get_tree().get_nodes_in_group("resources"):
                if not is_instance_valid(destroyed_resource):
                    continue
                var destroyed_resource_id = destroyed_resource.get("entity_id")
                if destroyed_resource_id != null and int(destroyed_resource_id) == incoming_id:
                    print("[DESTROY_LOG] Removing replicated destroyed resource ", incoming_id, ".")
                    destroyed_resource.queue_free()
                    break
            continue

        incoming_ids[incoming_id] = true
        for resource in get_tree().get_nodes_in_group("resources"):
            if not is_instance_valid(resource):
                continue
            var resource_entity_id = resource.get("entity_id")
            if resource_entity_id != null and int(resource_entity_id) == incoming_id:
                if resource.has_method("sync_from_snapshot"):
                    resource.sync_from_snapshot(incoming_snapshot)
                else:
                    resource.amount = int(incoming_snapshot.get("amount", resource.amount))
                    if resource.get("current_health") != null:
                        resource.current_health = int(incoming_snapshot.get("health", resource.current_health))
                if incoming_snapshot.has("position") and not resource.has_method("sync_from_snapshot"):
                    resource.global_position = Vector2(float(incoming_snapshot["position"].get("x", 0.0)), float(incoming_snapshot["position"].get("y", 0.0)))
                break

    for resource in get_tree().get_nodes_in_group("resources"):
        if not is_instance_valid(resource):
            continue
        var resource_entity_id = resource.get("entity_id")
        var resource_id := int(resource_entity_id) if resource_entity_id != null else -1
        if incoming_ids.has(resource_id):
            continue
        print("[DESTROY_LOG] Removing replicated resource ", resource_id, ".")
        resource.queue_free()

func _sync_buildings(buildings: Array) -> void:
    for incoming in buildings:
        var incoming_snapshot: Dictionary = incoming
        for building in get_tree().get_nodes_in_group("buildings"):
            if not is_instance_valid(building):
                continue
            if building.get("entity_id") == incoming_snapshot["entity_id"]:
                if incoming_snapshot.has("position"):
                    building.global_position = Vector2(float(incoming_snapshot["position"].get("x", 0.0)), float(incoming_snapshot["position"].get("y", 0.0)))
                building.current_health = int(incoming_snapshot.get("health", building.current_health))
                break

func _find_unit_node_by_entity_id(unit_id: int) -> Node:
    if unit_id < 0:
        return null
    for unit in get_tree().get_nodes_in_group("units"):
        if is_instance_valid(unit) and unit is CharacterBody2D:
            var unit_entity_id = unit.get("entity_id")
            if unit_entity_id != null and int(unit_entity_id) == unit_id:
                return unit
    return null

func _get_units_root() -> Node:
    return get_node_or_null("/root/World/Units")

func _allocate_dynamic_entity_id() -> int:
    while _find_unit_node_by_entity_id(_next_dynamic_entity_id) != null:
        _next_dynamic_entity_id += 1
    var allocated := _next_dynamic_entity_id
    _next_dynamic_entity_id += 1
    return allocated

func _get_spawn_position(player_slot: int) -> Vector2:
    if player_slot < DEFAULT_UNIT_SPAWN_POSITIONS.size():
        return DEFAULT_UNIT_SPAWN_POSITIONS[player_slot]
    var offset_slot := player_slot - DEFAULT_UNIT_SPAWN_POSITIONS.size()
    return DEFAULT_UNIT_SPAWN_POSITIONS.back() + Vector2(80 * float(offset_slot + 1), 0.0)

# DEBUG: Log all unit positions to server log (safe to delete)
func _debug_log_unit_positions() -> void:
    print("[DEBUG_UNIT_POS] --- Unit positions snapshot ---")
    for unit in get_tree().get_nodes_in_group("units"):
        if not is_instance_valid(unit):
            continue
        var uid: int = int(unit.get("entity_id")) if unit.get("entity_id") != null else int(unit.get_instance_id())
        var pid: int = int(unit.get("player_id")) if unit.get("player_id") != null else -1
        var pos: Vector2 = unit.global_position
        print("[DEBUG_UNIT_POS] Unit %d (player %d) -> pos: (%.2f, %.2f)" % [uid, pid, pos.x, pos.y])
    print("[DEBUG_UNIT_POS] ------------------------------")