extends Node
class_name ShowcaseScenario

signal scenario_state_changed(state: Dictionary)

@export var auto_demo_on_ready: bool = false
@export var demo_player_id: int = 0
@export var demo_mode_name: String = "ATTACK"

var _world: Node = null
var _gateway: Node = null
var _authoritative_state: Dictionary = {}
var _authoritative_signature: String = ""
var _local_signature: String = ""
var _demo_active: bool = false
var _demo_phase: String = "idle"
var _demo_unit_id: int = -1
var _demo_target_id: int = -1

func _ready() -> void:
    _world = get_parent()
    _gateway = _world.get_node_or_null("ClientGateway") if _world != null else null
    if _gateway != null and _gateway.has_signal("authoritative_state_applied"):
        if not _gateway.authoritative_state_applied.is_connected(_on_authoritative_state_applied):
            _gateway.authoritative_state_applied.connect(_on_authoritative_state_applied)
    _refresh_cache()
    _update_local_signature()
    _emit_state_change()
    if auto_demo_on_ready:
        call_deferred("run_demo")

func bind_world(world: Node) -> void:
    _world = world
    _gateway = _world.get_node_or_null("ClientGateway") if _world != null else null
    _refresh_cache()
    _update_local_signature()
    _emit_state_change()

func serialize_state() -> Dictionary:
    return {
        "demo_active": _demo_active,
        "demo_phase": _demo_phase,
        "demo_mode_name": demo_mode_name,
        "demo_player_id": demo_player_id,
        "demo_unit_id": _demo_unit_id,
        "demo_target_id": _demo_target_id
    }

func get_status_report() -> Dictionary:
    return {
        "demo_active": _demo_active,
        "demo_phase": _demo_phase,
        "demo_unit_id": _demo_unit_id,
        "demo_target_id": _demo_target_id,
        "authoritative_tick": int(_authoritative_state.get("tick", -1)),
        "local_signature": _local_signature,
        "authoritative_signature": _authoritative_signature,
        "in_sync": is_in_sync()
    }

func is_in_sync() -> bool:
    return not _local_signature.is_empty() and _local_signature == _authoritative_signature

func get_local_signature() -> String:
    return _local_signature

func get_authoritative_signature() -> String:
    return _authoritative_signature

func get_authoritative_tick() -> int:
    return int(_authoritative_state.get("tick", -1))

func get_demo_unit_id() -> int:
    return _demo_unit_id

func get_demo_target_id() -> int:
    return _demo_target_id

func get_unit_ids_for_player(pid: int) -> Array[int]:
    var result: Array[int] = []
    for unit in _get_units():
        if int(unit.get("player_id")) == pid:
            result.append(int(unit.get("entity_id")))
    result.sort()
    return result

func get_first_unit_id_for_player(pid: int) -> int:
    var ids := get_unit_ids_for_player(pid)
    return ids[0] if not ids.is_empty() else -1

func get_first_resource_id() -> int:
    for res in _get_resources():
        return int(res.get("entity_id"))
    return -1

func run_demo(unit_id: int = -1, player_id: int = -1, target_id: int = -1) -> bool:
    _refresh_cache()
    if unit_id < 0:
        unit_id = get_first_unit_id_for_player(player_id if player_id >= 0 else demo_player_id)
    if unit_id < 0:
        push_warning("[SHOWCASE] No unit available for demo.")
        return false
    if player_id < 0:
        player_id = int(_lookup_unit(unit_id).get("player_id", demo_player_id))
    if target_id <= 0:
        target_id = _get_nearest_resource_id(unit_id)
    if target_id < 0:
        push_warning("[SHOWCASE] No resource available for demo.")
        return false

    _demo_unit_id = unit_id
    _demo_target_id = target_id
    _demo_active = true
    _demo_phase = "commanding"

    var command := {
        "action": demo_mode_name,
        "unit_id": unit_id,
        "player_id": player_id,
        "target_id": target_id
    }

    var result := false
    if _gateway != null and _gateway.has_method("submit_showcase_command"):
        result = bool(_gateway.submit_showcase_command(command))
    elif _gateway != null:
        result = _execute_local_demo_command(command)

    _demo_phase = "command_sent" if result else "command_failed"
    _update_local_signature()
    _emit_state_change()
    return result

func _execute_local_demo_command(command: Dictionary) -> bool:
    var action_gateway = get_node_or_null("/root/ActionGateway")
    if action_gateway == null:
        return false
    match String(command.get("action", "")):
        "CHOP_AND_RETURN":
            return action_gateway.go_chop_tree_and_return(int(command.get("unit_id", -1)), int(command.get("target_id", -1)), int(command.get("player_id", -1)))
        "MOVE":
            var pos_dict: Dictionary = command.get("target", {})
            return action_gateway.move_unit(int(command.get("unit_id", -1)), Vector2(float(pos_dict.get("x", 0.0)), float(pos_dict.get("y", 0.0))), int(command.get("player_id", -1)))
        "ATTACK":
            return action_gateway.attack_target(int(command.get("unit_id", -1)), int(command.get("target_id", -1)), int(command.get("player_id", -1)))
        _:
            return false

