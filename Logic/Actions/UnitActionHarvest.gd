extends RefCounted
class_name UnitActionHarvest

const ACTION_STATE = IUnitAction.ActionState

var _state: int = ACTION_STATE.PENDING
var _target_node: Node2D = null
var _elapsed: float = 0.0
var _harvest_duration: float = 5.0

func start(unit: CharacterBody2D, target: Node2D) -> void:
	_state = ACTION_STATE.RUNNING
	if target != null:
		_target_node = target

	if not is_instance_valid(_target_node):
		_state = ACTION_STATE.FAILED
		return

	if "total_time" in _target_node:
		_harvest_duration = float(_target_node.total_time)
	elif "totalTime" in _target_node:
		_harvest_duration = float(_target_node.totalTime)

	if unit.has_node("AnimationPlayer"):
		var anim: AnimationPlayer = unit.get_node("AnimationPlayer")
		if anim.has_animation("Chop"):
			anim.play("Chop")
		elif anim.has_animation("Work"):
			anim.play("Work")

	if _target_node.has_method("_on_harvest_area_body_entered"):
		if "units_harvesting" in _target_node:
			_target_node.units_harvesting += 1
			if _target_node.has_node("ProgressBar/Timer"):
				var timer = _target_node.get_node("ProgressBar/Timer")
				if timer.is_stopped():
					timer.start()

func tick(unit: CharacterBody2D, delta: float) -> int:
	if _state != ACTION_STATE.RUNNING:
		return _state

	if not is_instance_valid(_target_node):
		_state = ACTION_STATE.COMPLETED
		if unit.has_node("AnimationPlayer"):
			unit.get_node("AnimationPlayer").stop()
		return _state

	_elapsed += delta

	if _elapsed > _harvest_duration * 3.0:
		_state = ACTION_STATE.COMPLETED
		_cleanup(unit)

	return _state

func cancel(unit: CharacterBody2D) -> void:
	_state = ACTION_STATE.FAILED
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

func _cleanup(unit: CharacterBody2D) -> void:
	if is_instance_valid(_target_node):
		if "units_harvesting" in _target_node:
			_target_node.units_harvesting = maxi(0, _target_node.units_harvesting - 1)
			if _target_node.units_harvesting <= 0 and _target_node.has_node("ProgressBar/Timer"):
				_target_node.get_node("ProgressBar/Timer").stop()
	if unit.has_node("AnimationPlayer"):
		unit.get_node("AnimationPlayer").stop()

static func create(resource_node: Node2D) -> UnitActionHarvest:
	var action = UnitActionHarvest.new()
	action._target_node = resource_node
	if resource_node and ("total_time" in resource_node or "totalTime" in resource_node):
		action._harvest_duration = float(resource_node.get("total_time") if resource_node.get("total_time") != null else resource_node.get("totalTime"))
	return action
