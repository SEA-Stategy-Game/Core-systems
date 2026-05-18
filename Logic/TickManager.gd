extends Node

signal tick(tick: int)
signal tick_processed(count: int)
signal authoritative_state_ready(state: Dictionary)

@export var tick_interval: float = 0.1
@export var run_without_network: bool = true

var time_passed: float = 0.0
var current_tick: int = 0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

func is_ready() -> bool:
    return true

func get_tick_count() -> int:
    return current_tick

func build_authoritative_snapshot() -> Dictionary:
    return _build_authoritative_snapshot()

func _process(delta: float) -> void:
    var should_tick := run_without_network
    var peer := multiplayer.multiplayer_peer
    var peer_active := peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
    if peer_active:
        should_tick = multiplayer.is_server()
    if not should_tick:
        return
    time_passed += delta
    if time_passed < tick_interval:
        return
    time_passed = 0.0
    current_tick += 1
    _process_tick()

func _process_tick() -> void:
    tick.emit(current_tick)
    tick_processed.emit(current_tick)
    authoritative_state_ready.emit(_build_authoritative_snapshot())

func _build_authoritative_snapshot() -> Dictionary:
    var snapshot := {
        "payload_type": "full",
        "tick": current_tick,
        "timestamp": Time.get_unix_time_from_system(),
        "units": [],
        "resources": [],
        "buildings": [],
        "scenario": {}
    }

    for unit in get_tree().get_nodes_in_group("units"):
        if not is_instance_valid(unit) or not (unit is CharacterBody2D):
            continue
        var entity_id = unit.get("entity_id")
        if entity_id == null:
            continue
        if unit.is_queued_for_deletion() or _node_is_destroyed(unit):
            continue
        snapshot["units"].append({
            "entity_id": int(entity_id),
            "player_id": int(unit.get("player_id")) if unit.get("player_id") != null else 0,
            "owner_peer_id": int(unit.get("owner_peer_id")) if unit.get("owner_peer_id") != null else -1,
            "position": {"x": unit.global_position.x, "y": unit.global_position.y},
            "health": int(unit.get("current_health")),
            "idle": bool(unit.get("is_idle")),
            "destroyed": false
        })

    for resource in get_tree().get_nodes_in_group("resources"):
        if not is_instance_valid(resource):
            continue
        var entity_id = resource.get("entity_id")
        if entity_id == null:
            continue
        if resource.is_queued_for_deletion() or _node_is_destroyed(resource):
            continue
        snapshot["resources"].append({
            "entity_id": int(entity_id),
            "resource_name": str(resource.get("resource_name")) if resource.get("resource_name") != null else resource.name,
            "position": {"x": resource.global_position.x, "y": resource.global_position.y},
            "amount": int(resource.get("amount")) if resource.get("amount") != null else -1,
            "health": int(resource.get("current_health")) if resource.get("current_health") != null else -1,
            "destroyed": false
        })

    for building in get_tree().get_nodes_in_group("buildings"):
        if not is_instance_valid(building):
            continue
        var entity_id = building.get("entity_id")
        if entity_id == null:
            continue
        snapshot["buildings"].append({
            "entity_id": int(entity_id),
            "player_id": int(building.get("player_id")) if building.get("player_id") != null else 0,
            "position": {"x": building.global_position.x, "y": building.global_position.y},
            "health": int(building.get("current_health")) if building.get("current_health") != null else -1
        })

    _snapshot_sort_by_id(snapshot["units"])
    _snapshot_sort_by_id(snapshot["resources"])
    _snapshot_sort_by_id(snapshot["buildings"])

    var scenario = get_node_or_null("/root/World/ScenarioController")
    if scenario != null and scenario.has_method("serialize_state"):
        snapshot["scenario"] = scenario.serialize_state()

    snapshot["state_signature"] = DeterminismHash.snapshot_signature(snapshot)
    return snapshot

static func _snapshot_sort_by_id(items: Array) -> void:
    items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return int(a.get("entity_id", -1)) < int(b.get("entity_id", -1))
    )

static func _node_is_destroyed(node: Node) -> bool:
    if node.has_method("is_alive"):
        return not node.is_alive()
    if node.has_method("is_destroyed"):
        return node.is_destroyed()
    return false