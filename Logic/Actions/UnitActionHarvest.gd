## UnitActionHarvest.gd
## -----------------------------------------------------------------------
## Concrete IUnitAction -- harvests a MapResource (tree, stone, etc.).
## Pre-condition: the unit must already be adjacent to the resource
## (a preceding MOVE action should handle pathfinding).
##
## The action registers the unit with the resource's harvesting count
## and waits until the resource signals depletion or a timer expires.
## -----------------------------------------------------------------------
extends RefCounted
class_name UnitActionHarvest

const ActionState = IUnitAction.ActionState

var _state: int = ActionState.PENDING
var _target_node: Node2D = null
var _elapsed: float = 0.0
var _harvest_duration: float = 5.0  # Overridden from resource's totalTime

# -----------------------------------------------------------------
# IUnitAction contract
# -----------------------------------------------------------------

func start(unit: CharacterBody2D, target: Node2D) -> void:
	_state = ActionState.RUNNING
	_target_node = target

	if not is_instance_valid(target):
		_state = ActionState.FAILED
		return

	# Read harvest time from the resource if available
	if "totalTime" in target:
		_harvest_duration = target.totalTime

	# Play chop / mine animation
	if unit.has_node("AnimationPlayer"):
		# Try resource-specific animation, fall back to idle
		var anim: AnimationPlayer = unit.get_node("AnimationPlayer")
		if anim.has_animation("Chop"):
			anim.play("Chop")
		elif anim.has_animation("Work"):
			anim.play("Work")

	# Increment the resource's harvesting counter so the resource
	# timer logic (already in resource.gd) does its job.
	if target.has_method("_on_harvest_area_body_entered"):
		if "units_harvesting" in target:
			target.units_harvesting += 1
			# Start the resource timer if it is stopped
			if target.has_node("ProgressBar/Timer"):
				var timer = target.get_node("ProgressBar/Timer")
				if timer.is_stopped():
					timer.start()

func tick(unit: CharacterBody2D, delta: float) -> int:
	if _state != ActionState.RUNNING:
		return _state

	# Resource was depleted or removed
	if not is_instance_valid(_target_node):
		_state = ActionState.COMPLETED
		if unit.has_node("AnimationPlayer"):
			unit.get_node("AnimationPlayer").stop()
		return _state

	_elapsed += delta

	# Safety timeout -- if the resource is still alive but the harvest
	# duration has far exceeded expectations, mark as completed.
	if _elapsed > _harvest_duration * 3.0:
		_state = ActionState.COMPLETED
		_cleanup(unit)

	return _state

func cancel(unit: CharacterBody2D) -> void:
	_state = ActionState.FAILED
	_cleanup(unit)

func serialize() -> Dictionary:
	var target_id: int = -1
	if is_instance_valid(_target_node) and "entity_id" in _target_node:
		target_id = _target_node.entity_id
	return {
		"type": "HARVEST",
		"target_id": target_id,
		"elapsed": _elapsed,
		"state": _state
	}

# -----------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------

func _cleanup(unit: CharacterBody2D) -> void:
	if is_instance_valid(_target_node):
		if "units_harvesting" in _target_node:
			_target_node.units_harvesting = maxi(0, _target_node.units_harvesting - 1)
			if _target_node.units_harvesting <= 0:
				if _target_node.has_node("ProgressBar/Timer"):
					_target_node.get_node("ProgressBar/Timer").stop()
	if unit.has_node("AnimationPlayer"):
		unit.get_node("AnimationPlayer").stop()

# -----------------------------------------------------------------
# Factory
# -----------------------------------------------------------------
static func create(resource_node: Node2D) -> UnitActionHarvest:
	var action = UnitActionHarvest.new()
	action._target_node = resource_node
	if resource_node and "totalTime" in resource_node:
		action._harvest_duration = resource_node.totalTime
	return action
