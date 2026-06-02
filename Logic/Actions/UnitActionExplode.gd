## UnitActionExplode.gd
## -----------------------------------------------------------------------
## One-shot area-of-effect strike centred on a position (or the unit's
## current position).  Applies damage with linear falloff to every
## damageable hostile within `radius`.  Completes in a single tick.
##
## Useful for grenades, dynamite, mage spells, etc.
## -----------------------------------------------------------------------
extends RefCounted
class_name UnitActionExplode

const ActionState = IUnitAction.ActionState

var _state: int = ActionState.PENDING
var _center: Vector2 = Vector2.ZERO
var _radius: float = 64.0
var _damage: int = 25
var _falloff: float = 0.6
var _attacker_player_id: int = -1

# -----------------------------------------------------------------
# IUnitAction contract
# -----------------------------------------------------------------

func start(unit: CharacterBody2D, _target: Node2D) -> void:
	_state = ActionState.RUNNING
	if "player_id" in unit:
		_attacker_player_id = unit.player_id
	# If no centre was set explicitly, explode at the unit's position.
	if _center == Vector2.ZERO and unit:
		_center = unit.global_position

func tick(unit: CharacterBody2D, _delta: float) -> int:
	if _state != ActionState.RUNNING:
		return _state
	_apply_explosion(unit)
	_state = ActionState.COMPLETED
	return _state

func cancel(_unit: CharacterBody2D) -> void:
	_state = ActionState.FAILED

func serialize() -> Dictionary:
	return {
		"type": "EXPLODE",
		"center": {"x": _center.x, "y": _center.y},
		"radius": _radius,
		"damage": _damage,
		"state": _state,
	}

# -----------------------------------------------------------------
# Implementation
# -----------------------------------------------------------------

func _apply_explosion(unit: CharacterBody2D) -> void:
	var tree = unit.get_tree() if unit else null
	if tree == null:
		return
	print("[COMBAT_LOG] Unit ", _get_uid(unit), " detonates AoE (r=",
		_radius, ", dmg=", _damage, ") at ", _center)
	var candidates: Array = []
	candidates.append_array(tree.get_nodes_in_group("units"))
	candidates.append_array(tree.get_nodes_in_group("buildings"))
	candidates.append_array(tree.get_nodes_in_group("resources"))
	var r2 = _radius * _radius
	for c in candidates:
		if not is_instance_valid(c) or not (c is Node2D):
			continue
		if c == unit:
			continue
		var d2 = c.global_position.distance_squared_to(_center)
		if d2 > r2:
			continue
		if c.has_method("get_player_id"):
			var pid = int(c.get_player_id())
			if pid == _attacker_player_id and pid >= 0:
				continue
		if not c.has_method("take_damage"):
			continue
		var t = sqrt(d2) / _radius
		var dmg_scale = lerp(1.0, _falloff, t)
		var dmg = int(round(float(_damage) * dmg_scale))
		if dmg > 0:
			c.take_damage(dmg)

func _get_uid(unit: CharacterBody2D) -> int:
	if unit == null:
		return -1
	if "entity_id" in unit:
		return unit.entity_id
	return unit.get_instance_id()

# -----------------------------------------------------------------
# Factory
# -----------------------------------------------------------------

## Detonate centred on a world position.
static func create(center: Vector2, radius: float = 64.0,
		damage: int = 25, falloff: float = 0.6) -> UnitActionExplode:
	var a := UnitActionExplode.new()
	a._center = center
	a._radius = radius
	a._damage = damage
	a._falloff = falloff
	return a

## Detonate centred on the acting unit's position.  Useful for
## self-destruct / kamikaze units; centre is resolved in start().
static func create_self(radius: float = 64.0, damage: int = 25,
		falloff: float = 0.6) -> UnitActionExplode:
	var a := UnitActionExplode.new()
	a._center = Vector2.ZERO
	a._radius = radius
	a._damage = damage
	a._falloff = falloff
	return a
