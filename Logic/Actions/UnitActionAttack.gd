extends RefCounted
class_name UnitActionAttack

const ACTION_STATE = IUnitAction.ActionState

var _state := ACTION_STATE.PENDING
var _target_node: Node2D = null

@export var _attack_damage := 10
@export var _attack_cooldown := 1.0
@export var _hit_chance := 0.9
@export var _damage_variance := 0.2

var _cooldown_timer := 0.0
var _allow_neutral_targets := false
var _rng: RandomNumberGenerator = null

func setup(target: Node2D, allow_neutral_targets: bool = false) -> void:
	_target_node = target
	_allow_neutral_targets = allow_neutral_targets
	_rng = RandomNumberGenerator.new()
	_rng.randomize()

func start(unit: CharacterBody2D, target: Node2D) -> void:
	if _state == ACTION_STATE.RUNNING:
		return
	_state = ACTION_STATE.RUNNING
	if target != null:
		_target_node = target
	if "attack_damage" in unit:
		_attack_damage = int(unit.attack_damage)
	if "attack_cooldown" in unit:
		_attack_cooldown = float(unit.attack_cooldown)
	_cooldown_timer = 0.0
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()

func tick(unit: CharacterBody2D, delta: float) -> int:
	if _state != ACTION_STATE.RUNNING:
		return _state
	var multiplayer_api := unit.get_tree().get_multiplayer()
	var peer: MultiplayerPeer = multiplayer_api.multiplayer_peer
	var is_authoritative: bool = (
		peer == null or
		peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED or
		multiplayer_api.is_server()
	)
	if not is_authoritative:
		return _state

	_cooldown_timer -= delta

	# Target validity check.
	if _target_node == null or not is_instance_valid(_target_node):
		_state = ACTION_STATE.COMPLETED
		unit.velocity = Vector2.ZERO
		return _state

	if _target_node.has_method("is_alive") and not _target_node.is_alive():
		_state = ACTION_STATE.COMPLETED
		unit.velocity = Vector2.ZERO
		return _state

	# --- Range check ---
	var in_range: bool = _is_in_range(unit, _target_node)

	if not in_range:
		var direction := unit.global_position.direction_to(_target_node.global_position)
		var chase_speed := 50.0
		if unit.has_method("get_local_movement_speed"):
			chase_speed = float(unit.get_local_movement_speed())
		unit.velocity = direction * chase_speed
		return _state

	# In range — stop moving.
	unit.velocity = Vector2.ZERO

	if _cooldown_timer > 0.0:
		return _state

	_cooldown_timer = _attack_cooldown

	if not _target_node.has_method("take_damage") or not is_instance_valid(_target_node):
		return _state

	var min_dmg: int = max(1, int(round(float(_attack_damage) * (1.0 - _damage_variance))))
	var max_dmg: int = max(min_dmg, int(round(float(_attack_damage) * (1.0 + _damage_variance))))
	var damage: int = _rng.randi_range(min_dmg, max_dmg)

	var entity_id_value = _target_node.get("entity_id")
	var target_id: int = int(entity_id_value) if entity_id_value != null else int(_target_node.get_instance_id())

	if _rng.randf() <= _hit_chance:
		print("[COMBAT_LOG] Unit ", unit.get("entity_id"), " attacked target ", target_id, " for ", damage, " damage.")
		_target_node.take_damage(damage)
	else:
		print("[COMBAT_LOG] Unit ", unit.get("entity_id"), " missed target ", target_id, ".")

	# Trigger retaliation if target is idle.
	if is_instance_valid(_target_node) and _target_node.has_method("is_alive") and _target_node.is_alive():
		if "command_queue" in _target_node and _target_node.command_queue != null:
			if _target_node.command_queue.is_idle():
				var retaliation: UnitActionAttack = UnitActionAttack.create_focused(unit)
				_target_node.command_queue.enqueue(retaliation)

	# Re-validate after damage application.
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

func _is_in_range(unit: CharacterBody2D, target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target == unit:
		return false
	if target.has_method("is_alive") and not target.is_alive():
		return false
	if not target.has_method("get_player_id"):
		return false
	var target_player_id := int(target.get_player_id())
	if target_player_id == unit.get("player_id"):
		return false
	if target_player_id == -1 and not _allow_neutral_targets:
		return false

	var radius := _effective_range_radius(unit)
	return unit.global_position.distance_to(target.global_position) <= radius

func _effective_range_radius(unit: CharacterBody2D) -> float:
	var range_area: Node = unit.get_node_or_null("Range")
	if range_area == null:
		return 60.0
	var collision_shape: Node = range_area.get_node_or_null("CollisionShape2D")
	if collision_shape == null or not (collision_shape is CollisionShape2D):
		return 60.0
	var cs := collision_shape as CollisionShape2D
	if not (cs.shape is CircleShape2D):
		return 60.0
	var shape_radius: float = (cs.shape as CircleShape2D).radius
	var sx: float = abs(unit.scale.x) * abs(range_area.scale.x) * abs(cs.scale.x)
	var sy: float = abs(unit.scale.y) * abs(range_area.scale.y) * abs(cs.scale.y)
	return shape_radius * maxf(sx, sy)

static func create(target: Node2D) -> UnitActionAttack:
	var attack := UnitActionAttack.new()
	attack.setup(target, true)
	return attack

static func create_focused(target: Node2D) -> UnitActionAttack:
	var attack := UnitActionAttack.new()
	attack.setup(target, false)
	return attack