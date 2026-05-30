## UnitActionFire.gd
## -----------------------------------------------------------------------
## Concrete IUnitAction -- fires a single Projectile at a target.
##
## The action moves the unit into projectile range, spawns one Projectile,
## waits for the cooldown, and either completes (single shot) or loops
## (auto-fire mode) until the target dies or no hostiles remain.
## -----------------------------------------------------------------------
extends RefCounted
class_name UnitActionFire

const ActionState = IUnitAction.ActionState

var _state: int = ActionState.PENDING
var _target_node: Node2D = null
var _attack_cooldown: float = 1.0
var _cooldown_timer: float = 0.0
var _auto_repeat: bool = true       ## fire repeatedly until target dies
var _shots_fired: int = 0
var _max_shots: int = -1            ## -1 = unlimited (until target dies / out of range)
var _projectile_damage: int = -1
var _projectile_speed: float = -1.0

# -----------------------------------------------------------------
# IUnitAction contract
# -----------------------------------------------------------------

func start(unit: CharacterBody2D, target: Node2D) -> void:
	_state = ActionState.RUNNING
	if target != null:
		_target_node = target
	if "attack_cooldown" in unit:
		_attack_cooldown = unit.attack_cooldown
	_cooldown_timer = 0.0
	_shots_fired = 0

func tick(unit: CharacterBody2D, delta: float) -> int:
	if _state != ActionState.RUNNING:
		return _state

	_cooldown_timer -= delta

	if not is_instance_valid(_target_node):
		_state = ActionState.COMPLETED
		return _state
	if _target_node.has_method("is_alive") and not _target_node.is_alive():
		_state = ActionState.COMPLETED
		return _state

	# Move into firing range if we have one configured.
	var in_range := true
	if unit.has_method("get_hostiles_in_range"):
		in_range = unit.get_hostiles_in_range().has(_target_node)

	if not in_range:
		var dir := unit.global_position.direction_to(_target_node.global_position)
		var speed = unit.Speed if "Speed" in unit else 50
		unit.velocity = dir * speed
		unit.move_and_slide()
		return _state

	unit.velocity = Vector2.ZERO

	# Fire on cooldown.
	if _cooldown_timer <= 0.0:
		_cooldown_timer = _attack_cooldown
		if unit.has_method("fire_projectile"):
			unit.fire_projectile(_target_node)
			_shots_fired += 1
			if _max_shots > 0 and _shots_fired >= _max_shots:
				_state = ActionState.COMPLETED
				return _state
			if not _auto_repeat:
				_state = ActionState.COMPLETED
				return _state

	return _state

func cancel(unit: CharacterBody2D) -> void:
	_state = ActionState.FAILED
	if unit != null:
		unit.velocity = Vector2.ZERO

func serialize() -> Dictionary:
	var target_id: int = -1
	if is_instance_valid(_target_node) and "entity_id" in _target_node:
		target_id = _target_node.entity_id
	return {
		"type": "FIRE",
		"target_id": target_id,
		"state": _state,
		"shots_fired": _shots_fired,
	}

# -----------------------------------------------------------------
# Factories
# -----------------------------------------------------------------

## Fire a single projectile at `target` (action completes after one shot).
static func create_single(target: Node2D) -> UnitActionFire:
	var a := UnitActionFire.new()
	a._target_node = target
	a._auto_repeat = false
	a._max_shots = 1
	return a

## Fire continuously at `target` until it dies / leaves range.
static func create_auto(target: Node2D) -> UnitActionFire:
	var a := UnitActionFire.new()
	a._target_node = target
	a._auto_repeat = true
	return a
