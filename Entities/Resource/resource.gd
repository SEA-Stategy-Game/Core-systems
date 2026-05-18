extends Entity
class_name MapResource

@export var resource_name: String = "Resource"
@export var total_time: float = 5.0

@onready var bar = $ProgressBar
@onready var timer = $ProgressBar/Timer
@onready var nav_region = get_node_or_null("/root/World/NavigationRegion2D")
@onready var server = get_node_or_null("/root/World/ClientGateway")

var amount: int = 1
var max_amount: int = 1
var current_time: float
var units_harvesting: int = 0

signal modified

func _ready() -> void:
    player_id = -1
    current_health = max_health
    current_time = total_time
    if bar:
        bar.max_value = total_time
        bar.value = current_time
    if is_in_group("units"):
        remove_from_group("units")
    add_to_group("resources")
    if multiplayer.is_server() and server != null and server.has_method("_on_ressource_modified"):
        self.modified.connect(server._on_ressource_modified)

func _has_server_authority() -> bool:
    var peer := multiplayer.multiplayer_peer
    if peer == null:
        return true
    if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
        return false
    return multiplayer.is_server()

func harvest():
    if _is_destroyed:
        return
    if amount > 0:
        amount -= 1
        if amount <= 0:
            on_finished_harvesting()

func _on_harvest_area_body_entered(body: Node2D) -> void:
    if _is_destroyed or not _has_server_authority():
        return
    if body is Unit:
        units_harvesting += 1
        if timer and timer.is_stopped():
            timer.start()

func _on_harvest_area_body_exited(body: Node2D) -> void:
    if _is_destroyed or not _has_server_authority():
        return
    if body is Unit:
        units_harvesting -= 1
        if units_harvesting <= 0 and timer:
            timer.stop()

func _on_timer_timeout() -> void:
    if _is_destroyed or not _has_server_authority():
        return
    current_time -= 1 * units_harvesting

    if bar:
        var tween = get_tree().create_tween()
        tween.tween_property(bar, "value", current_time, 0.5)

    if current_time <= 0:
        harvest()

func die() -> void:
    _finalize_destruction("damaged")

func sync_from_snapshot(snapshot: Dictionary) -> void:
    if bool(snapshot.get("destroyed", false)):
        _mark_destroyed_from_network()
        return
    amount = int(snapshot.get("amount", amount))
    current_health = int(snapshot.get("health", current_health))
    if snapshot.has("position"):
        global_position = Vector2(snapshot["position"]["x"], snapshot["position"]["y"])
    if amount <= 0 or current_health <= 0:
        _mark_destroyed_from_network()

func on_finished_harvesting():
    _finalize_destruction("harvested")

func _finalize_destruction(reason: String) -> void:
    if _is_destroyed:
        return
    _is_destroyed = true
    current_health = 0
    amount = 0
    units_harvesting = 0
    if timer:
        timer.stop()
    print("[RESOURCE_LOG] Resource ", entity_id, " (", resource_name, ") destroyed via ", reason, ".")
    print("[DESTROY_LOG] Resource ", entity_id, " removed from authoritative gameplay.")
    modified.emit(self)
    queue_free()
    if nav_region != null and nav_region.has_method("rebuild_nav"):
        nav_region.rebuild_nav()

func _mark_destroyed_from_network() -> void:
    if _is_destroyed:
        return
    _is_destroyed = true
    current_health = 0
    amount = 0
    units_harvesting = 0
    if timer:
        timer.stop()
    print("[DESTROY_LOG] Replicated destruction for resource ", entity_id, " (", resource_name, ").")
    queue_free()