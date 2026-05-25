## UnitActionConstruct.gd
## -----------------------------------------------------------------------
## Concrete IUnitAction -- constructs a building at a target position.
## Assumes the unit is already adjacent (MOVE precedes this action).
## After `build_duration` ticks the building scene is instantiated.
## -----------------------------------------------------------------------
extends RefCounted
class_name UnitActionConstruct

const ActionState = IUnitAction.ActionState

var _state: int = ActionState.PENDING
var _build_position: Vector2 = Vector2.ZERO
var _building_scene_path: String = ""
var _build_duration: float = 10.0
var _elapsed: float = 0.0

# -----------------------------------------------------------------
# IUnitAction contract
# -----------------------------------------------------------------

func start(unit: CharacterBody2D, _target: Node2D) -> void:
	_state = ActionState.RUNNING
	if _target:
		_build_position = _target.global_position

	# Play build animation
	if unit.has_node("AnimationPlayer"):
		var anim: AnimationPlayer = unit.get_node("AnimationPlayer")
		if anim.has_animation("Build"):
			anim.play("Build")
		elif anim.has_animation("Work"):
			anim.play("Work")

func tick(unit: CharacterBody2D, delta: float) -> int:
	if _state != ActionState.RUNNING:
		return _state

	_elapsed += delta
	if _elapsed >= _build_duration:
		_place_building(unit)
		_state = ActionState.COMPLETED
		if unit.has_node("AnimationPlayer"):
			unit.get_node("AnimationPlayer").stop()

	return _state

func cancel(unit: CharacterBody2D) -> void:
	_state = ActionState.FAILED
	if unit.has_node("AnimationPlayer"):
		unit.get_node("AnimationPlayer").stop()

func serialize() -> Dictionary:
	return {
		"type": "CONSTRUCT",
		"building_scene": _building_scene_path,
		"build_position": {"x": _build_position.x, "y": _build_position.y},
		"elapsed": _elapsed,
		"duration": _build_duration,
		"state": _state
	}

# -----------------------------------------------------------------
# Internal
# -----------------------------------------------------------------

func _place_building(unit: CharacterBody2D) -> void:
	if _building_scene_path.is_empty():
		push_warning("UnitActionConstruct: No building scene path specified.")
		return
	var scene = load(_building_scene_path)
	if scene == null:
		push_error("UnitActionConstruct: Failed to load scene: ", _building_scene_path)
		_state = ActionState.FAILED
		return
	var building = scene.instantiate()
	building.global_position = _build_position
	# Add to the Houses container in the scene tree
	var houses_node = unit.get_tree().get_root().get_node_or_null("World/Houses")
	if houses_node:
		houses_node.add_child(building)
	else:
		unit.get_tree().get_root().add_child(building)

# -----------------------------------------------------------------
# Factory
# -----------------------------------------------------------------

static func create(scene_path: String, position: Vector2, duration: float = 10.0) -> UnitActionConstruct:
	var action = UnitActionConstruct.new()
	action._building_scene_path = scene_path
	action._build_position = position
	action._build_duration = duration
	return action
