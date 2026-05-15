extends RefCounted
class_name CommandQueue

signal action_completed(unit_id: int, action_data: Dictionary)
signal action_failed(unit_id: int, action_data: Dictionary)
signal queue_empty(unit_id: int)

const MAX_QUEUE_SIZE: int = 32

var _queue: Array = []
var _current_action = null
var _unit: CharacterBody2D = null
var _unit_id: int = -1

func setup(unit: CharacterBody2D, unit_id: int) -> void:
	_unit = unit
	_unit_id = unit_id

func enqueue(action) -> bool:
	if not IUnitAction.is_implemented_by(action):
		push_error("CommandQueue: object does not implement IUnitAction.")
		return false
	if _queue.size() >= MAX_QUEUE_SIZE:
		push_warning("CommandQueue: queue full for unit %d" % _unit_id)
		return false
	_queue.append(action)
	return true

func clear() -> void:
	if _current_action != null:
		_current_action.cancel(_unit)
		_current_action = null
	_queue.clear()

func is_idle() -> bool:
	return _current_action == null and _queue.is_empty()

func pending_count() -> int:
	return _queue.size() + (1 if _current_action != null else 0)

func process_tick(unit: CharacterBody2D, delta: float) -> void:
	if _current_action == null:
		if _queue.is_empty():
			return
		_current_action = _queue.pop_front()
		_current_action.start(unit, null)

	var result = _current_action.tick(unit, delta)

	if result == IUnitAction.ActionState.COMPLETED:
		var finished_action = _current_action
		_current_action = null
		action_completed.emit(_unit_id, finished_action.serialize())
		if _queue.is_empty():
			queue_empty.emit(_unit_id)

	elif result == IUnitAction.ActionState.FAILED:
		var failed_action = _current_action
		_current_action = null
		action_failed.emit(_unit_id, failed_action.serialize())

func serialize() -> Array:
	var payload: Array = []
	if _current_action != null:
		payload.append(_current_action.serialize())
	for action in _queue:
		payload.append(action.serialize())
	return payload
