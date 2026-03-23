## UnitActionMove.gd
## -----------------------------------------------------------------------
## Concrete IUnitAction -- moves a unit to a target position.
## The action is RUNNING while the unit travels and transitions to
## COMPLETED once it arrives within `arrival_radius`.
## -----------------------------------------------------------------------
extends RefCounted
class_name UnitActionMove

const ActionState = IUnitAction.ActionState

var _target_position: Vector2 = Vector2.ZERO
var _arrival_radius: float = 12.0
var _state: int = ActionState.PENDING
var _target_node: Node2D = null  # Optional -- used to follow a moving target

# -----------------------------------------------------------------
# IUnitAction contract
# -----------------------------------------------------------------

func start(unit: CharacterBody2D, target: Node2D) -> void:
	_state = ActionState.RUNNING
	_target_node = target
	if target:
		_target_position = target.global_position
	# Play walk animation if available
	if unit.has_node("AnimationPlayer"):
		unit.get_node("AnimationPlayer").play("Walk Down")

func tick(unit: CharacterBody2D, _delta: float) -> int:
	if _state != ActionState.RUNNING:
		return _state

	# If following a live node, update destination every tick
	if is_instance_valid(_target_node):
		_target_position = _target_node.global_position

	var direction = unit.global_position.direction_to(_target_position)
	var speed = unit.Speed if "Speed" in unit else 50
	unit.velocity = direction * speed

	if unit.global_position.distance_to(_target_position) > _arrival_radius:
		unit.move_and_slide()
	else:
		unit.velocity = Vector2.ZERO
		_state = ActionState.COMPLETED
		if unit.has_node("AnimationPlayer"):
			unit.get_node("AnimationPlayer").stop()

	return _state

func cancel(unit: CharacterBody2D) -> void:
	_state = ActionState.FAILED
	unit.velocity = Vector2.ZERO
	if unit.has_node("AnimationPlayer"):
		unit.get_node("AnimationPlayer").stop()

func serialize() -> Dictionary:
	return {
		"type": "MOVE",
		"target_position": {"x": _target_position.x, "y": _target_position.y},
		"state": _state
	}

# -----------------------------------------------------------------
# Convenience factory
# -----------------------------------------------------------------
static func create(destination: Vector2) -> UnitActionMove:
	var action = UnitActionMove.new()
	action._target_position = destination
	return action

static func create_to_node(target_node: Node2D) -> UnitActionMove:
	var action = UnitActionMove.new()
	if target_node:
		action._target_position = target_node.global_position
		action._target_node = target_node
	return action
