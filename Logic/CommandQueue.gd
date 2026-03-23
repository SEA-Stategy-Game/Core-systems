## CommandQueue.gd
## -----------------------------------------------------------------------
## Per-unit sequential command queue.  The TickManager calls `process_tick`
## once per simulation tick; the queue pops the next action and advances
## through its lifecycle: PENDING -> start() -> RUNNING -> tick() per frame
## -> COMPLETED / FAILED -> next action.
##
## Capacity is capped at MAX_QUEUE_SIZE to satisfy the 1-20 unit limit
## without causing tick-jitter (bounded work per tick).
## -----------------------------------------------------------------------
extends RefCounted
class_name CommandQueue

signal action_completed(unit_id: int, action_data: Dictionary)
signal action_failed(unit_id: int, action_data: Dictionary)
signal queue_empty(unit_id: int)

const MAX_QUEUE_SIZE: int = 32  # Generous cap; AI plans are typically < 10

var _queue: Array = []           # Array[IUnitAction-conforming RefCounted]
var _current_action = null       # Currently executing action
var _unit: CharacterBody2D = null
var _unit_id: int = -1

# -----------------------------------------------------------------
# Initialisation
# -----------------------------------------------------------------

func setup(unit: CharacterBody2D, unit_id: int) -> void:
	_unit = unit
	_unit_id = unit_id

# -----------------------------------------------------------------
# Queue management
# -----------------------------------------------------------------

## Append an action to the back of the queue.
## Returns false if the queue is full.
func enqueue(action) -> bool:
	if not IUnitAction.is_implemented_by(action):
		push_error("CommandQueue: object does not implement IUnitAction.")
		return false
	if _queue.size() >= MAX_QUEUE_SIZE:
		push_warning("CommandQueue: queue full for unit ", _unit_id)
		return false
	_queue.append(action)
	return true

## Clear all pending actions and cancel the active one.
func clear() -> void:
	if _current_action != null:
		_current_action.cancel(_unit)
		_current_action = null
	_queue.clear()

## Number of actions waiting (excluding the currently running one).
func pending_count() -> int:
	return _queue.size()

## True when there is no running or pending action.
func is_idle() -> bool:
	return _current_action == null and _queue.is_empty()

# -----------------------------------------------------------------
# Tick processing  (called by TickManager / Unit)
# -----------------------------------------------------------------

func process_tick(delta: float) -> void:
	# If no current action, try to pop the next one
	if _current_action == null:
		if _queue.is_empty():
			queue_empty.emit(_unit_id)
			return
		_current_action = _queue.pop_front()
		# Resolve target -- stored on the action by the ActionGateway
		var target = _current_action._target_node if "_target_node" in _current_action else null
		_current_action.start(_unit, target)

	# Advance the running action
	var state: int = _current_action.tick(_unit, delta)

	match state:
		IUnitAction.ActionState.COMPLETED:
			action_completed.emit(_unit_id, _current_action.serialize())
			_current_action = null
		IUnitAction.ActionState.FAILED:
			action_failed.emit(_unit_id, _current_action.serialize())
			_current_action = null
		# RUNNING / PENDING -> continue next tick

# -----------------------------------------------------------------
# Persistence helpers
# -----------------------------------------------------------------

func serialize() -> Array:
	var data: Array = []
	if _current_action != null:
		data.append(_current_action.serialize())
	for action in _queue:
		data.append(action.serialize())
	return data
