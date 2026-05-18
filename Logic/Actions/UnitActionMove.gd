extends RefCounted
class_name UnitActionMove

const ACTION_STATE = IUnitAction.ActionState

var _target_position: Vector2 = Vector2.ZERO
var _arrival_radius: float = 12.0
var _state: int = ACTION_STATE.PENDING
var _target_node: Node2D = null

func start(unit: CharacterBody2D, target: Node2D) -> void:
	_state = ACTION_STATE.RUNNING
	if target != null:
		_target_node = target
	if is_instance_valid(_target_node):
		_target_position = _target_node.global_position
	elif _target_position == Vector2.ZERO and unit != null:
		_target_position = unit.global_position

	if unit.has_node("AnimationPlayer"):
		unit.get_node("AnimationPlayer").play("Walk Down")

func tick(unit: CharacterBody2D, _delta: float) -> int:
	if _state != ACTION_STATE.RUNNING:
		return _state

	if is_instance_valid(_target_node):
		_target_position = _target_node.global_position

	var direction = unit.global_position.direction_to(_target_position)
	var base_speed = int(unit.get("speed")) if unit.get("speed") != null else 50
	var speed = float(base_speed)
	unit.velocity = direction * speed

	if unit.global_position.distance_to(_target_position) > _arrival_radius:
		unit.move_and_slide()
	else:
		unit.velocity = Vector2.ZERO
		_state = ACTION_STATE.COMPLETED
		if unit.has_node("AnimationPlayer"):
			unit.get_node("AnimationPlayer").stop()

	return _state

func cancel(unit: CharacterBody2D) -> void:
	_state = ACTION_STATE.FAILED
	unit.velocity = Vector2.ZERO
	if unit.has_node("AnimationPlayer"):
		unit.get_node("AnimationPlayer").stop()

func serialize() -> Dictionary:
	return {
		"type": "MOVE",
		"target_position": {"x": _target_position.x, "y": _target_position.y},
		"state": _state
	}

static func create(position: Vector2) -> UnitActionMove:
	var action := UnitActionMove.new()
	action.setup(position)
	return action

static func create_to_node(node: Node2D) -> UnitActionMove:
	var action := UnitActionMove.new()
	action.setup_to_node(node)
	return action

func setup(position: Vector2) -> void:
	_target_position = position
	_target_node = null

func setup_to_node(node: Node2D) -> void:
	_target_node = node
	if is_instance_valid(node):
		_target_position = node.global_position
