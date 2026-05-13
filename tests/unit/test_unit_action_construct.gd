extends GutTest

## -----------------------------------------------------------------------
## Unit tests for UnitActionConstruct.gd
## -----------------------------------------------------------------------
## Tests the build-timer state machine.  An empty scene path is used so
## no real building scene is instantiated -- placement into the World is
## scene wiring, not core decision logic.
## -----------------------------------------------------------------------

const UNIT_SCENE = preload("res://Entities/Units/character_body_2dtets.tscn")

var unit: Unit

func before_each() -> void:
	unit = UNIT_SCENE.instantiate() as Unit
	add_child_autofree(unit)

func after_each() -> void:
	unit = null

# ----------
# factory
# ----------
func test_create_stores_scene_position_and_duration() -> void:
	var action := UnitActionConstruct.create("res://Houses/Barracks.tscn", Vector2(64, 32), 5.0)

	assert_eq(action._building_scene_path, "res://Houses/Barracks.tscn")
	assert_eq(action._build_position, Vector2(64, 32))
	assert_eq(action._build_duration, 5.0)

# ----------
# lifecycle
# ----------
func test_start_sets_state_running() -> void:
	var action := UnitActionConstruct.create("", Vector2.ZERO, 1.0)

	action.start(unit, null)

	assert_eq(action._state, IUnitAction.ActionState.RUNNING)

func test_tick_keeps_running_before_build_duration_elapses() -> void:
	var action := UnitActionConstruct.create("", Vector2.ZERO, 1.0)
	action.start(unit, null)

	var state: int = action.tick(unit, 0.4)

	assert_eq(state, IUnitAction.ActionState.RUNNING)

func test_build_time_accumulates_across_ticks() -> void:
	var action := UnitActionConstruct.create("", Vector2.ZERO, 1.0)
	action.start(unit, null)

	action.tick(unit, 0.4)
	action.tick(unit, 0.4)
	var state: int = action.tick(unit, 0.4)

	assert_eq(state, IUnitAction.ActionState.COMPLETED)

func test_tick_does_not_complete_one_tick_early() -> void:
	var action := UnitActionConstruct.create("", Vector2.ZERO, 1.0)
	action.start(unit, null)

	action.tick(unit, 0.5)
	var state: int = action.tick(unit, 0.4)

	assert_eq(state, IUnitAction.ActionState.RUNNING)

func test_cancel_fails_the_action() -> void:
	var action := UnitActionConstruct.create("", Vector2.ZERO, 1.0)
	action.start(unit, null)

	action.cancel(unit)

	assert_eq(action._state, IUnitAction.ActionState.FAILED)

func test_tick_after_cancel_stays_failed() -> void:
	var action := UnitActionConstruct.create("", Vector2.ZERO, 1.0)
	action.start(unit, null)
	action.cancel(unit)

	var state: int = action.tick(unit, 5.0)

	assert_eq(state, IUnitAction.ActionState.FAILED)

# --------------
# serialization
# --------------
func test_serialize_reports_build_parameters_and_progress() -> void:
	var action := UnitActionConstruct.create("res://Houses/Barracks.tscn", Vector2(10, 20), 8.0)
	action.start(unit, null)
	action.tick(unit, 2.0)

	var data := action.serialize()

	assert_eq(data["type"], "CONSTRUCT")
	assert_eq(data["building_scene"], "res://Houses/Barracks.tscn")
	assert_eq(data["build_position"]["x"], 10.0)
	assert_eq(data["build_position"]["y"], 20.0)
	assert_eq(data["elapsed"], 2.0)
	assert_eq(data["duration"], 8.0)
	assert_eq(data["state"], IUnitAction.ActionState.RUNNING)
