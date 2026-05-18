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

	_push_target_to_agent(unit)

	if unit.has_node("AnimationPlayer"):
		unit.get_node("AnimationPlayer").play("Walk Down")

func tick(unit: CharacterBody2D, _delta: float) -> int:
	if _state != ACTION_STATE.RUNNING:
		return _state

	if is_instance_valid(_target_node):
		var new_pos := _target_node.global_position
		if new_pos.distance_squared_to(_target_position) > 4.0:
			_target_position = new_pos
			_push_target_to_agent(unit)

	var agent: NavigationAgent2D = unit.get_node_or_null("NavigationAgent2D")
	var direction := unit.global_position.direction_to(_target_position)
	var chase_speed := 50.0
	if unit.has_method("get_local_movement_speed"):
		chase_speed = float(unit.get_local_movement_speed())
	var desired_velocity := direction * chase_speed

	if agent != null:
		var nav_finished: bool = agent.is_navigation_finished()
		var dist: float = unit.global_position.distance_to(_target_position)

		if nav_finished or dist <= _arrival_radius:
			unit.velocity = Vector2.ZERO
			_state = ACTION_STATE.COMPLETED
			if unit.has_node("AnimationPlayer"):
				unit.get_node("AnimationPlayer").stop()
		else:
			unit.velocity = desired_velocity
	else:
		unit.velocity = desired_velocity

		if unit.global_position.distance_to(_target_position) <= _arrival_radius:
			unit.velocity = Vector2.ZERO
			_state = ACTION_STATE.COMPLETED
			if unit.has_node("AnimationPlayer"):
				unit.get_node("AnimationPlayer").stop()

	return _state

func cancel(unit: CharacterBody2D) -> void:
	_state = ACTION_STATE.FAILED
	var agent: NavigationAgent2D = unit.get_node_or_null("NavigationAgent2D")
	if agent != null:
		agent.target_position = unit.global_position
	else:
		unit.velocity = Vector2.ZERO
	if unit.has_node("AnimationPlayer"):
		unit.get_node("AnimationPlayer").stop()

func serialize() -> Dictionary:
	return {
		"type": "MOVE",
		"target_position": {"x": _target_position.x, "y": _target_position.y},
		"state": _state
	}

func _push_target_to_agent(unit: CharacterBody2D) -> void:
	var agent: NavigationAgent2D = unit.get_node_or_null("NavigationAgent2D")
	if agent != null:
		agent.target_position = _target_position

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