extends RefCounted
class_name UnitActionAttack

const ACTION_STATE = IUnitAction.ActionState

var _state := ACTION_STATE.PENDING
var _target_node: Node2D = null

var _attack_damage := 10
var _attack_cooldown := 1.0
var _cooldown_timer := 0.0


func start(unit: CharacterBody2D, target: Node2D) -> void:
	# GUARD: prevent double-start
	if _state == ACTION_STATE.RUNNING:
		return

	_state = ACTION_STATE.RUNNING
	_target_node = target

	if "attack_damage" in unit:
		_attack_damage = unit.attack_damage

	if "attack_cooldown" in unit:
		_attack_cooldown = unit.attack_cooldown

	_cooldown_timer = 0.0


func tick(unit: CharacterBody2D, delta: float) -> int:
	if _state != ACTION_STATE.RUNNING:
		return _state

	# AUTHORITY GUARD (CRITICAL FOR MULTIPLAYER)
	if unit.has_method("is_multiplayer_authority") and not unit.is_multiplayer_authority():
		return _state

	_cooldown_timer -= delta

	# validate target
	if _target_node == null or not is_instance_valid(_target_node):
		_state = ACTION_STATE.COMPLETED
		return _state

	if _target_node.has_method("is_alive") and not _target_node.is_alive():
		_state = ACTION_STATE.COMPLETED
		return _state

	# range check ONLY (no movement here)
	if unit.has_method("get_hostiles_in_range"):
		var hostiles = unit.get_hostiles_in_range()
		if not hostiles.has(_target_node):
			return _state

	# attack
	unit.velocity = Vector2.ZERO

	if _cooldown_timer <= 0.0:
		_cooldown_timer = _attack_cooldown

		if _target_node.has_method("take_damage"):
			_target_node.take_damage(_attack_damage)

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
	var a = UnitActionAttack.new()
	a._target_node = target
	return a


static func create_focused(target: Node2D) -> UnitActionAttack:
	var a = UnitActionAttack.new()
	a._target_node = target
	return a
