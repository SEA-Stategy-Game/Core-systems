extends RefCounted
class_name UnitActionAttack

const ACTION_STATE = IUnitAction.ActionState

var _state := ACTION_STATE.PENDING
var _target_node: Node2D = null

var _attack_damage := 10
var _attack_cooldown := 1.0
var _cooldown_timer := 0.0
var _allow_neutral_targets := false

func setup(target: Node2D, allow_neutral_targets: bool = false) -> void:
    _target_node = target
    _allow_neutral_targets = allow_neutral_targets

func start(unit: CharacterBody2D, target: Node2D) -> void:
    if _state == ACTION_STATE.RUNNING:
        return

    _state = ACTION_STATE.RUNNING

    if target != null:
        _target_node = target

    if "attack_damage" in unit:
        _attack_damage = unit.attack_damage

    if "attack_cooldown" in unit:
        _attack_cooldown = unit.attack_cooldown

    _cooldown_timer = 0.0

func tick(unit: CharacterBody2D, delta: float) -> int:
    if _state != ACTION_STATE.RUNNING:
        return _state

    if unit.multiplayer.multiplayer_peer != null and not unit.multiplayer.is_server():
        return _state

    _cooldown_timer -= delta

    if _target_node == null or not is_instance_valid(_target_node):
        _state = ACTION_STATE.COMPLETED
        return _state

    if _target_node.has_method("is_alive") and not _target_node.is_alive():
        _state = ACTION_STATE.COMPLETED
        return _state

    if unit.has_method("is_target_in_attack_range"):
        if not unit.is_target_in_attack_range(_target_node, _allow_neutral_targets):
            var direction := unit.global_position.direction_to(_target_node.global_position)
            var chase_speed := 50.0
            if unit.has_method("get_local_movement_speed"):
                chase_speed = float(unit.get_local_movement_speed())
            unit.velocity = direction * chase_speed
            unit.move_and_slide()
            return _state
    elif unit.has_method("get_hostiles_in_range"):
        var hostiles = unit.get_hostiles_in_range()
        if not hostiles.has(_target_node):
            return _state

    unit.velocity = Vector2.ZERO

    if _cooldown_timer <= 0.0:
        _cooldown_timer = _attack_cooldown

        if _target_node.has_method("take_damage"):
            var target_id := _target_node.get_instance_id()
            if _target_node.get("entity_id") != null:
                target_id = int(_target_node.get("entity_id"))

            print("[COMBAT_LOG] Unit ", unit.get("entity_id"), " attacked target ", target_id, " for ", _attack_damage, " damage.")
            _target_node.take_damage(_attack_damage)

        if _target_node == null or not is_instance_valid(_target_node):
            _state = ACTION_STATE.COMPLETED
            return _state

        if _target_node.has_method("is_alive") and not _target_node.is_alive():
            _state = ACTION_STATE.COMPLETED

    return _state

func cancel(unit: CharacterBody2D) -> void:
    _state = ACTION_STATE.FAILED
    unit.velocity = Vector2.ZERO

func serialize() -> Dictionary:
    return {
        "type": "ATTACK",
        "state": _state
    }

static func create(target: Node2D) -> UnitActionAttack:
    var attack := UnitActionAttack.new()
    attack.setup(target, true)
    return attack

static func create_focused(target: Node2D) -> UnitActionAttack:
    var attack := UnitActionAttack.new()
    attack.setup(target, false)
    return attack