func _on_authoritative_state_applied(state: Dictionary) -> void:
    _authoritative_state = state.duplicate(true)
    _authoritative_signature = String(state.get("state_signature", ""))
    if _authoritative_signature.is_empty():
        _authoritative_signature = DeterminismHash.snapshot_signature(state)
    _update_local_signature()
    _refresh_cache()
    if _demo_active and not _authoritative_signature.is_empty() and not _local_signature.is_empty():
        _demo_phase = "synced" if _local_signature == _authoritative_signature else "desynced"
    _emit_state_change()

func _refresh_cache() -> void:
    if _world == null:
        _world = get_parent()
    _gateway = _world.get_node_or_null("ClientGateway") if _world != null else null
    if _demo_unit_id < 0:
        _demo_unit_id = get_first_unit_id_for_player(demo_player_id)
    if _demo_target_id <= 0:
        _demo_target_id = get_first_resource_id()

func _update_local_signature() -> void:
    _local_signature = DeterminismHash.snapshot_signature(_build_local_snapshot())

func _build_local_snapshot() -> Dictionary:
    var tick_manager = get_node_or_null("/root/TickManager")
    var snapshot := {
        "payload_type": "full",
        "tick": tick_manager.get_tick_count() if tick_manager != null and tick_manager.has_method("get_tick_count") else 0,
        "timestamp": 0,
        "units": [],
        "resources": [],
        "buildings": [],
        "stockpile": {
            "wood": Game.Wood,
            "stone": Game.Stone
        },
        "scenario": serialize_state()
    }

    for unit in _get_units():
        if unit.has_method("is_alive") and not unit.is_alive():
            continue
        snapshot["units"].append({
            "entity_id": int(unit.get("entity_id")),
            "player_id": int(unit.get("player_id")) if unit.get("player_id") != null else 0,
            "owner_peer_id": int(unit.get("owner_peer_id")) if unit.get("owner_peer_id") != null else -1,
            "position": {"x": unit.global_position.x, "y": unit.global_position.y},
            "health": int(unit.get("current_health")) if unit.get("current_health") != null else -1,
            "idle": bool(unit.get("is_idle")) if unit.get("is_idle") != null else true,
            "destroyed": false
        })

    for res in _get_resources():
        if res.has_method("is_alive") and not res.is_alive():
            continue
        snapshot["resources"].append({
            "entity_id": int(res.get("entity_id")),
            "resource_name": str(res.get("resource_name")) if res.get("resource_name") != null else res.name,
            "position": {"x": res.global_position.x, "y": res.global_position.y},
            "amount": int(res.get("amount")) if res.get("amount") != null else -1,
            "health": int(res.get("current_health")) if res.get("current_health") != null else -1,
            "destroyed": false
        })

    for building in _get_buildings():
        snapshot["buildings"].append({
            "entity_id": int(building.get("entity_id")),
            "player_id": int(building.get("player_id")) if building.get("player_id") != null else 0,
            "position": {"x": building.global_position.x, "y": building.global_position.y},
            "health": int(building.get("current_health")) if building.get("current_health") != null else -1
        })

    _sort_snapshot(snapshot["units"])
    _sort_snapshot(snapshot["resources"])
    _sort_snapshot(snapshot["buildings"])
    return snapshot

func _get_units() -> Array:
    var result: Array = []
    if _world == null:
        return result
    for node in _world.get_tree().get_nodes_in_group("units"):
        if is_instance_valid(node) and node is CharacterBody2D:
            result.append(node)
    result.sort_custom(func(a, b): return _node_sort_key(a) < _node_sort_key(b))
    return result

func _get_resources() -> Array:
    var result: Array = []
    if _world == null:
        return result
    for node in _world.get_tree().get_nodes_in_group("resources"):
        if is_instance_valid(node):
            result.append(node)
    result.sort_custom(func(a, b): return _node_sort_key(a) < _node_sort_key(b))
    return result

func _get_buildings() -> Array:
    var result: Array = []
    if _world == null:
        return result
    for node in _world.get_tree().get_nodes_in_group("buildings"):
        if is_instance_valid(node):
            result.append(node)
    result.sort_custom(func(a, b): return _node_sort_key(a) < _node_sort_key(b))
    return result

func _lookup_unit(unit_id: int) -> Dictionary:
    for unit in _get_units():
        if int(unit.entity_id) == unit_id:
            return {"player_id": int(unit.player_id), "entity_id": int(unit.entity_id)}
    return {}

func _sort_snapshot(items: Array) -> void:
    items.sort_custom(func(a, b): return int(a.get("entity_id", -1)) < int(b.get("entity_id", -1)))

func _node_sort_key(node: Node) -> String:
    return String(node.get_path())

func _emit_state_change() -> void:
    scenario_state_changed.emit(get_status_report())

func _get_nearest_resource_id(unit_id: int) -> int:
    var unit_node: Node2D = null
    for unit in _get_units():
        if int(unit.entity_id) == unit_id:
            unit_node = unit
            break
    if unit_node == null:
        return -1

    var best_id := -1
    var best_distance := INF
    for resource in _get_resources():
        if not is_instance_valid(resource):
            continue
        var resource_id := int(resource.get("entity_id"))
        if resource_id < 0:
            continue
        var distance := unit_node.global_position.distance_to(resource.global_position)
        if distance < best_distance:
            best_distance = distance
            best_id = resource_id
    return best_id