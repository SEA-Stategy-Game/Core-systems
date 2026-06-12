extends GutTest

## -----------------------------------------------------------------------
## Unit tests for UnitActionHarvest.gd
## -----------------------------------------------------------------------
## Uses a lightweight fake resource so the harvest logic is tested in
## isolation from the real resource scenes (timers, progress bars).
## -----------------------------------------------------------------------

const UNIT_SCENE = preload("res://Entities/Units/character_body_2dtets.tscn")

## Minimal stand-in exposing the surface UnitActionHarvest interacts with.
class FakeResource extends Node2D:
	var entity_id: int = 4242
	var totalTime: float = 0.5
	var units_harvesting: int = 0

	func _on_harvest_area_body_entered(_body: Node2D) -> void:
		pass

var unit: Unit
var resource: FakeResource

func before_each() -> void:
	unit = UNIT_SCENE.instantiate() as Unit
	add_child_autofree(unit)
	resource = FakeResource.new()
	add_child_autofree(resource)

func after_each() -> void:
	unit = null
	resource = null

# ----------
# factory
# ----------
func test_create_reads_harvest_duration_from_resource() -> void:
	var action := UnitActionHarvest.create(resource)

	assert_eq(action._harvest_duration, resource.totalTime)
	assert_eq(action._target_node, resource)

# ----------
# lifecycle
# ----------
func test_start_registers_unit_on_resource_counter() -> void:
	var action := UnitActionHarvest.create(resource)

	action.start(unit, resource)

	assert_eq(action._state, IUnitAction.ActionState.RUNNING)
	assert_eq(resource.units_harvesting, 1)

func test_start_with_null_target_fails() -> void:
	var action := UnitActionHarvest.create(null)

	action.start(unit, null)

	assert_eq(action._state, IUnitAction.ActionState.FAILED)

func test_tick_keeps_running_while_resource_is_alive_and_within_time() -> void:
	var action := UnitActionHarvest.create(resource)
	action.start(unit, resource)

	var state: int = action.tick(unit, resource.totalTime)

	assert_eq(state, IUnitAction.ActionState.RUNNING)

func test_tick_completes_when_resource_is_depleted_and_freed() -> void:
	var action := UnitActionHarvest.create(resource)
	action.start(unit, resource)

	resource.free()
	var state: int = action.tick(unit, 0.1)

	assert_eq(state, IUnitAction.ActionState.COMPLETED)

func test_safety_timeout_completes_and_unregisters_the_unit() -> void:
	var action := UnitActionHarvest.create(resource)
	action.start(unit, resource)

	# Elapsed time beyond 3x the expected harvest duration.
	var state: int = action.tick(unit, resource.totalTime * 3.0 + 0.1)

	assert_eq(state, IUnitAction.ActionState.COMPLETED)
	assert_eq(resource.units_harvesting, 0)

func test_cancel_fails_the_action_and_unregisters_the_unit() -> void:
	var action := UnitActionHarvest.create(resource)
	action.start(unit, resource)

	action.cancel(unit)

	assert_eq(action._state, IUnitAction.ActionState.FAILED)
	assert_eq(resource.units_harvesting, 0)

func test_cleanup_never_drives_the_counter_negative() -> void:
	var action := UnitActionHarvest.create(resource)
	action.start(unit, resource)
	resource.units_harvesting = 0  # someone else already unregistered

	action.cancel(unit)

	assert_eq(resource.units_harvesting, 0)

# --------------
# serialization
# --------------
func test_serialize_reports_target_id_and_state() -> void:
	var action := UnitActionHarvest.create(resource)
	action.start(unit, resource)

	var data := action.serialize()

	assert_eq(data["type"], "HARVEST")
	assert_eq(data["target_id"], 4242)
	assert_eq(data["state"], IUnitAction.ActionState.RUNNING)

func test_serialize_reports_negative_target_id_when_resource_is_gone() -> void:
	var action := UnitActionHarvest.create(resource)
	action.start(unit, resource)
	resource.free()

	var data := action.serialize()

	assert_eq(data["target_id"], -1)
