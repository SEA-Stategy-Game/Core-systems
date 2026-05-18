extends CharacterBody2D
class_name Unit

@export var selected: bool = false
@export var entity_id: int = -1
@export var player_id: int = 0
@export var owner_peer_id: int = -1
@export var max_health: int = 100
@export var attack_damage: int = 10
@export var attack_cooldown: float = 1.0

var current_health: int
var _is_destroyed: bool = false
var _needs_initial_position: bool = true

@onready var box = get_node("HitBox")
@onready var anim = get_node("AnimationPlayer")
@onready var attack_range_area: Area2D = get_node_or_null("Range")
@onready var tile_map: TileMapLayer = get_node("/root/World/NavigationRegion2D/TileMapLayer")

var follow_cursor: bool = false
var speed: int = 300
var is_animated: bool = false
var current_path_index: int = 0
@onready var sprite = $Arthax

var command_queue: CommandQueue = null
var is_idle: bool = true
var _bodies_in_range: Array = []

signal ai_action_completed(unit_id: int, action_data: Dictionary)
signal ai_action_failed(unit_id: int, action_data: Dictionary)
signal unit_idled(unit_id: int)

func _ready() -> void:
    current_health = max_health
    add_to_group("units", true)
    set_selected(selected)

    command_queue = CommandQueue.new()
    var uid: int = entity_id if entity_id >= 0 else get_instance_id()
    command_queue.setup(self, uid)
    command_queue.action_completed.connect(_on_cq_action_completed)
    command_queue.action_failed.connect(_on_cq_action_failed)
    command_queue.queue_empty.connect(_on_cq_queue_empty)

    if attack_range_area:
        attack_range_area.body_entered.connect(_on_range_body_entered)
        attack_range_area.body_exited.connect(_on_range_body_exited)

    $NavigationAgent2D.waypoint_reached.connect(_on_waypoint_reached)
    $NavigationAgent2D.navigation_finished.connect(func(): current_path_index = 0)

func assign_network_owner(peer_id: int, assigned_player_id: int) -> void:
    owner_peer_id = peer_id
    player_id = assigned_player_id
    if peer_id > 0:
        set_multiplayer_authority(peer_id, false)
    print("[OWNERSHIP_LOG] Unit ", entity_id, " assigned to peer ", peer_id, " as player ", assigned_player_id, ".")

func sync_from_snapshot(snapshot: Dictionary) -> void:
    entity_id = int(snapshot.get("entity_id", entity_id))
    player_id = int(snapshot.get("player_id", player_id))
    owner_peer_id = int(snapshot.get("owner_peer_id", owner_peer_id))
    current_health = int(snapshot.get("health", current_health))
    if bool(snapshot.get("destroyed", false)) or current_health <= 0:
        _mark_destroyed_from_network()
        return

    # Apply authoritative server position (clients consume this).
    if snapshot.has("position"):
        global_position = Vector2(snapshot["position"]["x"], snapshot["position"]["y"])
        velocity = Vector2.ZERO

    _needs_initial_position = false

    if owner_peer_id > 0:
        set_multiplayer_authority(owner_peer_id, false)

func is_locally_owned() -> bool:
    var peer := multiplayer.multiplayer_peer
    if peer == null:
        return true
    if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
        return false
    return multiplayer.get_unique_id() == owner_peer_id

func can_accept_local_input() -> bool:
    return is_locally_owned() and not _is_destroyed

func set_selected(value: bool) -> void:
    selected = value
    if box:
        box.visible = value

func _on_range_body_entered(body: Node2D) -> void:
    if body == self:
        return
    if body.has_method("get_player_id"):
        _bodies_in_range.append(body)

func _on_range_body_exited(body: Node2D) -> void:
    _bodies_in_range.erase(body)

func get_hostiles_in_range() -> Array:
    var hostiles: Array = []
    for body in _bodies_in_range:
        if not is_instance_valid(body):
            continue
        if not body.has_method("get_player_id"):
            continue
        if body.get_player_id() == player_id:
            continue
        if body.get_player_id() == -1:
            continue
        if body.has_method("is_alive") and not body.is_alive():
            continue
        hostiles.append(body)
    return hostiles

func get_closest_hostile() -> Node2D:
    var hostiles = get_hostiles_in_range()
    var closest: Node2D = null
    var closest_dist: float = INF
    for h in hostiles:
        var d = global_position.distance_to(h.global_position)
        if d < closest_dist:
            closest_dist = d
            closest = h
    return closest

func is_target_in_attack_range(target: Node2D, allow_neutral_targets: bool = false) -> bool:
    if target == null or not is_instance_valid(target):
        return false
    if target == self:
        return false
    if not target.has_method("get_player_id"):
        return false
    if target.has_method("is_alive") and not target.is_alive():
        return false
    var target_player_id := int(target.get_player_id())
    if target_player_id == player_id:
        return false
    if target_player_id == -1 and not allow_neutral_targets:
        return false
    return global_position.distance_to(target.global_position) <= get_attack_range_radius()

func get_attack_range_radius() -> float:
    var collision_shape := attack_range_area.get_node_or_null("CollisionShape2D") if attack_range_area != null else null
    if collision_shape != null and collision_shape.shape is CircleShape2D:
        return (collision_shape.shape as CircleShape2D).radius * maxf(collision_shape.global_scale.x, collision_shape.global_scale.y)
    return 60.0

