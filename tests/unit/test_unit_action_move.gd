extends GutTest

## -----------------------------------------------------------------------
## Unit tests for UnitActionMove.gd
## -----------------------------------------------------------------------
## Tests the action's decision logic (state transitions, arrival check,
## factories, serialization) against a real Unit instance.  Actual
## pathfinding across a navmesh is covered by the acceptance tests.
## -----------------------------------------------------------------------

const UNIT_SCENE = preload("res://Entities/Units/character_body_2dtets.tscn")

var unit: Unit

func before_each() -> void:
	unit = UNIT_SCENE.instantiate() as Unit
	add_child_autofree(unit)

func after_each() -> void:
	unit = null

# ----------
# factories
# ----------
func test_create_stores_destination_and_default_radius() -> void:
	var action := UnitActionMove.create(Vector2(120, 40))

	assert_eq(action._target_position, Vector2(120, 40))
	assert_eq(action._arrival_radius, 12.0)

func test_create_accepts_custom_arrival_radius() -> void:
	var action := UnitActionMove.create(Vector2.ZERO, 25.0)

	assert_eq(action._arrival_radius, 25.0)

func test_create_to_node_snapshots_node_position_and_tracks_node() -> void:
	var target := autofree(Node2D.new())
	target.global_position = Vector2(50, 60)

	var action := UnitActionMove.create_to_node(target)

	assert_eq(action._target_position, Vector2(50, 60))
	assert_eq(action._target_node, target)

func test_create_to_node_with_null_target_defaults_to_origin() -> void:
	var action := UnitActionMove.create_to_node(null)

	assert_eq(action._target_position, Vector2.ZERO)
	assert_null(action._target_node)

# ----------
# lifecycle
# ----------
func test_start_sets_state_running_and_forwards_destination_to_unit() -> void:
	var action := UnitActionMove.create(Vector2(100, 0))

	action.start(unit, null)

	assert_eq(action._state, IUnitAction.ActionState.RUNNING)
	assert_eq(unit.get_node("NavigationAgent2D").target_position, Vector2(100, 0))

func test_tick_completes_when_unit_is_within_arrival_radius() -> void:
	unit.global_position = Vector2(200, 200)
	var action := UnitActionMove.create(Vector2(205, 200))
	action.start(unit, null)

	var state: int = action.tick(unit, 0.016)

	assert_eq(state, IUnitAction.ActionState.COMPLETED)
	assert_eq(unit.velocity, Vector2.ZERO)

func test_tick_completes_exactly_at_destination() -> void:
	unit.global_position = Vector2(300, 300)
	var action := UnitActionMove.create(Vector2(300, 300))
	action.start(unit, null)

	var state: int = action.tick(unit, 0.016)

	assert_eq(state, IUnitAction.ActionState.COMPLETED)

func test_cancel_marks_action_failed_and_stops_the_unit() -> void:
	var action := UnitActionMove.create(Vector2(500, 500))
	action.start(unit, null)
	unit.velocity = Vector2(10, 0)

	action.cancel(unit)

	assert_eq(action._state, IUnitAction.ActionState.FAILED)
	assert_eq(unit.velocity, Vector2.ZERO)

func test_tick_after_cancel_stays_failed_and_does_not_resume() -> void:
	var action := UnitActionMove.create(Vector2(500, 500))
	action.start(unit, null)
	action.cancel(unit)

	var state: int = action.tick(unit, 0.016)

	assert_eq(state, IUnitAction.ActionState.FAILED)

# --------------
# serialization
# --------------
func test_serialize_reports_type_target_and_state() -> void:
	var action := UnitActionMove.create(Vector2(7, 9))

	var data := action.serialize()

	assert_eq(data["type"], "MOVE")
	assert_eq(data["target_position"]["x"], 7.0)
	assert_eq(data["target_position"]["y"], 9.0)
	assert_eq(data["state"], IUnitAction.ActionState.PENDING)