func get_local_movement_speed() -> float:
    if tile_map != null and tile_map.has_method("get_tile_at_world_pos"):
        var tile = tile_map.get_tile_at_world_pos(global_position)
        if tile != null and tile.has_method("get_movement_multiplier"):
            return speed * tile.get_movement_multiplier()
    return speed

func take_damage(amount: int) -> void:
    if _is_destroyed or amount <= 0:
        return
    current_health = maxi(0, current_health - amount)
    print("[COMBAT_LOG] Unit ", entity_id, " (player ", player_id, ") took ", amount, " damage. HP: ", current_health, "/", max_health)
    var sprite = get_node_or_null("Arthax")
    if not sprite:
        sprite = get_node_or_null("Sprite2D")
    if sprite:
        if sprite.material:
            sprite.material = sprite.material.duplicate(true)
        var tween = get_tree().create_tween()
        sprite.modulate = Color(1, 0, 0)
        tween.tween_property(sprite, "modulate", Color(1, 1, 1), 0.2)
    if current_health <= 0:
        die()

func get_current_health() -> int:
    return current_health

func is_alive() -> bool:
    return not _is_destroyed and current_health > 0

func get_player_id() -> int:
    return player_id

func get_owner_peer_id() -> int:
    return owner_peer_id

func die() -> void:
    if _is_destroyed:
        return
    _is_destroyed = true
    print("[COMBAT_LOG] Unit ", entity_id, " (player ", player_id, ") destroyed.")
    print("[DESTROY_LOG] Unit ", entity_id, " removed from authoritative gameplay.")
    if command_queue:
        command_queue.clear()
    queue_free()

func _mark_destroyed_from_network() -> void:
    if _is_destroyed:
        return
    _is_destroyed = true
    current_health = 0
    print("[DESTROY_LOG] Replicated destruction for unit ", entity_id, ".")
    queue_free()

func _input(event) -> void:
    if not can_accept_local_input():
        return
    if event.is_action_pressed("RightClick") and selected:
        var gateway = get_node_or_null("/root/Server")
        if gateway == null:
            gateway = get_node_or_null("/root/World/ClientGateway")
        if gateway == null or not gateway.has_method("submit_player_command"):
            return
        var target := get_global_mouse_position()
        var ok := bool(gateway.submit_player_command({
            "action": "MOVE",
            "unit_id": entity_id,
            "player_id": player_id,
            "target": {"x": target.x, "y": target.y}
        }))
        if ok:
            print("[INPUT_LOG] Local peer ", owner_peer_id, " requested MOVE for unit ", entity_id, " to ", target, ".")

func _physics_process(_delta) -> void:
    _bodies_in_range = _bodies_in_range.filter(func(b): return is_instance_valid(b))

    var peer := multiplayer.multiplayer_peer
    var should_advance_physics := false
    if peer == null:
        should_advance_physics = true
    elif peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and multiplayer.is_server():
        should_advance_physics = true

    if should_advance_physics:
        move_and_slide()

func _on_cq_action_completed(uid: int, data: Dictionary) -> void:
    ai_action_completed.emit(uid, data)

func _on_cq_action_failed(uid: int, data: Dictionary) -> void:
    ai_action_failed.emit(uid, data)

func _on_cq_queue_empty(uid: int) -> void:
    if not is_idle:
        is_idle = true
        unit_idled.emit(uid)

func set_anim(flag) -> void:
    if flag and not is_animated:
        anim.play("Walk Down")
        is_animated = true
    if not flag and is_animated:
        anim.stop()
        is_animated = false

func point_to_line_dist(line_start: Vector2, line_end: Vector2, point_position: Vector2) -> float:
    var segment: Vector2 = line_end - line_start
    var length_sq: float = segment.length_squared()
    if length_sq <= 0.0001:
        return point_position.distance_to(line_start)

    var t: float = clampf((point_position - line_start).dot(segment) / length_sq, 0.0, 1.0)
    var closest_point: Vector2 = line_start + segment * t
    return point_position.distance_to(closest_point)

func recalculate_path() -> void:
    $NavigationAgent2D.target_position = $NavigationAgent2D.target_position

func _on_waypoint_reached(details: Dictionary) -> void:
    current_path_index += 1

func trigger_white_flash() -> void:
    var mat = sprite.material as ShaderMaterial
    mat.set_shader_parameter("active", true)
    await get_tree().create_timer(0.4).timeout
    mat.set_shader_parameter("active", false)

func get_navigation_path_segment(amount_of_segments: int) -> PackedVector2Array:
    var path = $NavigationAgent2D.get_current_navigation_path()
    if $NavigationAgent2D.is_navigation_finished() or current_path_index >= path.size():
        return PackedVector2Array()
    var end_index = min(current_path_index + amount_of_segments, path.size())
    return path.slice(current_path_index, end_index)

func _on_navigation_agent_2d_velocity_computed(safe_velocity: Vector2) -> void:
    # Only the authoritative simulation should compute/apply navigation velocity.
    var peer := multiplayer.multiplayer_peer
    if peer != null and not multiplayer.is_server():
        return

    velocity = safe_velocity
    if not $NavigationAgent2D.is_navigation_finished():
        set_anim(safe_velocity.length_squared() > 100)
    else:
        set_anim(false)
        velocity = Vector2.ZERO